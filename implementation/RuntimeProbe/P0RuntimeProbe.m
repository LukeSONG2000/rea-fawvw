#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CommonCrypto/CommonDigest.h>
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
    Findings=[NSMutableDictionary dictionary]; Record(@"probeVersion",@1);
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
