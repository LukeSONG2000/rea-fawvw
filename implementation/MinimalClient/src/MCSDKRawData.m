// MCSDKRawData.m — MAL 原始接口直连（vehicleDataDetail / VehicleStatusReport XML）
#import "MCSDK_Internal.h"

@interface MCRawXMLParser : NSObject <NSXMLParserDelegate>
@property (strong) NSMutableArray<NSDictionary *> *fields;
@end
@implementation MCRawXMLParser
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)ns
 qualifiedName:(NSString *)q attributes:(NSDictionary *)attrs {
    if (attrs.count == 0) return;
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:attrs];
    d[@"_element"] = name;
    [self.fields addObject:d];
}
@end

@implementation MCSDK (RawData)

- (NSString *)mbbAccessToken {
    if (!self.account) return nil;
    id tokens = MCSafeGet(self.account, @"mbbTokens");
    if (!tokens) return nil;
    id at = MCSafeGet(tokens, @"accessToken");
    if ([at isKindOfClass:NSString.class]) return at;
    id tok = MCSafeGet(at, @"token");
    return [tok isKindOfClass:NSString.class] ? tok : nil;
}

- (void)rawGet:(NSString *)urlString accept:(NSString *)accept
    completion:(void (^)(NSString *, NSError *))completion {
    NSString *token = self.mbbAccessToken;
    if (token.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-80
            userInfo:@{NSLocalizedDescriptionKey: @"无 MBB 令牌（未登录）"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    req.HTTPMethod = @"GET";
    [req setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [req setValue:accept forHTTPHeaderField:@"Accept"];
    [req setValue:@"BootstrapApp" forHTTPHeaderField:@"x-app-name"];
    [req setValue:@"1.0" forHTTPHeaderField:@"x-app-version"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
            return;
        }
        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(body, nil); });
    }] resume];
}

- (void)rawVehicleDataForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    [self rawGet:[NSString stringWithFormat:
        @"https://mal-3a.prd.cn.dp.vwg-connect.cn/api/vehicleMgmt/vehicledata/v2/vehicles/%@", vin]
        accept:@"application/vnd.vwg.mbb.vehicleDataDetail_v2_1_0+xml, application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml"
        completion:completion];
}

- (void)rawStatusReportForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    [self rawGet:[NSString stringWithFormat:
        @"https://mal-3a.prd.cn.dp.vwg-connect.cn/api/bs/vsr/v1/vehicles/%@/status", vin]
        accept:@"application/vnd.vwg.mbb.VehicleStatusReport_v1_0_0+xml, application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml"
        completion:completion];
}

- (NSArray<NSDictionary *> *)parseRawXML:(NSString *)xml {
    MCRawXMLParser *dp = [MCRawXMLParser new];
    dp.fields = [NSMutableArray array];
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    p.delegate = dp;
    [p parse];
    return dp.fields;
}

@end
