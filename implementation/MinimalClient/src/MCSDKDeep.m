// MCSDKDeep.m — 深度探测：SDK 门面下全部剩余查询（只读）+ 权限地图
#import "MCSDK_Internal.h"
#import <objc/message.h>

#import "MCCapabilitySurvey.h"

@implementation MCSDK (Deep)
- (void)deepProbeAll:(void (^)(NSString *line))onLine {
    [MCCapabilitySurvey runWithProgress:onLine];
}

- (void)rawOperationListForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    NSString *uid = MCSafeGet(self.account, @"mbbUserId");
    if (![uid isKindOfClass:NSString.class]) {
        if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-81
            userInfo:@{NSLocalizedDescriptionKey: @"无 mbbUserId（未登录）"}]);
        return;
    }
    [self rawRegionalGETForVIN:vin path:[NSString stringWithFormat:
        @"/rolesrights/operationlist/v3/vehicles/%@/users/%@?scope=All", vin, uid]
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
