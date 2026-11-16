// MCHostAuth.m
#import "MCHostAuth.h"
#import "MCConfiguration.h"

static NSURLSession *sharedSession(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        // 网关基础参数：原 App UA/版本头（网关可能校验；取证后对齐）。
        cfg.HTTPAdditionalHeaders = @{
            @"User-Agent": @"FAW-VW OneApp iOS",
            @"Accept": @"application/json",
        };
        cfg.timeoutIntervalForRequest = 20;
        s = [NSURLSession sessionWithConfiguration:cfg];
    });
    return s;
}

static NSDictionary *CandidateLoginBody(NSString *u, NSString *p) {
    // [TODO-RUNTIME] 字段名未取证。按国内网关惯例给出最小候选集，
    // probeLoginSchema 用于实测回填；登录正文不可记录到日志。
    return @{
        @"mobile": u,
        @"password": p,
        @"loginType": @"PASSWORD",
    };
}

static void PostJSON(NSURL *url, NSDictionary *body,
                     void (^done)(NSData *_Nullable, NSURLResponse *_Nullable, NSError *_Nullable)) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
    if (err || !data) { done(nil, nil, err); return; }
    req.HTTPBody = data;
    [[sharedSession() dataTaskWithRequest:req completionHandler:done] resume];
}

@implementation MCHostAuth

+ (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(NSString *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:
        [MCHostGatewayBaseURL stringByAppendingPathComponent:MCHostLoginPasswordPath]];
    PostJSON(url, CandidateLoginBody(username, password), ^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) { !completion ? : completion(nil, e); return; }
        NSError *err = nil;
        id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:&err] : nil;
        if (!obj || err) {
            !completion ? : completion(nil, [NSError errorWithDomain:@"MCHostAuth" code:-2
                    userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"响应解析失败: %@", err]}]);
            return;
        }
        // [TODO-RUNTIME] 身份令牌字段名与 data 解密方式待取证；当前按 data.token/data.idToken 候选。
        NSString *status = obj[@"returnStatus"];
        NSString *token = nil;
        if ([obj[@"data"] isKindOfClass:[NSString class]]) {
            token = obj[@"data"];  // 若 data 为整体令牌
        } else if ([obj[@"data"] isKindOfClass:[NSDictionary class]]) {
            token = obj[@"data"][@"idToken"] ?: obj[@"data"][@"token"];
        }
        if ([status isEqualToString:@"SUCCEED"] && token.length > 0) {
            !completion ? : completion(token, nil);
        } else {
            !completion ? : completion(nil, [NSError errorWithDomain:@"MCHostAuth" code:-3
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"网关返回: %@", obj]}]);
        }
    });
}

+ (void)probeLoginSchemaWithUsername:(NSString *)username
                             password:(NSString *)password
                             completion:(void (^)(NSString *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:
        [MCHostGatewayBaseURL stringByAppendingPathComponent:MCHostLoginPasswordPath]];
    PostJSON(url, CandidateLoginBody(username, password), ^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *raw = e.localizedDescription ?: ([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]);
        !completion ? : completion(raw, e);
    });
}

@end
