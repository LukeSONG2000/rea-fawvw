// MCSDK.m — CarNetLib ObjC 适配层实现
//
// 全部调用序列依据 docs/P0-EVIDENCE.md 的反汇编证据：
//  - VWPCHybridMotion.initializeCarNetLib (0x1074ce314)
//  - VWPCHybridMotion.fetchMbbStage (0x1074ce41c)
//  - VWPCHybridMotion.loginMBBWithIdentityToken:completion: (0x1074cdf44)
//  - VWPCHybridMotion.fetchVehicleByVin:account:completion: (0x1074cdccc)
// Swift 类以运行时名加载；typed objc_msgSend 全部集中在本文件。
#import "MCSDK.h"
#import "MCConfiguration.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// 主程序不链接 CarNetLib（保持可执行零第三方依赖）；
// dyld 不会自动加载 Frameworks/ 目录，须显式 dlopen 拉起整条依赖链。
static void *MCLoadCarNetLib(void) {
    static void *handle = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle mainBundle].bundlePath;
        handle = dlopen([path stringByAppendingPathComponent:
            @"Frameworks/CarNetLib.framework/CarNetLib"].UTF8String, RTLD_NOW);
        if (!handle) {
            NSLog(@"[MCSDK] dlopen CarNetLib 失败: %s", dlerror());
        }
    });
    return handle;
}

// ---- typed objc_msgSend（签名与 SDK 元数据 type encoding 对齐）----
static id   (*ms_ret_id_id)(id, SEL, id) = (id(*)(id,SEL,id))objc_msgSend;
static void (*ms_ret_void)(id, SEL) = (void(*)(id,SEL))objc_msgSend;

// Swift 运行时类名（analysis/carnet-objc-metadata.txt）
#define CLS_CarNetLib      "_TtC9CarNetLib9CarNetLib"
#define CLS_AppInfo        "_TtC9CarNetLib7AppInfo"
#define CLS_CarNetConfig   "_TtC9CarNetLib12CarNetConfig"
#define CLS_ActionConfig   "_TtC9CarNetLib12ActionConfig"
#define CLS_MbbChinaStage  "_TtC9CarNetLib13MbbChinaStage"

static inline Class MCClass(NSString *runtimeName) {
    Class c = NSClassFromString(runtimeName);
    return c;
}

@interface MCSDK ()
@property (nonatomic, strong, nullable) id stageActions;   // StageActionsImpl
@property (nonatomic, strong, nullable) id rawStage;       // MbbChinaStage（分步定位用）
@property (nonatomic, strong, nullable) id account;        // CarNetLib.Account
@property (nonatomic, strong, nullable) id accountActions; // AccountActionsImpl
@property (nonatomic, strong, nullable) id vehicleActions; // VehicleActionsImpl
@property (nonatomic, copy, nullable) NSString *pendingVIN; // 异步选车完成前的登记
@end

@implementation MCSDK

+ (instancetype)shared {
    static MCSDK *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [MCSDK new]; });
    return s;
}

- (BOOL)sdkAvailable {
    MCLoadCarNetLib();
    return MCClass(@(CLS_CarNetLib)) != nil && MCClass(@(CLS_MbbChinaStage)) != nil;
}

- (void)initializeSDK:(void (^)(NSError *))completion {
    MCLoadCarNetLib();
    // 分步打点：SDK 的日志渲染器在主队列异步执行，每步间隔 1.2s，
    // 崩溃发生在哪一步之后即可定位是哪个调用触发的渲染强转。
    [self stepA_appInfoAndInitialize:^(NSError *err) {
        if (err) { !completion ? : completion(err); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self stepB_buildStage:^(NSError *err2) {
                if (err2) { !completion ? : completion(err2); return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self stepC_useStage:^(NSError *err3) {
                        !completion ? : completion(err3);
                    }];
                });
            }];
        });
    }];
}

- (void)stepA_appInfoAndInitialize:(void (^)(NSError *))completion {
    NSLog(@"[MCSDK] stepA 开始");
    Class carNetLib = MCClass(@(CLS_CarNetLib));
    if (!carNetLib) {
        !completion ? : completion([NSError errorWithDomain:@"MCSDK" code:-1
                    userInfo:@{NSLocalizedDescriptionKey:@"CarNetLib 类不可用：framework 未加载"}]);
        return;
    }
    // AppInfo：initWithAppName:appVersion:appId:clientName:clientBrand:
    // 参数值见 MCConfiguration（部分为 TODO-RUNTIME 取证占位）。
    Class appInfoCls = MCClass(@(CLS_AppInfo));
    id appInfo = ((id(*)(id,SEL,id,id,id,id,id))objc_msgSend)(
        [appInfoCls alloc], @selector(initWithAppName:appVersion:appId:clientName:clientBrand:),
        MCAppInfoName, MCAppInfoVersion, MCAppInfoId, MCAppInfoClientName, MCAppInfoClientBrand);
    if (!appInfo) {
        !completion ? : completion([NSError errorWithDomain:@"MCSDK" code:-2
                    userInfo:@{NSLocalizedDescriptionKey:@"AppInfo 构造失败"}]);
        return;
    }

    // CarNetConfig：P0 先用 defaultConfig（原宿主完整参数见证据文档，
    // ActionConfig(pollJobTimeout:123.0, pollRequestDelay:2.0) 待取证后切换精确构造）。
    id config = ((id(*)(Class,SEL))objc_msgSend)(MCClass(@(CLS_CarNetConfig)),
                                                 @selector(defaultConfig));

    // +[CarNetLib initializeWithAppInfo:config:extensionDispatchQueue:]（类方法）
    // 崩溃取证结论：extensionDispatchQueue 在 Swift 侧是 Non-Optional DispatchQueue，
    // 传 nil 会在 SDK 日志渲染时触发 "null pointer in Non-Optional" 断言 → 传主队列。
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(carNetLib,
        @selector(initializeWithAppInfo:config:extensionDispatchQueue:),
        appInfo, config, dispatch_get_main_queue());
    NSLog(@"[MCSDK] stepA 完成（AppInfo+config+initialize）");
    !completion ? : completion(nil);
}

