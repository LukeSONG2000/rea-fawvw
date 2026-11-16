#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <sys/stat.h>

static NSMutableDictionary *Findings;
static NSString *ProbeDirectory(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/P0Probe"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    return path;
}
static void Record(NSString *key, id value) {
    @synchronized(Findings) {
        Findings[key] = value ?: @"<nil>";
        NSString *path = [ProbeDirectory() stringByAppendingPathComponent:@"findings.plist"];
        [Findings writeToFile:path atomically:YES];
        chmod(path.fileSystemRepresentation, 0600);
    }
}
// ===== Keychain 属性枚举（找 identity token 的持久化位；只取属性与长度摘要，不导出本体）=====
static NSString *SHA256Prefix(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 4; i++) [s appendFormat:@"%02x", hash[i]];
    return s;
}
static void DumpKeychain(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
    };
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &out);
    if (st != errSecSuccess) { Record(@"keychain-dump-status", @(st)); return; }
    NSArray *items = CFBridgingRelease(out);
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSData *value = item[(__bridge id)kSecValueData];
        [list addObject:@{
            @"service": item[(__bridge id)kSecAttrService] ?: @"<nil>",
            @"account": item[(__bridge id)kSecAttrAccount] ?: @"<nil>",
            @"group": item[(__bridge id)kSecAttrAccessGroup] ?: @"<nil>",
            @"bytes": @(value.length),
            @"sha256-8": value ? SHA256Prefix(value) : @"<nil>",
            @"accessible": item[(__bridge id)kSecAttrAccessible] ?: @"<nil>",
        }];
    }
    Record(@"keychain-generic-password", list);
    Record(@"keychain-dump-count", @(list.count));
}


static id Read(id object, NSString *key) {
    @try { id value = [object valueForKey:key]; return value; } @catch (NSException *e) { return nil; }
}
static id Describe(id value) {
    if (!value) return @"<nil>";
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:NSStringFromClass([value class]) forKey:@"class"];
    for (NSString *key in @[@"baseUrl", @"baseURL", @"url", @"identifier", @"name"]) {
        id v = Read(value, key);
        if ([v isKindOfClass:NSString.class]) result[key] = v;
        else if ([v isKindOfClass:NSURL.class]) result[key] = [v absoluteString];
    }
    return result;
}
static void CaptureToken(NSString *source, id token) {
    if (![token isKindOfClass:NSString.class] || ![token length]) { Record(source, @{@"present":@NO}); return; }
    NSData *bytes = [token dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, hash);
    NSMutableString *digest = [NSMutableString string];
    for (NSUInteger i=0;i<sizeof(hash);i++) [digest appendFormat:@"%02x",hash[i]];
    NSMutableDictionary *info = [@{@"present":@YES,@"length":@([token length]),@"sha256":digest} mutableCopy];
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count == 3) {
        NSString *encoded = [parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
        encoded = [encoded stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
        while (encoded.length % 4) encoded = [encoded stringByAppendingString:@"="];
        NSData *json = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
        id claims = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        if ([claims isKindOfClass:NSDictionary.class]) for (NSString *key in @[@"typ",@"type",@"iss",@"scp",@"exp",@"cor"]) if (claims[key]) info[key] = claims[key];
    }
    // Credential stays solely in the app's protected local diagnostic directory; never NSLog.
    NSString *path = [ProbeDirectory() stringByAppendingPathComponent:[source stringByAppendingString:@".token"]];
    [bytes writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
    chmod(path.fileSystemRepresentation,0600);
    Record(source, info);
}
// ===== 登录链路取证（P1）：oneapp-api 网关请求/响应 + tokens 写入 =====
// 数据只写入本机受限目录（0700），不进日志。请求体可能含用户密码，仅本机分析用。
static NSDateFormatter *StampFormatter;
static NSString *Stamp(void) {
    if (!StampFormatter) {
        StampFormatter = [NSDateFormatter new];
        StampFormatter.dateFormat = @"HHmmss.SSS";
    }
    return [StampFormatter stringFromDate:[NSDate date]];
}
static BOOL HostInteresting(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    return [host containsString:@"faw-vw.com"] || [host containsString:@"fawvw"]
        || [host containsString:@"volkswagen"] || [host containsString:@"vwg-connect"];
}
static void SaveBlob(NSString *kind, NSURL *url, NSData *data) {
    if (!data.length) return;
    NSString *host = [url.host.lowercaseString stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *name = [NSString stringWithFormat:@"%@-%@-%@.bin", Stamp(), kind, host];
    NSString *path = [ProbeDirectory() stringByAppendingPathComponent:name];
    [data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
    chmod(path.fileSystemRepresentation, 0600);
}
static NSMutableDictionary *MakeCaptureEntry(NSURLRequest *request) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"url"] = request.URL.absoluteString;
    entry[@"method"] = request.HTTPMethod;
    entry[@"stamp"] = Stamp();
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        NSString *key = [(NSString *)k lowercaseString];
        // 脱敏：授权/票据类头只记长度
        headers[key] = ([key containsString:@"authorization"] || [key containsString:@"token"])
            ? [NSString stringWithFormat:@"<len=%lu>", (unsigned long)[(NSString *)v length]] : v;
    }];
    entry[@"requestHeaders"] = headers;
    return entry;
}
static IMP DataTaskReq, UploadTaskData;
static id HookDataTask(id self, SEL sel, NSURLRequest *request, id handler) {
    // 只捕获请求侧；不包装 completionHandler（CFNetwork task 销毁路径析构崩溃，见 17:03 崩溃报告）
    if (HostInteresting(request.URL)) {
        NSMutableDictionary *entry = MakeCaptureEntry(request);
        if (request.HTTPBody) SaveBlob(@"reqbody", request.URL, request.HTTPBody);
        Record([@"net-" stringByAppendingString:entry[@"stamp"]], entry);
    }
    return ((id(*)(id,SEL,id,id))DataTaskReq)(self, sel, request, handler);
}
static id HookUploadTask(id self, SEL sel, NSURLRequest *request, NSData *body, id handler) {
    if (HostInteresting(request.URL)) {
        NSMutableDictionary *entry = MakeCaptureEntry(request);
        if (body) SaveBlob(@"reqbody", request.URL, body);
        Record([@"netup-" stringByAppendingString:entry[@"stamp"]], entry);
    }
    return ((id(*)(id,SEL,id,id,id))UploadTaskData)(self, sel, request, body, handler);
}
static IMP DefaultsSetObject, DefaultsSetData;
static void HookDefaultsSet(id self, SEL sel, id value, NSString *key) {
    if ([key isKindOfClass:NSString.class] && ([key containsString:@"coreentity.tokens"] || [key containsString:@"currentUser"])) {
        // tokens 归档含令牌本体：摘要+长度进 findings，原文写入受限目录供本地解包
        NSData *raw = [value isKindOfClass:NSData.class] ? value : [NSKeyedArchiver archivedDataWithRootObject:value requiringSecureCoding:NO error:nil];
        if (raw.length) {
            SaveBlob([NSString stringWithFormat:@"defaults-%@", key.lastPathComponent], [NSURL URLWithString:@"file://defaults"], raw);
            Record([NSString stringWithFormat:@"defaults-write-%@", key.lastPathComponent],
                   @{@"stamp": Stamp(), @"bytes": @(raw.length)});
        }
    }
    if (sel == NSSelectorFromString(@"setData:forKey:")) {
        ((void(*)(id,SEL,id,id))DefaultsSetData)(self, sel, value, key);
    } else {
        ((void(*)(id,SEL,id,id))DefaultsSetObject)(self, sel, value, key);
    }
}

