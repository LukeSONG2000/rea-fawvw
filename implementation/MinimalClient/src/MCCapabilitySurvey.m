// A sequential, persisted, strictly read-only per-vehicle capability survey.
#import "MCCapabilitySurvey.h"
#import "MCSDK_Internal.h"
#import "MCConfiguration.h"
#import <sys/stat.h>

static id Snapshot(id value, NSUInteger depth) {
    if (!value) return NSNull.null;
    if ([value isKindOfClass:NSString.class]) return [value length]>30000 ? [[value substringToIndex:30000] stringByAppendingString:@"…"] : value;
    if ([value isKindOfClass:NSNumber.class] || value==NSNull.null) return value;
    if ([value isKindOfClass:NSDate.class]) return @([value timeIntervalSince1970]);
    if ([value isKindOfClass:NSSet.class]) value=[value allObjects];
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *a=[NSMutableArray array]; NSUInteger limit=MIN([value count],100);
        for(NSUInteger i=0;i<limit;i++) [a addObject:depth ? Snapshot(value[i],depth-1) : @"<depth-limit>"];
        return @{@"count":@([value count]),@"items":a};
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *d=[NSMutableDictionary dictionary];
        for(id key in value) if ([key isKindOfClass:NSString.class] && d.count<100) d[key]=depth ? Snapshot(value[key],depth-1):@"<depth-limit>";
        return d;
    }
    NSMutableDictionary *d=[NSMutableDictionary dictionaryWithObject:NSStringFromClass(object_getClass(value)) forKey:@"_class"];
    if (!depth) return d;
    NSSet *deny=[NSSet setWithArray:@[@"accessToken",@"refreshToken",@"identityToken",@"mbbTokens",@"account",@"token",@"hash",@"superclass",@"description",@"debugDescription"]];
    for(Class c=object_getClass(value);c && c!=NSObject.class;c=class_getSuperclass(c)) {
        unsigned int count=0; objc_property_t *props=class_copyPropertyList(c,&count);
        for(unsigned int i=0;i<count && d.count<90;i++) {
            NSString *name=@(property_getName(props[i])); if ([deny containsObject:name]) continue;
            const char *attr=property_getAttributes(props[i]); NSString *getter=name;
            if(attr) {
                NSString *attrs=@(attr);
                for(NSString *part in [attrs componentsSeparatedByString:@","]) if([part hasPrefix:@"G"]) getter=[part substringFromIndex:1];
            }
            @try { d[name]=Snapshot(MCSafeGet(value,getter),depth-1); } @catch(NSException *e) { d[name]=@"<getter-exception>"; }
        }
        free(props);
    }
    return d;
}

