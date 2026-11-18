// MCSDKCatalog.m — 车辆人类可读信息与能力目录（全部只读）
#import "MCSDK_Internal.h"
#import "MCConfiguration.h"
#import <objc/message.h>

@implementation MCVehicleInfo
@end

// Vehicle 对象上可探测的能力属性（inventory 全量 30 项，按用户最小范围分组）
static NSDictionary *MCFeatureMap(void) {
    return @{
        @"lockUnlockFeature": @"门锁/车窗/天窗（上锁·解锁·车窗开/关/通风）",
        @"remoteStartFeature": @"远程发动机启停（含 SPIN）",
        @"climaterFeature": @"空调（启停/设置/前后窗加热）",
        @"auxiliaryHeatingFeature": @"辅助加热",
        @"honkFlashFeature": @"寻车（鸣笛/闪灯）",
        @"lastParkingPositionFeature": @"停车位置",
        @"vehicleStatusFeature": @"车况状态（门窗/油量/续航/保养）",
        @"vehicleHealthReportFeature": @"健康报告",
        @"tripStatisticsFeature": @"行程统计",
        @"remoteVehicleStatusFeature": @"远程状态刷新",
        @"batteryChargingFeature": @"充电（旧）",
        @"batteryChargingFeatureV2": @"充电 V2",
        @"remoteBatteryChargingFeature": @"远程充电",
        @"departureTimerFeature": @"出发计划",
        @"remoteProfileTimerFeature": @"空调定时（档位计时）",
        @"antiTheftAlertFeature": @"防盗提醒",
        @"geoFenceAlertFeature": @"地理围栏",
        @"speedAlertFeature": @"速度提醒",
        @"pushSubscriptionsFeature": @"推送订阅",
        @"mobileDevicePairingFeature": @"手机配对（数字钥匙）",
        @"flightModeFeature": @"飞行模式",
        @"remotePretripClimatisationFeature": @"行前空调",
        @"parkingAssistantFeature": @"泊车辅助",
        @"poiFeature": @"兴趣点",
    };
}

@implementation MCSDK (Catalog)

- (void)catalogWithCompletion:(void (^)(NSArray<MCVehicleInfo *> *, NSError *))completion {
    [self vehicleVinsWithCompletion:^(NSArray<NSString *> *vins, NSError *err) {
        if (err || vins.count == 0) { !completion ? : completion(nil, err); return; }
        NSMutableArray *infos = [NSMutableArray array];
        dispatch_group_t group = dispatch_group_create();
        __block NSError *firstErr = nil;
        for (NSString *vin in vins) {
            dispatch_group_enter(group);
            id action = ((id(*)(id,SEL,id,id))objc_msgSend)(self.accountActions,
                @selector(vehicleWithVin:successFunction:), vin,
                ^(id vehicle) {
                    MCVehicleInfo *info = [MCVehicleInfo new];
                    info.vin = vin;
                    info.rawVehicle = vehicle;
                    id vd = MCSafeGet(vehicle, @"vehicleData");
                    if (vd) {
                        info.brand = MCSafeGet(vd, @"brand");
                        info.country = MCSafeGet(vd, @"country");
                        id cp = MCSafeGet(vd, @"carportData");
                        if ([cp respondsToSelector:@selector(modelName)]) {
                            info.modelCode = MCSafeGet(cp, @"modelCode");
                            info.modelName = MCSafeGet(cp, @"modelName");
                            info.modelYear = [MCSafeGet(cp, @"modelYear") description];
                            info.countryCode = MCSafeGet(cp, @"countryCode");
                            info.color = MCSafeGet(cp, @"color");
                            info.engine = MCSafeGet(cp, @"engine");
                            info.transmission = MCSafeGet(cp, @"transmission");
                            info.mmi = MCSafeGet(cp, @"mmi");
                        }
                    }
                    info.displayName = info.modelName.length ? info.modelName
                                        : [vin substringFromIndex:MAX(0, vin.length - 6)];
                    // A feature object exists even for disabled services; inspect the actual enabled flag.
                    NSMutableArray *feats = [NSMutableArray array];
                    NSDictionary *map = MCFeatureMap();
                    for (NSString *key in map) {
                        if (![vehicle respondsToSelector:NSSelectorFromString(key)]) continue;
                        id v = ((id(*)(id,SEL))objc_msgSend)(vehicle, NSSelectorFromString(key));
                        if (v && [MCSafeGet(v, @"serviceEnabled") boolValue]) [feats addObject:key];
                    }
                    info.features = feats;
                    [infos addObject:info];
                    dispatch_group_leave(group);
                });
            ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
                ^(id sdkError) {
                    if (!firstErr) firstErr = [NSError errorWithDomain:@"MCSDK" code:-60
                        userInfo:@{NSLocalizedDescriptionKey:[sdkError description]}];
                    dispatch_group_leave(group);
                });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (infos.count == 0) { !completion ? : completion(nil, firstErr); return; }
            [infos sortUsingComparator:^NSComparisonResult(MCVehicleInfo *a, MCVehicleInfo *b) {
                return [a.vin compare:b.vin];
            }];
            !completion ? : completion(infos, nil);
        });
    }];
}