- (void)stepB_buildStage:(void (^)(NSError *))completion {
    NSLog(@"[MCSDK] stepB 开始");
    // MbbChinaStage：mbbStageWithAuthenticationServerBaseUrl:...:scope:brand:country:
    id stage = ((id(*)(Class,SEL,id,id,id,id,id,id))objc_msgSend)(
        MCClass(@(CLS_MbbChinaStage)),
        @selector(mbbStageWithAuthenticationServerBaseUrl:falServerBaseUrl:malServerBaseUrl:scope:brand:country:),
        MCMbbAuthServerURL, MCMbbFalServerURL, MCMbbMalServerURL,
        MCMbbScope, MCMbbBrand, MCMbbCountry);
    if (!stage) {
        !completion ? : completion([NSError errorWithDomain:@"MCSDK" code:-3
                    userInfo:@{NSLocalizedDescriptionKey:@"MbbChinaStage 构造失败"}]);
        return;
    }
    self.rawStage = stage;
    NSLog(@"[MCSDK] stepB 完成（stage=%@）", stage);
    !completion ? : completion(nil);
}

- (void)stepC_useStage:(void (^)(NSError *))completion {
    NSLog(@"[MCSDK] stepC 开始");
    Class carNetLib = MCClass(@(CLS_CarNetLib));
    id actions = ms_ret_id_id(carNetLib, @selector(useMbbStage:), self.rawStage);
    NSLog(@"[MCSDK] stepC useMbbStage 返回 %@", actions);
    self.stageActions = actions;
    !completion ? : completion(nil);
}

- (void)loginMBBWithIdentityToken:(NSString *)identityToken
                       completion:(void (^)(NSError *))completion {
    if (!self.stageActions) {
        !completion ? : completion([NSError errorWithDomain:@"MCSDK" code:-10
                    userInfo:@{NSLocalizedDescriptionKey:@"SDK 未初始化"}]);
        return;
    }
    __weak __typeof(self) weakSelf = self;
    // A registered client ID is an opaque runtime value, not a JWT audience.
    NSString *clientID = [NSUserDefaults.standardUserDefaults stringForKey:@"imported.clientID"];
    void (^success)(id) = ^(id account) {
        weakSelf.account = account;
        weakSelf.accountActions = ms_ret_id_id(MCClass(@(CLS_CarNetLib)), @selector(useAccount:), account);
        NSLog(@"[MCSDK] MBB authentication succeeded");
        if (completion) completion(nil);
    };
    id flow;
    if (clientID.length) {
        flow = ((id(*)(id,SEL,id,id,id))objc_msgSend)(self.stageActions,
            @selector(authenticateWithClientID:identityToken:successFunction:), clientID, identityToken, success);
    } else {
        flow = ((id(*)(id,SEL,id,id))objc_msgSend)(self.stageActions,
            @selector(authenticateWithIdentityToken:accountFunction:), identityToken, success);
    }
    // -[Flow executeWithErrorFunction:]
    ((void(*)(id,SEL,id))objc_msgSend)(flow, @selector(executeWithErrorFunction:),
        ^(id sdkError) {
            NSString *msg = [sdkError respondsToSelector:@selector(errorMessage)]
                ? [sdkError performSelector:@selector(errorMessage)] : [sdkError description];
            NSLog(@"[MCSDK] MBB 登录失败 err=%@", sdkError);
            !completion ? : completion([NSError errorWithDomain:@"MCSDK" code:-11
                        userInfo:@{NSLocalizedDescriptionKey: msg ?: @"未知 SDK 错误"}]);
        });
}

