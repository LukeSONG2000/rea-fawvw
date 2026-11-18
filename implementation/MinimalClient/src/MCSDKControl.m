// MCSDKControl.m — Control adapters. UI confirmation remains required; capability evidence is not execution proof.
// Protected action: securityPinWithSecurityPin: -> ExecutableAction.executeWithErrorFunction:
// SPIN 仅存内存（MCSDK.spinCode），不落盘、不打印。
#import "MCSDK_Internal.h"
#import <objc/message.h>

static NSString *MCNullStr(NSString *s) { return s ?: @""; }

// 执行 action；若为 SPIN 保护动作且已设置 SPIN，则先换取 runnable
static void Execute(id action, NSString *_Nullable spin,
                    void (^onError)(NSString *)) {
    if (!action) { onError(@"指令构造失败"); return; }
    id runnable = action;
    if ([action respondsToSelector:@selector(securityPinWithSecurityPin:)]) {
        if (!spin.length) { onError(@"此操作需要 SPIN 安全码"); return; }
        runnable = ((id(*)(id,SEL,id))objc_msgSend)(action,
                      @selector(securityPinWithSecurityPin:), spin);
        if (!runnable) { onError(@"SPIN 被拒绝（码错误或被锁）"); return; }
    }
    if (![runnable respondsToSelector:@selector(executeWithErrorFunction:)]) { onError(@"SDK 未提供该控制动作的执行入口"); return; }
    ((void(*)(id,SEL,id))objc_msgSend)(runnable, @selector(executeWithErrorFunction:),
        ^(id sdkError) { onError(MCNullStr([sdkError description])); });
}

// 单参数指令：[subActions xxxWithStatusFunction:block]
static void RunStatusCommand(id vehicleActions, NSString *facadeProp, SEL command,
                             NSString *spin, void (^onStatus)(NSString *),
                             void (^onError)(NSString *)) {
    if (!vehicleActions) { onError(@"未选车"); return; }
    id sub = MCSafeGet(vehicleActions, facadeProp);
    if (!sub) { onError([NSString stringWithFormat:@"车辆不支持 %@", facadeProp]); return; }
    if (![sub respondsToSelector:command]) { onError(@"SDK 未暴露此控制接口"); return; }
    id action = ((id(*)(id,SEL,id))objc_msgSend)(sub, command,
        ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, spin, onError);
}

// 双参数（鸣笛/闪灯）
static void RunHonkFlash(id vehicleActions, SEL command, NSUInteger duration,
                         void (^onStatus)(NSString *), void (^onError)(NSString *)) {
    if (!vehicleActions) { onError(@"未选车"); return; }
    // Honk/flash methods live directly on VehicleActionsImpl, not a honkAndFlash property.
    id sub = vehicleActions;
    if (![sub respondsToSelector:command]) { onError(@"SDK 未提供此寻车接口"); return; }
    Class paramCls = NSClassFromString(@"_TtC9CarNetLib21HonkAndFlashParameter");
    if (!paramCls) { onError(@"HonkAndFlashParameter 类缺失"); return; }
    id param = ((id(*)(id,SEL,NSUInteger))objc_msgSend)([paramCls alloc],
                 @selector(initWithDuration:), duration);
    id action = ((id(*)(id,SEL,id,id))objc_msgSend)(sub, command, param,
        ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, nil, onError);
}

@implementation MCSDK (Control)

