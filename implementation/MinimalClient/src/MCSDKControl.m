// MCSDKControl.m — 物理控制全量接口（用户已明确授权执行）
// SPIN 保护动作：securityPinWithSecurityPin: → loadWithErrorFunction:
// SPIN 仅存内存（MCSDK.spinCode），不落盘、不打印。
#import "MCSDK_Internal.h"
#import <objc/message.h>

static NSString *MCNullStr(NSString *s) { return s ?: @""; }

// 执行 action；若为 SPIN 保护动作且已设置 SPIN，则先换取 runnable
static void Execute(id action, NSString *_Nullable spin,
                    void (^onError)(NSString *)) {
    if (!action) { onError(@"指令构造失败"); return; }
    id runnable = action;
    if (spin.length > 0 && [action respondsToSelector:@selector(securityPinWithSecurityPin:)]) {
        runnable = ((id(*)(id,SEL,id))objc_msgSend)(action,
                      @selector(securityPinWithSecurityPin:), spin);
        if (!runnable) { onError(@"SPIN 被拒绝（码错误或被锁）"); return; }
    }
    ((void(*)(id,SEL,id))objc_msgSend)(runnable, @selector(loadWithErrorFunction:),
        ^(id sdkError) { onError(MCNullStr([sdkError description])); });
}

// 单参数指令：[subActions xxxWithStatusFunction:block]
static void RunStatusCommand(id vehicleActions, NSString *facadeProp, SEL command,
                             NSString *spin, void (^onStatus)(NSString *),
                             void (^onError)(NSString *)) {
    if (!vehicleActions) { onError(@"未选车"); return; }
    id sub = nil;
    @try { sub = [vehicleActions valueForKey:facadeProp]; } @catch (id e) {}
    if (!sub) { onError([NSString stringWithFormat:@"车辆不支持 %@", facadeProp]); return; }
    id action = ((id(*)(id,SEL,id))objc_msgSend)(sub, command,
        ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, spin, onError);
}

// 双参数（鸣笛/闪灯）
static void RunHonkFlash(id vehicleActions, SEL command, NSUInteger duration,
                         void (^onStatus)(NSString *), void (^onError)(NSString *)) {
    if (!vehicleActions) { onError(@"未选车"); return; }
    id sub = nil;
    @try { sub = [vehicleActions valueForKey:@"honkAndFlash"]; } @catch (id e) {}
    if (!sub) { onError(@"车辆不支持寻车"); return; }
    Class paramCls = NSClassFromString(@"_TtC9CarNetLib21HonkAndFlashParameter");
    if (!paramCls) { onError(@"HonkAndFlashParameter 类缺失"); return; }
    id param = ((id(*)(id,SEL,NSUInteger))objc_msgSend)([paramCls new],
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
    id sub = nil;
    @try { sub = [self.vehicleActions valueForKey:@"climatisation"]; } @catch (id e) {}
    if (!sub) { onError(@"车辆不支持空调"); return; }
    Class tempCls = NSClassFromString(@"_TtC9CarNetLib16TemperatureValue");
    Class setCls  = NSClassFromString(@"_TtC9CarNetLib21ClimatisationSettings");
    if (!tempCls || !setCls) { onError(@"空调参数类缺失"); return; }
    id temp = ((id(*)(id,SEL,double,long))objc_msgSend)([tempCls new],
                @selector(initWithTemperature:unit:), tempC, 0 /* celsius */);
    id settings = ((id(*)(id,SEL,long,id,BOOL))objc_msgSend)([setCls new],
                @selector(initWithHeaterSource:targetTemperature:useWithoutExternalPower:),
                0 /* automatic */, temp, YES);
    id action = ((id(*)(id,SEL,id,id,id))objc_msgSend)(sub,
                @selector(start:climatisationSettings:successFunction:),
                nil /* 无 timerId */, settings,
                ^(id status) { onStatus(MCNullStr([status description])); });
    Execute(action, nil, onError);
}
- (void)climateStop:(void (^)(NSString *))onStatus error:(void (^)(NSString *))onError {
    RunStatusCommand(self.vehicleActions, @"climatisation",
                     @selector(stopWithSuccessFunction:), nil, onStatus, onError);
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
    id sub = nil;
    @try { sub = [self.vehicleActions valueForKey:@"remoteStart"]; } @catch (id e) {}
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