- (void)vehicleVinsWithCompletion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    if (!self.accountActions) {
        !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-20
                    userInfo:@{NSLocalizedDescriptionKey:@"尚未登录"}]);
        return;
    }
    // vehicleVins(successFunction: ([String]) -> ()) -> QueryAction
    id action = ((id(*)(id,SEL,id))objc_msgSend)(self.accountActions,
        @selector(vehicleVinsWithSuccessFunction:),
        ^(NSArray<NSString *> *vins) {
            NSLog(@"[MCSDK] vehicle count=%lu",(unsigned long)vins.count);
            !completion ? : completion(vins, nil);
        });
    ((void(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id sdkError) {
            !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-21
                        userInfo:@{NSLocalizedDescriptionKey:[sdkError description]}]);
        });
}

- (BOOL)useVehicleWithVIN:(NSString *)vin {
    if (!self.accountActions || !vin.length) return NO;
    [self selectVehicleWithVIN:vin completion:nil];
    return YES; // Accepted for asynchronous processing, not a completed selection.
}

- (void)selectVehicleWithVIN:(NSString *)vin completion:(void (^)(NSError *))completion {
    if (!self.accountActions || !vin.length) {
        if (completion) completion([NSError errorWithDomain:@"MCSDK" code:-22 userInfo:@{NSLocalizedDescriptionKey:@"尚未登录或车辆标识为空"}]);
        return;
    }
    self.pendingVIN = vin;
    self.vehicleActions = nil;
    id action = ((id(*)(id,SEL,id,id))objc_msgSend)(self.accountActions,
        @selector(vehicleWithVin:successFunction:), vin, ^(id vehicle) {
            if (![self.pendingVIN isEqualToString:vin]) return;
            self.vehicleActions = ms_ret_id_id(MCClass(@(CLS_CarNetLib)), @selector(useVehicle:), vehicle);
            if (completion) completion(nil);
        });
    ((void(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:), ^(id sdkError) {
        if (![self.pendingVIN isEqualToString:vin]) return;
        if (completion) completion([NSError errorWithDomain:@"MCSDK" code:-23 userInfo:@{NSLocalizedDescriptionKey:@"SDK 选车失败"}]);
    });
}

- (void)statusOfCurrentVehicleWithCompletion:(void (^)(NSString *, NSError *))completion {
    if (!self.vehicleActions) {
        !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-30
                    userInfo:@{NSLocalizedDescriptionKey:@"尚未选择车辆"}]);
        return;
    }
    // statusWithStatusFunction: → QueryAction；P0 仅只读展示
    id action = ((id(*)(id,SEL,id))objc_msgSend)(self.vehicleActions,
        @selector(statusWithStatusFunction:),
        ^(id status) {
            NSLog(@"[MCSDK] vehicle status callback received");
            NSMutableDictionary *details = [NSMutableDictionary dictionaryWithObject:NSStringFromClass([status class]) forKey:@"statusClass"];
            for (NSString *key in @[@"timestamp",@"mileage",@"fuelLevel",@"electricLevel",@"primaryEngineRange",@"combinedRange"]) {
                @try {
                    id value = [status valueForKey:key];
                    if ([value isKindOfClass:NSDate.class]) details[key] = @([value timeIntervalSince1970]);
                    else if ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) details[key] = value;
                    else if (value) {
                        NSMutableDictionary *parts = [NSMutableDictionary dictionary];
                        for (NSString *part in @[@"mileage",@"range",@"level",@"unit"]) {
                            @try { id v=[value valueForKey:part]; if ([v isKindOfClass:NSNumber.class] || [v isKindOfClass:NSString.class]) parts[part]=v; } @catch (NSException *e) {}
                        }
                        if (parts.count) details[key]=parts;
                    }
                } @catch (NSException *e) {}
            }
            NSData *json = [NSJSONSerialization dataWithJSONObject:details options:0 error:nil];
            if (completion) completion([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding], nil);
        });
    ((void(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id sdkError) {
            !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-31
                        userInfo:@{NSLocalizedDescriptionKey:[sdkError description]}]);
        });
}

- (void)shutdown {
    if (self.stageActions) { /* Flow 侧无显式取消入口；SDK 根 shutDown */ }
    Class carNetLib = MCClass(@(CLS_CarNetLib));
    if (carNetLib && [carNetLib respondsToSelector:@selector(shutDown)]) {
        ms_ret_void(carNetLib, @selector(shutDown));
    }
    self.stageActions = nil; self.account = nil;
    self.accountActions = nil; self.vehicleActions = nil;
}

+ (void)dumpSDKMethodSignatures {
    for (NSString *name in @[@"_TtC9CarNetLib9CarNetLib", @"_TtC9CarNetLib13MbbChinaStage",
                             @"_TtC9CarNetLib16StageActionsImpl", @"_TtC9CarNetLib18AccountActionsImpl",
                             @"_TtC9CarNetLib18VehicleActionsImpl"]) {
        Class c = NSClassFromString(name);
        NSLog(@"== %@ -> %@", name, c);
        if (!c) continue;
        unsigned int n = 0;
        Method *ms = class_copyMethodList(c, &n);
        for (unsigned int i = 0; i < n; i++)
            NSLog(@"   %@ %@", NSStringFromSelector(method_getName(ms[i])),
                  [NSString stringWithUTF8String:method_getTypeEncoding(ms[i])]);
        free(ms);
    }
}

@end
