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
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(carNetLib,
        @selector(initializeWithAppInfo:config:extensionDispatchQueue:),
        appInfo, config, nil);

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
    // +[CarNetLib useMbbStage:] → StageActionsImpl
    self.stageActions = ms_ret_id_id(carNetLib, @selector(useMbbStage:), stage);
    NSLog(@"[MCSDK] 初始化完成 stage=%@", self.stageActions);
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
    // -[StageActionsImpl authenticateWithIdentityToken:accountFunction:] → Flow
    id flow = ((id(*)(id,SEL,id,id))objc_msgSend)(self.stageActions,
        @selector(authenticateWithIdentityToken:accountFunction:),
        identityToken,
        ^(id account) {
            // 成功：CarNetLib.Account。+[CarNetLib useAccount:] → AccountActionsImpl
            weakSelf.account = account;
            weakSelf.accountActions = ms_ret_id_id(MCClass(@(CLS_CarNetLib)),
                                                   @selector(useAccount:), account);
            NSLog(@"[MCSDK] MBB 登录成功 account=%@", account);
            !completion ? : completion(nil);
        });
    // -[Flow executeWithErrorFunction:]
    ((id(*)(id,SEL,id))objc_msgSend)(flow, @selector(executeWithErrorFunction:),
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
            NSLog(@"[MCSDK] vehicleVins = %@", vins);
            !completion ? : completion(vins, nil);
        });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(executeWithErrorFunction:),
        ^(id sdkError) {
            !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-21
                        userInfo:@{NSLocalizedDescriptionKey:[sdkError description]}]);
        });
}

- (BOOL)useVehicleWithVIN:(NSString *)vin {
    if (!self.accountActions) return NO;
    __block BOOL ok = NO;
    id action = ((id(*)(id,SEL,id,id))objc_msgSend)(self.accountActions,
        @selector(vehicleWithVin:successFunction:), vin,
        ^(id vehicle) {
            // +[CarNetLib useVehicle:] → VehicleActionsImpl
            [MCSDK shared].vehicleActions = ms_ret_id_id(MCClass(@(CLS_CarNetLib)),
                                                         @selector(useVehicle:), vehicle);
            ok = YES;
        });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(executeWithErrorFunction:),
        ^(id sdkError) { NSLog(@"[MCSDK] useVehicle 失败 %@", sdkError); });
    // vehicleWithVin 为异步 QueryAction；这里只登记选择意图，状态回调里完成绑定。
    self.pendingVIN = vin;
    return YES;
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
            NSLog(@"[MCSDK] status = %@", status);
            !completion ? : completion([status description], nil);
        });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(executeWithErrorFunction:),
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