static IMP AppInfoInit, StageFactory, StageInit7, StageInit6, UseStage, Authenticate, AuthenticateClient, SendIdentity, HostLogin;
static id HookAppInfo(id self, SEL sel, id name, id version, id appID, id client, id brand) {
    Record(@"AppInfo", @{@"appName":Describe(name),@"appVersion":Describe(version),@"appId":Describe(appID),@"clientName":Describe(client),@"clientBrand":Describe(brand)});
    return ((id(*)(id,SEL,id,id,id,id,id))AppInfoInit)(self,sel,name,version,appID,client,brand);
}
static void SaveStageArguments(NSString *key,id auth,id fal,id mal,id scope,id brand,id country,id pins) {
    Record(key,@{@"authenticationServer":Describe(auth),@"falServer":Describe(fal),@"malServer":Describe(mal),@"scope":Describe(scope),@"brand":Describe(brand),@"country":Describe(country),@"pins":Describe(pins)});
}
static id HookStageFactory(id self,SEL sel,id auth,id fal,id mal,id scope,id brand,id country) {
    SaveStageArguments(@"stageFactory",auth,fal,mal,scope,brand,country,nil);
    return ((id(*)(id,SEL,id,id,id,id,id,id))StageFactory)(self,sel,auth,fal,mal,scope,brand,country);
}
static id HookStageInit7(id self,SEL sel,id auth,id fal,id mal,id scope,id brand,id country,id pins) {
    SaveStageArguments(@"stageInit7",auth,fal,mal,scope,brand,country,pins);
    return ((id(*)(id,SEL,id,id,id,id,id,id,id))StageInit7)(self,sel,auth,fal,mal,scope,brand,country,pins);
}
static id HookStageInit6(id self,SEL sel,id auth,id fal,id mal,id scope,id brand,id country) {
    SaveStageArguments(@"stageInit6",auth,fal,mal,scope,brand,country,nil);
    return ((id(*)(id,SEL,id,id,id,id,id,id))StageInit6)(self,sel,auth,fal,mal,scope,brand,country);
}
static id HookUseStage(id self,SEL sel,id stage) {
    NSMutableDictionary *info=[NSMutableDictionary dictionary];
    for (NSString *key in @[@"authenticationServer",@"falServer",@"malServer",@"scope",@"brand",@"country"]) info[key]=Describe(Read(stage,key));
    Record(@"useMbbStage",info);
    return ((id(*)(id,SEL,id))UseStage)(self,sel,stage);
}
static id HookAuthenticate(id self,SEL sel,id token,id callback) {
    CaptureToken(@"sdk-identity",token);
    return ((id(*)(id,SEL,id,id))Authenticate)(self,sel,token,callback);
}
static id HookAuthenticateClient(id self,SEL sel,id client,id token,id callback) {
    Record(@"authenticationClientID",Describe(client)); CaptureToken(@"sdk-client-identity",token);
    return ((id(*)(id,SEL,id,id,id))AuthenticateClient)(self,sel,client,token,callback);
}
static void HookSendIdentity(id self,SEL sel,id token) {
    CaptureToken(@"host-send-identity",token);
    ((void(*)(id,SEL,id))SendIdentity)(self,sel,token);
}
static void HookHostLogin(id self,SEL sel,id token,id callback) {
    CaptureToken(@"host-login-identity",token);
    ((void(*)(id,SEL,id,id))HostLogin)(self,sel,token,callback);
}
static void Replace(Class cls, NSString *name, IMP replacement, IMP *original, BOOL classMethod) {
    if (classMethod) cls=object_getClass(cls);
    Method method=class_getInstanceMethod(cls,NSSelectorFromString(name));
    if (!method) { Record([@"missing-" stringByAppendingString:name],@YES); return; }
    *original=method_getImplementation(method);
    if (!class_addMethod(cls,NSSelectorFromString(name),replacement,method_getTypeEncoding(method))) method_setImplementation(method,replacement);
}
__attribute__((constructor)) static void InstallProbe(void) {
    Findings=[NSMutableDictionary dictionary]; Record(@"probeVersion",@2);
    // P1 登录链取证：网关请求/响应 + tokens/currentUser 写入
    Replace([NSURLSession class], @"dataTaskWithRequest:completionHandler:", (IMP)HookDataTask, &DataTaskReq, NO);
    Replace([NSURLSession class], @"uploadTaskWithRequest:fromData:completionHandler:", (IMP)HookUploadTask, &UploadTaskData, NO);
    Replace([NSUserDefaults class], @"setObject:forKey:", (IMP)HookDefaultsSet, &DefaultsSetObject, NO);
    Replace([NSUserDefaults class], @"setData:forKey:", (IMP)HookDefaultsSet, &DefaultsSetData, NO);
    Replace(NSClassFromString(@"_TtC9CarNetLib7AppInfo"),@"initWithAppName:appVersion:appId:clientName:clientBrand:",(IMP)HookAppInfo,&AppInfoInit,NO);
    Class stage=NSClassFromString(@"_TtC9CarNetLib13MbbChinaStage");
    Replace(stage,@"mbbStageWithAuthenticationServerBaseUrl:falServerBaseUrl:malServerBaseUrl:scope:brand:country:",(IMP)HookStageFactory,&StageFactory,YES);
    Replace(stage,@"initWithAuthenticationServer:falServer:malServer:scope:brand:country:vehicleBackendPublicKeyPins:",(IMP)HookStageInit7,&StageInit7,NO);
    Replace(stage,@"initWithAuthenticationServer:falServer:malServer:scope:brand:country:",(IMP)HookStageInit6,&StageInit6,NO);
    Replace(NSClassFromString(@"_TtC9CarNetLib9CarNetLib"),@"useMbbStage:",(IMP)HookUseStage,&UseStage,YES);
    Class actions=NSClassFromString(@"_TtC9CarNetLib16StageActionsImpl");
    Replace(actions,@"authenticateWithIdentityToken:accountFunction:",(IMP)HookAuthenticate,&Authenticate,NO);
    Replace(actions,@"authenticateWithClientID:identityToken:successFunction:",(IMP)HookAuthenticateClient,&AuthenticateClient,NO);
    Class host=NSClassFromString(@"VWPCHybridMotion");
    Replace(host,@"sendIdToken:",(IMP)HookSendIdentity,&SendIdentity,NO);
    Replace(host,@"loginMBBWithIdentityToken:completion:",(IMP)HookHostLogin,&HostLogin,NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        DumpKeychain();
        Class cls=NSClassFromString(@"VWPCHybridMotion");
        if (![cls respondsToSelector:NSSelectorFromString(@"sharedManager")]) return;
        id manager=((id(*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(@"sharedManager"));
        CaptureToken(@"host-existing-identity",Read(manager,@"idToken"));
        if (!Findings[@"AppInfo"]) ((void(*)(id,SEL))objc_msgSend)(manager,NSSelectorFromString(@"initializeCarNetLib"));
        id stage=((id(*)(id,SEL))objc_msgSend)(manager,NSSelectorFromString(@"fetchMbbStage"));
        Record(@"localStageClass",stage?NSStringFromClass([stage class]):@"<nil>");
        Record(@"localInspectionComplete",@YES);
    });
}
