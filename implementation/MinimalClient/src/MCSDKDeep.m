// MCSDKDeep.m — 深度探测：SDK 门面下全部剩余查询（只读）+ 权限地图
#import "MCSDK_Internal.h"
#import <objc/message.h>

static NSString *NS(id o) { return o ? [o description] : @"<nil>"; }
static NSString *KVC(id o, NSString *k) { @try { return NS([o valueForKey:k]); } @catch (id e) { return @"<无此键>"; } }

static void RunQuery(id target, id action, NSString *name, void (^onLine)(NSString *)) {
    if (!action) { onLine([NSString stringWithFormat:@"%@: 动作构造失败", name]); return; }
    ((void(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id e) { onLine([NSString stringWithFormat:@"%@: ✗ %@", name, [e description]]); });
}
static id Action1(id target, SEL sel, id block) {
    return ((id(*)(id,SEL,id))objc_msgSend)(target, sel, block);
}
static id FacadeSub(id vehicleActions, NSString *prop) {
    @try { return [vehicleActions valueForKey:prop]; } @catch (id e) { return nil; }
}

@implementation MCSDK (Deep)

- (void)deepProbeAll:(void (^)(NSString *line))onLine {
    dispatch_async(dispatch_get_main_queue(), ^{
        id va = self.vehicleActions;
        if (!va) { onLine(@"未选车"); return; }
        NSMutableArray<void (^)(void)> *tasks = [NSMutableArray array];
        void (^add)(NSString *, void (^)(void (^)(NSString *))) = ^(NSString *name, void (^work)(void (^)(NSString *))) {
            [tasks addObject:^{ work(^(NSString *result) { onLine([NSString stringWithFormat:@"%@: %@", name, result]); }); }];
        };

        add(@"车辆用户", ^(void (^done)(NSString *)) {
            id a = Action1(va, @selector(vehicleUsersWithSuccessFunction:), ^(id users){ done(NS(users)); });
            RunQuery(va, a, @"车辆用户", onLine);
        });
        add(@"启动历史", ^(void (^done)(NSString *)) {
            id sub = FacadeSub(va, @"remoteStart");
            if (!sub) { done(@"车辆不支持"); return; }
            id a = Action1(sub, @selector(getHistoryWithSuccessFunction:), ^(id h){ done(NS(h)); });
            RunQuery(sub, a, @"启动历史", onLine);
        });
        add(@"寻车配置", ^(void (^done)(NSString *)) {
            id a = Action1(va, @selector(honkAndFlashConfigurationWithStatusFunction:), ^(id c){
                done([NSString stringWithFormat:@"最长 %@s 距离 %@ 禁鸣 %@ 禁闪 %@",
                    KVC(c,@"maximumServiceDuration"), KVC(c,@"maximumDistanceToVehicle"),
                    KVC(c,@"honkForbidden"), KVC(c,@"flashForbidden")]); });
            RunQuery(va, a, @"寻车配置", onLine);
        });
        add(@"出发计划", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"departureTimer") ? @"支持（配置读取待接）" : @"车辆不支持"); });
        add(@"空调定时", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"profileTimer") ? @"支持（档位读取待接）" : @"车辆不支持"); });
        add(@"地理围栏", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"geofenceAlerts") ?: @"车辆不支持/未配置"); });
        add(@"速度提醒", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"speedAlerts") ?: @"车辆不支持/未配置"); });
        add(@"防盗告警", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"antiTheftAlerts") ?: @"车辆不支持/未配置"); });
        add(@"手机配对", ^(void (^done)(NSString *)) {
            done(FacadeSub(va, @"mobileDevicePairing") ?: @"车辆不支持"); });
        add(@"充电状态", ^(void (^done)(NSString *)) {
            id a = Action1(va, @selector(chargerStatusWithStatusFunction:), ^(id s){ done(NS(s)); });
            RunQuery(va, a, @"充电状态", onLine);
        });
        add(@"门窗细态", ^(void (^done)(NSString *)) {
            id a = Action1(va, @selector(statusWithStatusFunction:), ^(id st){
                id body = nil;
                @try { body = [st valueForKey:@"bodyStatus"]; } @catch (id e) {}
                done(body ? [NSString stringWithFormat:@"%@", NS(body)] : @"无 bodyStatus"); });
            RunQuery(va, a, @"门窗细态", onLine);
        });

        __block void (^next)(NSUInteger) = nil;
        next = ^(NSUInteger idx) {
            if (idx >= tasks.count) { onLine(@"—— 深度探测完成 ——"); return; }
            tasks[idx]();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ next(idx + 1); });
        };
        next(0);
    });
}

- (void)rawOperationListForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    NSString *uid = nil;
    @try { uid = [self.account valueForKey:@"mbbUserId"]; } @catch (id e) {}
    if (![uid isKindOfClass:NSString.class]) {
        if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-81
            userInfo:@{NSLocalizedDescriptionKey: @"无 mbbUserId（未登录）"}]);
        return;
    }
    [self rawGet:[NSString stringWithFormat:
        @"https://mal-3a.prd.cn.dp.vwg-connect.cn/api/rolesrights/operationlist/v3/vehicles/%@/users/%@", vin, uid]
        accept:@"application/vnd.vwg.mbb.operationList_v3_0_2+xml, application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml"
        completion:completion];
}

- (void)rawHomeRegionForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    [self rawGet:[NSString stringWithFormat:
        @"https://mal-1a.prd.cn.vwg-connect.cn/api/cs/vds/v1/vehicles/%@/homeRegion", vin]
        accept:@"application/json"
        completion:completion];
}

@end