+ (NSDictionary<NSString *, NSString *> *)featureDescriptions { return MCFeatureMap(); }

+ (NSDictionary<NSString *, NSString *> *)controlCatalog {
    // 控制接口清单（仅展示，PoC 不执行任何物理控制）
    return @{
        @"门锁": @"lockWithStatusFunction: / unlockWithStatusFunction:",
        @"车窗天窗": @"windowSunroofOpen/Close/VentingOpenWithStatusFunction:",
        @"发动机": @"startEngineWithTimestampTrigger:…(SPIN) / stopEngineWithStatusFunction:",
        @"空调": @"start:climatisationSettings: / stop: / update:",
        @"辅助加热": @"startWithStatusFunction: / stopWithStatusFunction:",
        @"寻车": @"HonkFlashService（鸣笛/闪灯，参数待恢复）",
        @"充电": @"ChargerActions start/stop/update(V2)",
        @"出发计划": @"DepartureTimer 系列",
    };
}

- (void)locationOfCurrentVehicleWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (!self.vehicleActions) {
        if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-30
                    userInfo:@{NSLocalizedDescriptionKey: @"尚未选择车辆"}]);
        return;
    }
    id action = ((id(*)(id,SEL,id))objc_msgSend)(self.vehicleActions,
        @selector(locationWithVehicleLocationFunction:),
        ^(id location) {
            if (completion) completion([location description], nil);
        });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id sdkError) {
            NSString *msg = [sdkError description];
            if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-61
                        userInfo:@{NSLocalizedDescriptionKey: msg}]);
        });
}

@end

@implementation MCSDK (StatusQueries)

// 空调状态与门窗细态、健康告警（只读）
- (void)climateStatusWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (!self.vehicleActions) { if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-30 userInfo:@{NSLocalizedDescriptionKey:@"未选车"}]); return; }
    id action = ((id(*)(id,SEL,id))objc_msgSend)(self.vehicleActions,
        @selector(climatisationStatusWithStatusFunction:),
        ^(id st) { if (completion) completion([st description], nil); });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id e) { if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-71 userInfo:@{NSLocalizedDescriptionKey:[e description]}]); });
}

- (void)healthWarningsWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (!self.vehicleActions) { if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-30 userInfo:@{NSLocalizedDescriptionKey:@"未选车"}]); return; }
    id health = MCSafeGet(self.vehicleActions, @"healthReport");
    if (!health) { if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-72 userInfo:@{NSLocalizedDescriptionKey:@"不支持健康报告"}]); return; }
    id action = ((id(*)(id,SEL,id))objc_msgSend)(health, @selector(warningsWithSuccessFunction:),
        ^(id warnings) { if (completion) completion([warnings description], nil); });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id e) { if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-73 userInfo:@{NSLocalizedDescriptionKey:[e description]}]); });
}

@end