@interface MCCapabilitySurvey ()
@property(nonatomic,strong) NSMutableDictionary *report;
@property(nonatomic,strong) NSMutableArray *vehicles;
@property(nonatomic,strong) NSMutableArray *tasks;
@property(nonatomic,strong) NSMutableArray *queries;
@property(nonatomic,copy) void (^progress)(NSString *);
@property(nonatomic,copy) NSString *directory;
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) id retainedAction;
@property(nonatomic,strong) id surveyActions;
@property(nonatomic,copy) NSString *regionBase;
@property(nonatomic) NSUInteger vehicleIndex;
@property(nonatomic) NSUInteger taskIndex;
@end
@implementation MCCapabilitySurvey
+ (void)runWithProgress:(void (^)(NSString *))progress {
    static MCCapabilitySurvey *active;
    if (active && ![@[@"complete",@"authentication-failed",@"init-failed",@"missing-session",@"listing-failed"] containsObject:active.report[@"state"]?:@""]) { if(progress) progress(@"已有能力调查正在运行"); return; }
    active=[MCCapabilitySurvey new]; active.progress=progress;
    [active start];
}
- (void)save {
    NSString *p=[self.directory stringByAppendingPathComponent:@"survey.json"];
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.report options:NSJSONWritingPrettyPrinted error:&error];
    if(!data) { NSLog(@"[MC Survey] result serialization failed: %@",error.localizedDescription); return; }
    [data writeToFile:p options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error];
    chmod(p.fileSystemRepresentation,0600);
}
- (void)emit:(NSString *)message { if(self.progress) self.progress(message); }
- (void)start {
    self.directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/capability-survey"];
    [NSFileManager.defaultManager createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    self.vehicles=[NSMutableArray array];
    self.report=[@{@"surveyVersion":@3,@"started":@([NSDate.date timeIntervalSince1970]),@"physicalCommandsSent":@NO,@"state":@"initializing",@"vehicles":self.vehicles} mutableCopy]; [self save];
    NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest=18; cfg.timeoutIntervalForResource=22;
    self.session=[NSURLSession sessionWithConfiguration:cfg];
    NSString *token=[NSUserDefaults.standardUserDefaults stringForKey:@"imported.idToken"];
    if(!token.length) { self.report[@"state"]=@"missing-session"; [self save]; [self emit:@"缺少身份会话"]; return; }
    [[MCSDK shared] initializeSDK:^(NSError *e) {
        if(e) { self.report[@"state"]=@"init-failed"; self.report[@"error"]=e.localizedDescription; [self save]; return; }
        [[MCSDK shared] loginMBBWithIdentityToken:token completion:^(NSError *error) {
            if(error) { self.report[@"state"]=@"authentication-failed"; self.report[@"error"]=error.localizedDescription; [self save]; return; }
            self.report[@"state"]=@"listing"; [self save];
            [[MCSDK shared] vehicleVinsWithCompletion:^(NSArray<NSString *> *vins,NSError *listError) {
                dispatch_async(dispatch_get_main_queue(),^{
                    if(listError) { self.report[@"state"]=@"listing-failed"; self.report[@"error"]=listError.localizedDescription; [self save]; return; }
                    self.report[@"vehicleCount"]=@(vins.count);
                    [self inspectVins:vins atIndex:0];
                });
            }];
        }];
    }];
}
- (void)inspectVins:(NSArray *)vins atIndex:(NSUInteger)index {
    if(index>=vins.count) { self.report[@"state"]=@"complete"; self.report[@"finished"]=@([NSDate.date timeIntervalSince1970]); [self save]; [self emit:@"逐车能力调查完成，结果已保存"]; [self.session finishTasksAndInvalidate]; return; }
    self.vehicleIndex=index; self.report[@"state"]=@"surveying";
    NSString *vin=vins[index];
    id action=((id(*)(id,SEL,id,id))objc_msgSend)([MCSDK shared].accountActions,@selector(vehicleWithVin:successFunction:),vin,^(id vehicle){
        dispatch_async(dispatch_get_main_queue(),^{
            self.surveyActions=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"_TtC9CarNetLib9CarNetLib"),@selector(useVehicle:),vehicle);
            NSMutableDictionary *row=[@{@"index":@(index),@"vin":vin,@"vehicleData":Snapshot(MCSafeGet(vehicle,@"vehicleData"),4)} mutableCopy];
            NSMutableDictionary *features=[NSMutableDictionary dictionary];
            for(NSString *key in [MCSDK featureDescriptions]) features[key]=Snapshot(MCSafeGet(vehicle,key),5);
            row[@"features"]=features;
            row[@"vehicleOperations"]=Snapshot(MCSafeGet(vehicle,@"vehicleOperations"),5);
            row[@"isInFlightMode"]=Snapshot(MCSafeGet(vehicle,@"isInFlightMode"),1);
            row[@"userRole"]=Snapshot(MCSafeGet(vehicle,@"userRole"),1);
            self.queries=[NSMutableArray array]; row[@"queries"]=self.queries; [self.vehicles addObject:row]; [self save];
            [self resolveHomeRegion:vin completion:^(NSDictionary *resolution) {
                row[@"homeRegionResolution"]=resolution;
                [self buildTasksForVIN:vin]; self.taskIndex=0;
                [self runNextWithCompletion:^{ [self inspectVins:vins atIndex:index+1]; }];
            }];
        });
    });
    self.retainedAction=action;
    ((void(*)(id,SEL,id))objc_msgSend)(action,@selector(loadWithErrorFunction:),^(id error){
        dispatch_async(dispatch_get_main_queue(),^{
            [self.vehicles addObject:@{@"index":@(index),@"selectionError":Snapshot(error,4)}]; [self save];
            [self inspectVins:vins atIndex:index+1];
        });
    });
}
- (void)resolveHomeRegion:(NSString *)vin completion:(void (^)(NSDictionary *))completion {
    self.regionBase=nil;
    NSString *url=[NSString stringWithFormat:@"%@/cs/vds/v1/vehicles/%@/homeRegion",MCMbbMalServerURL,vin];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setValue:[@"Bearer " stringByAppendingString:[MCSDK shared].mbbAccessToken?:@""] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"en-US" forHTTPHeaderField:@"Accept-Language"];
    [req setValue:@"BootstrapApp" forHTTPHeaderField:@"x-app-name"];
    [req setValue:@"1.0" forHTTPHeaderField:@"x-app-version"];
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
        id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSString *base=[json isKindOfClass:NSDictionary.class]?json[@"homeRegion"][@"baseUri"][@"content"]:nil;
        NSURL *baseURL=[base isKindOfClass:NSString.class]?[NSURL URLWithString:base]:nil;
        BOOL valid=!error && status==200 && [baseURL.scheme isEqualToString:@"https"] && [baseURL.host hasSuffix:@".vwg-connect.cn"];
        dispatch_async(dispatch_get_main_queue(),^{
            self.regionBase=valid?[base stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]:nil;
            completion(@{@"httpStatus":@(status),@"baseURI":self.regionBase?:@"",@"resolved":@(valid)});
        });
    }] resume];
}
- (void)addQuery:(NSString *)name facade:(NSString *)facade selector:(NSString *)selector {
    [self.tasks addObject:@{@"name":name,@"kind":@"sdk",@"facade":facade?:@"",@"selector":selector}];
}
- (void)buildTasksForVIN:(NSString *)vin {
    self.tasks=[NSMutableArray array];
    [self addQuery:@"vehicleStatus" facade:nil selector:@"statusWithStatusFunction:"];
    [self addQuery:@"parkingPosition" facade:nil selector:@"locationWithVehicleLocationFunction:"];
    [self addQuery:@"climateStatus" facade:nil selector:@"climatisationStatusWithStatusFunction:"];
    [self addQuery:@"pretripClimateStatus" facade:nil selector:@"remotePretripClimatisationStatusWithStatusFunction:"];
    [self addQuery:@"chargerStatus" facade:nil selector:@"chargerStatusWithStatusFunction:"];
    [self addQuery:@"chargerStatusV2" facade:nil selector:@"chargerStatusV2WithStatusFunction:"];
    [self addQuery:@"auxiliaryHeatingStatus" facade:nil selector:@"auxiliaryHeatingStatusWithStatusFunction:"];
    [self addQuery:@"pairingStatus" facade:nil selector:@"mobileDevicePairingStatusWithStatusFunction:"];
    [self addQuery:@"honkFlashConfiguration" facade:nil selector:@"honkAndFlashConfigurationWithStatusFunction:"];
    [self addQuery:@"vehicleUsers" facade:nil selector:@"vehicleUsersWithSuccessFunction:"];
    [self addQuery:@"healthWarnings" facade:@"healthReport" selector:@"warningsWithSuccessFunction:"];
    [self addQuery:@"engineHistory" facade:@"remoteStart" selector:@"getHistoryWithSuccessFunction:"];
    [self addQuery:@"enginePairStatus" facade:@"remoteStart" selector:@"getLastPairStatusWithSuccessFunction:"];
    [self addQuery:@"departureConfiguration" facade:@"departureTimer" selector:@"configurationWithSuccessFunction:"];
    [self addQuery:@"profileTimers" facade:@"profileTimer" selector:@"getTimersAndProfilesWithSuccessFunction:"];
    [self addQuery:@"remoteProfileTimer" facade:nil selector:@"remoteProfileTimerWithSuccessFunction:"];
    [self addQuery:@"geofenceDefinitions" facade:@"geofenceAlerts" selector:@"definitionsWithStatusFunction:"];
    [self addQuery:@"geofenceNotifications" facade:@"geofenceAlerts" selector:@"notificationsWithStatusFunction:"];
    [self addQuery:@"speedDefinitions" facade:@"speedAlerts" selector:@"definitionsWithStatusFunction:"];
    [self addQuery:@"speedNotifications" facade:@"speedAlerts" selector:@"notificationsWithStatusFunction:"];
    [self addQuery:@"antiTheftNotifications" facade:@"antiTheftAlerts" selector:@"notificationsWithStatusFunction:"];
    [self addQuery:@"pairingLastStatus" facade:@"mobileDevicePairing" selector:@"getLastPairStatusWithSuccessFunction:"];
    // SDK TripType rawValue initializer and description establish 0=longTerm,1=shortTerm,2=cyclic.
    for(NSDictionary *trip in @[@{@"name":@"tripsLongTerm",@"type":@0},@{@"name":@"tripsShortTerm",@"type":@1},@{@"name":@"tripsCyclic",@"type":@2}])
        [self.tasks addObject:@{@"name":trip[@"name"],@"kind":@"trips",@"tripType":trip[@"type"]}];
    NSString *uid=MCSafeGet([MCSDK shared].account,@"mbbUserId");
    NSArray *raw=@[
        @[@"vehicleData",[NSString stringWithFormat:@"%@/vehicleMgmt/vehicledata/v2/vehicles/%@",self.regionBase?:@"",vin],@"application/vnd.vwg.mbb.vehicleDataDetail_v2_1_0+xml"],
        @[@"statusReport",[NSString stringWithFormat:@"%@/bs/vsr/v1/vehicles/%@/status",self.regionBase?:@"",vin],@"application/vnd.vwg.mbb.VehicleStatusReport_v1_0_0+xml"],
        @[@"operationList",[NSString stringWithFormat:@"%@/rolesrights/operationlist/v3/vehicles/%@/users/%@?scope=%@",self.regionBase?:@"",vin,uid?:@"",@"All"],@"application/vnd.vwg.mbb.operationList_v3_0_2+xml"],
        @[@"operationListUnscoped",[NSString stringWithFormat:@"%@/rolesrights/operationlist/v3/vehicles/%@/users/%@",self.regionBase?:@"",vin,uid?:@""],@"application/vnd.vwg.mbb.operationList_v3_0_2+xml"],
        @[@"carFinder",[NSString stringWithFormat:@"%@/bs/cf/v1/vehicles/%@/position",self.regionBase?:@"",vin],@"application/vnd.vwg.mbb.carfinderservice_v1_0_0+xml"],
        @[@"homeRegion",[NSString stringWithFormat:@"https://mal-1a.prd.cn.vwg-connect.cn/api/cs/vds/v1/vehicles/%@/homeRegion",vin],@"application/json"]];
    for(NSArray *r in raw) [self.tasks addObject:@{@"name":r[0],@"kind":@"raw",@"url":r[1],@"accept":r[2]}];
}
- (void)runNextWithCompletion:(void (^)(void))completion {
    if(self.taskIndex>=self.tasks.count) { completion(); return; }
    NSDictionary *task=self.tasks[self.taskIndex++];
    NSMutableDictionary *row=[@{@"name":task[@"name"],@"kind":task[@"kind"],@"state":@"pending"} mutableCopy];
    [self.queries addObject:row]; [self save];
    [self emit:[NSString stringWithFormat:@"车辆 %lu：%@",(unsigned long)self.vehicleIndex+1,task[@"name"]]];
    __block BOOL finished=NO;
    void (^finish)(NSString *,id)=^(NSString *state,id value){
        dispatch_async(dispatch_get_main_queue(),^{
            if(finished) return; finished=YES;
            row[@"state"]=state;
            if(value) row[@"result"]=value;
            self.retainedAction=nil; [self save];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/5),dispatch_get_main_queue(),^{ [self runNextWithCompletion:completion]; });
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,25*NSEC_PER_SEC),dispatch_get_main_queue(),^{finish(@"timeout",nil);});
    if([task[@"kind"] isEqual:@"raw"]) {
        if(!self.regionBase.length && ![task[@"name"] isEqualToString:@"homeRegion"]) { finish(@"region-unresolved",nil); return; }
        NSString *token=[MCSDK shared].mbbAccessToken;
        if(!token.length) { finish(@"no-access-token",nil); return; }
        NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:task[@"url"]]];
        req.HTTPMethod=@"GET";
        [req setValue:@"en-US" forHTTPHeaderField:@"Accept-Language"];
        [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        [req setValue:[task[@"accept"] stringByAppendingString:@", application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml"] forHTTPHeaderField:@"Accept"];
        [req setValue:@"BootstrapApp" forHTTPHeaderField:@"x-app-name"]; [req setValue:@"1.0" forHTTPHeaderField:@"x-app-version"];
        NSString *file=[NSString stringWithFormat:@"vehicle-%lu-%@.txt",(unsigned long)self.vehicleIndex,task[@"name"]];
        NSString *path=[self.directory stringByAppendingPathComponent:file];
        [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
            if(data) { [data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]; chmod(path.fileSystemRepresentation,0600); }
            finish(error?@"network-error":(status>=200 && status<300?@"success":@"http-error"),@{@"httpStatus":@(status),@"bytes":@(data.length),@"file":file,@"error":error.localizedDescription?:@""});
        }] resume];
        return;
    }
    id va=self.surveyActions;
    id target=[task[@"facade"] length]?MCSafeGet(va,task[@"facade"]):va;
    if(!target) { finish(@"facade-unavailable",nil); return; }
    void (^success)(id)=^(id value){finish(@"success",Snapshot(value,6));};
    id action=nil;
    if([task[@"kind"] isEqual:@"trips"]) {
        SEL s=@selector(tripStatisticsWithTripType:statusFunction:);
        if(![va respondsToSelector:s]) { finish(@"selector-unavailable",nil); return; }
        action=((id(*)(id,SEL,NSInteger,id))objc_msgSend)(va,s,[task[@"tripType"] integerValue],success);
    } else {
        SEL s=NSSelectorFromString(task[@"selector"]);
        if(![target respondsToSelector:s]) { finish(@"selector-unavailable",nil); return; }
        action=((id(*)(id,SEL,id))objc_msgSend)(target,s,success);
    }
    // Four read APIs return ListenableExecutableAction. This exception is an exact
    // selector/name allow-list from shipped Swift signatures, never a generic fallback.
    SEL run=@selector(loadWithErrorFunction:);
    if (![action respondsToSelector:run]) {
        NSSet *readOnlyExecutable=[NSSet setWithArray:@[@"engineHistory",@"enginePairStatus",@"profileTimers",@"pairingLastStatus"]];
        if ([readOnlyExecutable containsObject:task[@"name"]] && [action respondsToSelector:@selector(executeWithErrorFunction:)]) run=@selector(executeWithErrorFunction:);
        else { finish(@"query-action-unavailable",nil); return; }
    }
    row[@"runner"]=NSStringFromSelector(run); [self save];
    self.retainedAction=action;
    ((void(*)(id,SEL,id))objc_msgSend)(action,run,^(id error){finish(@"sdk-error",Snapshot(error,5));});
}
@end
