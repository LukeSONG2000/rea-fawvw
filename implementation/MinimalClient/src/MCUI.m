#import "MCUI.h"
#import <objc/runtime.h>
#import "MCSDK_Internal.h"

UIColor *MCInk(void) { return [UIColor colorWithRed:.10 green:.12 blue:.13 alpha:1]; }
UIColor *MCPaper(void) { return UIColor.systemGroupedBackgroundColor; }
UIColor *MCAccent(void) { return [UIColor colorWithRed:.77 green:.17 blue:.17 alpha:1]; }
UIFont *MCFont(CGFloat size, UIFontWeight weight) {
    UIFont *base=[UIFont systemFontOfSize:size weight:weight];
    return [UIFontMetrics.defaultMetrics scaledFontForFont:base];
}
void MCHapticPress(void) { [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred]; }
void MCHapticSelect(void) { [[UISelectionFeedbackGenerator new] selectionChanged]; }
void MCHapticResult(BOOL success) { [[UINotificationFeedbackGenerator new] notificationOccurred:success?UINotificationFeedbackTypeSuccess:UINotificationFeedbackTypeError]; }
NSString *MCVehicleName(NSString *name) {
    if([name.uppercaseString containsString:@"GTI"]) return @"Golf GTI";
    return name.length?name:@"我的车辆";
}
NSString *MCFriendlyName(NSString *key) {
    static NSDictionary *names; static dispatch_once_t once;
    dispatch_once(&once, ^{ names=@{
        @"vehicleDataDetail":@"车辆完整档案", @"carportData":@"出厂配置", @"vehicleDevices":@"通信设备", @"vehicleDevice":@"设备", @"deviceId":@"设备编号", @"deviceType":@"设备类型", @"ecuGeneration":@"控制器版本", @"embeddedSim":@"车载 SIM 卡", @"mno":@"网络运营商", @"imei":@"通信设备识别码", @"identification":@"设备标识", @"systemId":@"系统编号", @"isConnect":@"车联网状态", @"isConnectSorglosReady":@"车联网准备状态", @"requestId":@"查询编号", @"operationList":@"服务权限清单", @"serviceInfo":@"服务信息", @"serviceStatus":@"服务状态", @"parameter":@"参数", @"parameters":@"参数列表", @"permission":@"权限", @"privacyGroup":@"隐私权限组", @"privacyGroups":@"隐私权限组", @"privacyGroupState":@"隐私授权状态", @"privacyGroupStates":@"隐私授权状态", @"remoteCommand":@"远程命令", @"requiredSecurityLevel":@"所需安全级别", @"primaryUserRequired":@"需要主用户", @"rolesAndRightsRequired":@"需要角色权限", @"configurable":@"支持配置", @"personalized":@"个人服务", @"licenseRequired":@"需要服务授权", @"licenseProfile":@"服务授权", @"licenseProfiles":@"服务授权清单", @"activationDate":@"开通日期", @"expirationDate":@"到期日期", @"invocationUrl":@"服务地址", @"termsAndConditionsRequired":@"服务协议要求", @"serviceEol":@"服务结束状态", @"vehicleLifeCycleStatus":@"车辆服务周期", @"blockDisabling":@"限制停用", @"cumulatedLicense":@"累计授权", @"extAuth":@"额外认证", @"xsd":@"字段定义", @"stateOfCharge":@"电池电量", @"lastUpdated":@"最近更新时间", @"message":@"说明", @"code":@"结果代码", @"duration":@"持续时长", @"startTime":@"开始时间", @"endTime":@"结束时间", @"remainingTime":@"剩余时间", @"timer":@"定时器", @"timers":@"定时计划", @"profiles":@"档位设置", @"profile":@"档位", @"departureTime":@"出发时间", @"dayOfWeek":@"星期", @"recurring":@"重复执行", @"notification":@"通知", @"notifications":@"通知记录", @"definitions":@"提醒设置", @"deviceName":@"设备名称", @"paired":@"已配对", @"pairingState":@"配对状态", @"maximumDuration":@"最长持续时间", @"minimumDuration":@"最短持续时间", @"radius":@"半径",
        @"timestamp":@"数据采集时间", @"mileage":@"里程", @"fuelLevel":@"燃油余量", @"electricLevel":@"电量", @"primaryEngineRange":@"燃油续航", @"combinedRange":@"综合续航", @"range":@"续航", @"level":@"余量", @"unit":@"单位", @"value":@"数值", @"bodyStatus":@"车身状态", @"centralLockStatus":@"中央门锁", @"vehicleComponents":@"门窗与车身部件", @"component":@"部件", @"position":@"位置", @"status":@"状态", @"openStatus":@"开闭状态", @"lockStatus":@"门锁状态", @"type":@"类型", @"componentType":@"部件类型", @"componentState":@"部件状态", @"nextServiceIn":@"保养剩余量", @"nextServiceInKm":@"检查保养剩余里程", @"nextServiceInDays":@"检查保养剩余天数", @"nextOilServiceInKm":@"换油剩余里程", @"nextOilServiceInDays":@"换油剩余天数", @"tripEnd":@"结束时间", @"travelTime":@"行驶时长", @"startMileage":@"起始总里程", @"overallMileage":@"累计总里程", @"averageSpeed":@"平均速度", @"averageFuelConsumption":@"平均油耗数值", @"averageElectricEngineConsumption":@"平均电耗数值", @"averageRecuperation":@"能量回收数值", @"zeroEmissionDistance":@"零排放里程", @"reportReason":@"记录原因", @"tripType":@"行程类型", @"id":@"记录编号", @"warnings":@"健康提醒", @"actions":@"操作记录", @"operation":@"操作类型", @"result":@"执行结果", @"state":@"状态", @"latitude":@"纬度", @"longitude":@"经度", @"updateTime":@"位置采集时间", @"speed":@"速度", @"course":@"航向", @"vin":@"车辆识别码", @"modelName":@"车型", @"modelCode":@"车型代码", @"modelYear":@"年款", @"engine":@"发动机代码", @"transmission":@"变速箱代码", @"color":@"车漆代码", @"mmi":@"车机配置代码", @"brand":@"品牌", @"country":@"国家", @"countryCode":@"市场", @"serviceEnabled":@"服务已启用", @"unavailable":@"当前不可用", @"serviceDisableReason":@"停用原因代码", @"serviceDisabledReasons":@"停用原因代码", @"userRole":@"用户角色", @"securityLevel":@"安全级别", @"role":@"用户角色", @"isInFlightMode":@"飞行模式", @"requestStatus":@"请求状态", @"securityPin":@"安全码", @"temperature":@"温度", @"climatisationState":@"空调状态", @"heaterSource":@"加热来源", @"targetTemperature":@"设定温度", @"chargingState":@"充电状态", @"chargeMode":@"充电模式", @"remainingChargingTime":@"剩余充电时间", @"enabled":@"已启用", @"active":@"已启用", @"name":@"名称", @"textId":@"信号说明代码", @"fieldId":@"信号编号", @"tsCarCaptured":@"车辆采集时间", @"tsCarSent":@"车辆发送时间", @"tsCarSentUtc":@"车辆发送时间（UTC）", @"tsTssReceivedUtc":@"服务接收时间（UTC）", @"operationId":@"操作标识", @"requiredUserRole":@"所需用户角色", @"serviceId":@"服务标识", @"_text":@"内容", @"_element":@"数据类型"
    }; });
    if(names[key]) return names[key];
    NSDictionary *feature=[MCSDK featureDescriptions]; if(feature[key]) return feature[key];
    return [NSString stringWithFormat:@"其他字段 · %@",key];
}
NSString *MCFriendlyValue(id value, NSString *key) {
    if(!value || value==NSNull.null) return @"未提供";
    if([value isKindOfClass:NSDictionary.class]) {
        if(value[@"value"] && [value count]<=3) return MCFriendlyValue(value[@"value"],key);
        if(value[@"nextServiceIn"]) return MCFriendlyValue(value[@"nextServiceIn"],key);
        if([key isEqual:@"fuelLevel"] && value[@"level"]) return [NSString stringWithFormat:@"%@ %%",value[@"level"]];
        if([key isEqual:@"electricLevel"] && value[@"level"]) return [NSString stringWithFormat:@"%@ %%",value[@"level"]];
        if(value[@"mileage"]) return MCFriendlyValue(value[@"mileage"],@"mileage");
        if(value[@"range"]) return MCFriendlyValue(value[@"range"],@"range");
        return [NSString stringWithFormat:@"%lu 项",(unsigned long)[value count]];
    }
    if([value isKindOfClass:NSArray.class]) return [NSString stringWithFormat:@"%lu 条",(unsigned long)[value count]];
    if([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return [value boolValue]?@"是":@"否";
    if(([@[@"timestamp",@"tripEnd",@"updateTime"] containsObject:key]) && [value respondsToSelector:@selector(doubleValue)] && [value doubleValue]>1000000000) {
        double t=[value doubleValue];if(t>100000000000) t/=1000;
        NSDateFormatter *df=[NSDateFormatter new];df.dateStyle=NSDateFormatterMediumStyle;df.timeStyle=NSDateFormatterShortStyle;
        return [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
    }
    if([key isEqual:@"travelTime"] && [value respondsToSelector:@selector(doubleValue)]) {
        NSInteger s=[value integerValue];return s>=3600?[NSString stringWithFormat:@"%ld 小时 %ld 分钟",(long)s/3600,(long)(s%3600)/60]:[NSString stringWithFormat:@"%ld 分钟 %ld 秒",(long)s/60,(long)s%60];
    }
    NSString *text=[value description];
    NSDictionary *terms=@{@"PRIMARY_USER":@"主用户",@"SECONDARY_USER":@"授权用户",@"ENABLED":@"已启用",@"DISABLED":@"已停用",@"clamp15off":@"点火关闭时记录",@"CN":@"中国",@"VW":@"大众"};
    if(terms[text]) return terms[text];
    NSString *unit=@{@"mileage":@"km",@"range":@"km",@"startMileage":@"km",@"overallMileage":@"km",@"zeroEmissionDistance":@"km",@"averageSpeed":@"km/h",@"nextServiceInKm":@"km",@"nextOilServiceInKm":@"km",@"nextServiceInDays":@"天",@"nextOilServiceInDays":@"天"}[key];
    if(unit && [value respondsToSelector:@selector(doubleValue)]) {
        double n=[value doubleValue];
        if(n<0 && [key hasPrefix:@"next"]) return [NSString stringWithFormat:@"已超出 %@ %@",@(-n),unit];
        return [NSString stringWithFormat:@"%@ %@",text,unit];
    }
    if([value isKindOfClass:NSNumber.class] && [@[@"status",@"state",@"operation",@"type",@"position",@"unit",@"centralLockStatus",@"serviceDisableReason"] containsObject:key]) return [NSString stringWithFormat:@"代码 %@（含义待确认）",text];
    return text;
}
id MCInformationSnapshot(id value, NSUInteger depth) {
    if(!value || value==NSNull.null) return NSNull.null;
    if([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if([value isKindOfClass:NSDate.class]) return @([value timeIntervalSince1970]);
    if(!depth) return @"信息层级较深，暂未展开";
    if([value isKindOfClass:NSSet.class]) value=[value allObjects];
    if([value isKindOfClass:NSArray.class]) { NSMutableArray *a=[NSMutableArray array]; for(id item in value) [a addObject:MCInformationSnapshot(item,depth-1)]; return a; }
    if([value isKindOfClass:NSDictionary.class]) { NSMutableDictionary *d=[NSMutableDictionary dictionary];for(NSString *k in value) d[k]=MCInformationSnapshot(value[k],depth-1);return d; }
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    NSSet *deny=[NSSet setWithArray:@[@"accessToken",@"refreshToken",@"identityToken",@"mbbTokens",@"account",@"token",@"hash",@"superclass",@"description",@"debugDescription",@"securityPin",@"spin"]];
    for(Class c=object_getClass(value);c && c!=NSObject.class;c=class_getSuperclass(c)) {
        unsigned count=0; objc_property_t *props=class_copyPropertyList(c,&count);
        for(unsigned i=0;i<count;i++) {
            NSString *name=@(property_getName(props[i]));if([deny containsObject:name]) continue;
            NSString *getter=name; NSString *attributes=@(property_getAttributes(props[i]));
            for(NSString *part in [attributes componentsSeparatedByString:@","]) if([part hasPrefix:@"G"]) getter=[part substringFromIndex:1];
            d[name]=MCInformationSnapshot(MCSafeGet(value,getter),depth-1);
        }
        free(props);
    }
    return d;
}
