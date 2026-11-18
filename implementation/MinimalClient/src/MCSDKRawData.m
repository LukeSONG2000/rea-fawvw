// MCSDKRawData.m — MAL 原始接口直连（vehicleDataDetail / VehicleStatusReport XML）
#import "MCSDK_Internal.h"

@interface MCRawXMLParser : NSObject <NSXMLParserDelegate>
@property (strong) NSMutableArray<NSDictionary *> *fields;
@property (strong) NSMutableDictionary *currentField;
@property (strong) NSMutableString *text;
@end
@implementation MCRawXMLParser
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)q attributes:(NSDictionary *)attrs {
    self.text=[NSMutableString string];
    NSMutableDictionary *d=[NSMutableDictionary dictionaryWithObject:name forKey:@"_element"];
    for(NSString *key in attrs) d[[[key componentsSeparatedByString:@":"] lastObject]]=attrs[key];
    if([name isEqualToString:@"field"]) { self.currentField=d; [self.fields addObject:d]; }
    else if(attrs.count && !self.currentField) [self.fields addObject:d];
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)string { [self.text appendString:string]; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)q {
    NSString *text=[self.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([name isEqualToString:@"field"]) self.currentField=nil;
    else if(self.currentField && text.length) self.currentField[name]=text;
    self.text=[NSMutableString string];
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
    req.timeoutInterval = 20;
    [req setValue:@"en-US" forHTTPHeaderField:@"Accept-Language"];
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
        NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
        NSError *httpError = status >= 200 && status < 300 ? nil : [NSError errorWithDomain:@"MCRawHTTP" code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP %ld",(long)status]}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(body, httpError); });
    }] resume];
}

- (void)rawRegionalGETForVIN:(NSString *)vin path:(NSString *)path accept:(NSString *)accept completion:(void (^)(NSString *,NSError *))completion {
    [self rawHomeRegionForVIN:vin completion:^(NSString *body,NSError *error){
        NSData *data=[body dataUsingEncoding:NSUTF8StringEncoding];
        id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSString *base=[json isKindOfClass:NSDictionary.class]?json[@"homeRegion"][@"baseUri"][@"content"]:nil;
        NSURL *url=[base isKindOfClass:NSString.class]?[NSURL URLWithString:base]:nil;
        if(error || ![url.scheme isEqualToString:@"https"] || ![url.host hasSuffix:@".vwg-connect.cn"]) {
            if(completion) completion(nil,error?:[NSError errorWithDomain:@"MCRawHTTP" code:-82 userInfo:@{NSLocalizedDescriptionKey:@"无法解析车辆后端区域"}]); return;
        }
        NSString *root=[base stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        [self rawGet:[root stringByAppendingString:path] accept:accept completion:completion];
    }];
}
- (void)rawVehicleDataForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    [self rawRegionalGETForVIN:vin path:[NSString stringWithFormat:@"/vehicleMgmt/vehicledata/v2/vehicles/%@",vin]
        accept:@"application/vnd.vwg.mbb.vehicleDataDetail_v2_1_0+xml, application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml" completion:completion];
}
- (void)rawStatusReportForVIN:(NSString *)vin completion:(void (^)(NSString *, NSError *))completion {
    [self rawRegionalGETForVIN:vin path:[NSString stringWithFormat:@"/bs/vsr/v1/vehicles/%@/status",vin]
        accept:@"application/vnd.vwg.mbb.VehicleStatusReport_v1_0_0+xml, application/vnd.volkswagenag.com-error-v1+xml, application/vnd.vwg.mbb.genericError_v1_0_2+xml" completion:completion];
}

- (NSArray<NSDictionary *> *)parseRawXML:(NSString *)xml {
    MCRawXMLParser *dp = [MCRawXMLParser new];
    dp.fields = [NSMutableArray array];
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    p.delegate = dp;
    p.shouldProcessNamespaces = YES;
    p.shouldResolveExternalEntities = NO;
    [p parse];
    return dp.fields;
}

@end