- (void)flashLights:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunHonkFlash(self.vehicleActions, @selector(flashWithParameter:successFunction:), 5, onStatus, onError);
}
- (void)honkAndFlash:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunHonkFlash(self.vehicleActions, @selector(honkAndFlashWithParameter:successFunction:), 5, onStatus, onError);
}
- (void)lockVehicle:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteLockUnlock",
                     @selector(lockWithStatusFunction:), self.spinCode, onStatus, onError);
}
- (void)unlockVehicle:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteLockUnlock",
                     @selector(unlockWithStatusFunction:), self.spinCode, onStatus, onError);
}
- (void)windowVenting:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteLockUnlock",
                     @selector(windowSunroofVentingOpenWithStatusFunction:), self.spinCode, onStatus, onError);
}
- (void)windowOpen:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteLockUnlock",
                     @selector(windowSunroofOpenWithStatusFunction:), self.spinCode, onStatus, onError);
}
- (void)windowClose:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteLockUnlock",
                     @selector(windowSunroofCloseWithStatusFunction:), self.spinCode, onStatus, onError);
}

// 空调：start:climatisationSettings:（heaterSource=0 自动，22℃，不用外接电源）
- (void)climateStart:(double)tempC
           onStatus:(void (^)(NSString *))onStatus
              error:(void (^)(NSString *))onError {
    if (!self.vehicleActions) { onError(@"未选车"); return; }
    id sub = MCSafeGet(self.vehicleActions, @"climatisation");
    if (!sub) { onError(@"车辆不支持空调"); return; }
    Class tempCls = NSClassFromString(@"_TtC9CarNetLib16TemperatureValue");
    Class setCls  = NSClassFromString(@"_TtC9CarNetLib21ClimatisationSettings");
    if (!tempCls || !setCls) { onError(@"空调参数类缺失"); return; }
    id temp = ((id(*)(id,SEL,double,long))objc_msgSend)([tempCls alloc],
                @selector(initWithTemperature:unit:), tempC, 0 /* celsius */);
    id settings = ((id(*)(id,SEL,long,id,BOOL))objc_msgSend)([setCls alloc],
                @selector(initWithHeaterSource:targetTemperature:useWithoutExternalPower:),
                0 /* automatic */, temp, YES);
    id action = ((id(*)(id,SEL,NSInteger,id,id))objc_msgSend)(sub,
                @selector(start:climatisationSettings:successFunction:),
                (NSInteger)0 /* enum argument; vehicle-specific validity must be verified */, settings,
                ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, nil, onError);
}
- (void)climateStop:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    id sub=MCSafeGet(self.vehicleActions,@"climatisation");
    SEL selector=@selector(stop:successFunction:);
    if (![sub respondsToSelector:selector]) { onError(@"SDK 未提供空调停止接口"); return; }
    id action=((id(*)(id,SEL,NSInteger,id))objc_msgSend)(sub,selector,(NSInteger)0,^(id status){onStatus(MCNullStr([status description]));});
    Execute(action,nil,onError);
}

// 辅助加热（门面 remoteAuxiliaryHeating）
- (void)auxHeatStart:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteAuxiliaryHeating",
                     @selector(startWithStatusFunction:), nil, onStatus, onError);
}
- (void)auxHeatStop:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteAuxiliaryHeating",
                     @selector(stopWithStatusFunction:), nil, onStatus, onError);
}

// 发动机启停（SPIN 必需）
- (void)engineStartWithSpin:(NSString *)spin
                  onStatus:(void (^)(NSString *))onStatus
                     error:(void (^)(NSString *))onError {
    if (!self.vehicleActions) { onError(@"未选车"); return; }
    if (spin.length == 0) { onError(@"需要 SPIN"); return; }
    id sub = MCSafeGet(self.vehicleActions, @"remoteStart");
    if (!sub) { onError(@"车辆不支持远程启动"); return; }
    NSDate *now = [NSDate date];
    // SPIN 输入起止时间戳防重放：这里以当下为界（首末位输入时刻）
    id action = ((id(*)(id,SEL,id,id,id,id))objc_msgSend)(sub,
        @selector(startEngineWithTimestampTrigger:timestampFirstDigitSpin:timestampLastDigitSpin:statusFunction:),
        now, now, now,
        ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, spin, onError);
}
- (void)engineStop:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"remoteStart",
                     @selector(stopEngineWithStatusFunction:), nil, onStatus, onError);
}

@end
