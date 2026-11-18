// 产品信息页的只读白名单；不重新初始化 SDK，不切换到其他车辆。
#import "MCSDK_Internal.h"
#import "MCUI.h"
@implementation MCSDK (Information)
- (void)informationForKey:(NSString *)key completion:(void (^)(id, NSError *))completion {
    NSDictionary *tasks=@{
        @"vehicleStatus":@[@"",@"statusWithStatusFunction:"],
        @"climateStatus":@[@"",@"climatisationStatusWithStatusFunction:"],
        @"pretripClimateStatus":@[@"",@"remotePretripClimatisationStatusWithStatusFunction:"],
        @"chargerStatus":@[@"",@"chargerStatusWithStatusFunction:"],
        @"chargerStatusV2":@[@"",@"chargerStatusV2WithStatusFunction:"],
        @"auxiliaryHeatingStatus":@[@"",@"auxiliaryHeatingStatusWithStatusFunction:"],
        @"pairingStatus":@[@"",@"mobileDevicePairingStatusWithStatusFunction:"],
        @"honkFlashConfiguration":@[@"",@"honkAndFlashConfigurationWithStatusFunction:"],
        @"vehicleUsers":@[@"",@"vehicleUsersWithSuccessFunction:"],
        @"healthWarnings":@[@"healthReport",@"warningsWithSuccessFunction:"],
        @"engineHistory":@[@"remoteStart",@"getHistoryWithSuccessFunction:"],
        @"enginePairStatus":@[@"remoteStart",@"getLastPairStatusWithSuccessFunction:"],
        @"departureConfiguration":@[@"departureTimer",@"configurationWithSuccessFunction:"],
        @"profileTimers":@[@"profileTimer",@"getTimersAndProfilesWithSuccessFunction:"],
        @"remoteProfileTimer":@[@"",@"remoteProfileTimerWithSuccessFunction:"],
        @"geofenceDefinitions":@[@"geofenceAlerts",@"definitionsWithStatusFunction:"],
        @"geofenceNotifications":@[@"geofenceAlerts",@"notificationsWithStatusFunction:"],
        @"speedDefinitions":@[@"speedAlerts",@"definitionsWithStatusFunction:"],
        @"speedNotifications":@[@"speedAlerts",@"notificationsWithStatusFunction:"],
        @"antiTheftNotifications":@[@"antiTheftAlerts",@"notificationsWithStatusFunction:"],
        @"pairingLastStatus":@[@"mobileDevicePairing",@"getLastPairStatusWithSuccessFunction:"]
    };
    void (^finish)(id,NSError *)=^(id data,NSError *error){ dispatch_async(dispatch_get_main_queue(),^{completion(data,error);}); };
    if(!self.vehicleActions) { finish(nil,[NSError errorWithDomain:@"MCInformation" code:1 userInfo:@{NSLocalizedDescriptionKey:@"车辆尚未就绪，请返回主页重试"}]);return; }
    if([key hasPrefix:@"trips"]) {
        NSDictionary *types=@{@"tripsLongTerm":@0,@"tripsShortTerm":@1,@"tripsCyclic":@2};
        if(!types[key]) { finish(nil,[NSError errorWithDomain:@"MCInformation" code:2 userInfo:@{NSLocalizedDescriptionKey:@"未知查询"}]); return; }
        id action=((id(*)(id,SEL,NSInteger,id))objc_msgSend)(self.vehicleActions,@selector(tripStatisticsWithTripType:statusFunction:),[types[key] integerValue],^(id value){finish(MCInformationSnapshot(value,10),nil);});
        ((void(*)(id,SEL,id))objc_msgSend)(action,@selector(loadWithErrorFunction:),^(id error){finish(nil,[NSError errorWithDomain:@"MCInformation" code:3 userInfo:@{NSLocalizedDescriptionKey:@"当前车辆暂未提供此类行程"}]);});return;
    }
    NSArray *task=tasks[key];id target=task?([task[0] length]?MCSafeGet(self.vehicleActions,task[0]):self.vehicleActions):nil;
    SEL selector=task?NSSelectorFromString(task[1]):NULL;
    if(!target || !selector || ![target respondsToSelector:selector]) { finish(nil,[NSError errorWithDomain:@"MCInformation" code:4 userInfo:@{NSLocalizedDescriptionKey:@"当前车辆或服务暂不支持此项查询"}]);return; }
    id action=((id(*)(id,SEL,id))objc_msgSend)(target,selector,^(id value){finish(MCInformationSnapshot(value,10),nil);});
    SEL run=@selector(loadWithErrorFunction:);
    if(![action respondsToSelector:run]) {
        if([@[@"engineHistory",@"enginePairStatus",@"profileTimers",@"pairingLastStatus"] containsObject:key] && [action respondsToSelector:@selector(executeWithErrorFunction:)]) run=@selector(executeWithErrorFunction:);
        else { finish(nil,[NSError errorWithDomain:@"MCInformation" code:5 userInfo:@{NSLocalizedDescriptionKey:@"此项查询当前不可用"}]);return; }
    }
    ((void(*)(id,SEL,id))objc_msgSend)(action,run,^(id error){finish(nil,[NSError errorWithDomain:@"MCInformation" code:6 userInfo:@{NSLocalizedDescriptionKey:@"暂时无法读取，请稍后刷新；也可能是当前车辆尚未开通此服务"}]);});
}
@end
