// MCSDK.h — CarNetLib.framework 的 ObjC 适配层
//
// CarNetLib 是 Swift framework，对外暴露 @objc 入口。本适配层集中封装
// 运行时类加载与 typed objc_msgSend，业务代码不直接触碰 SDK 内部结构。
//
// 调用序列严格对齐原宿主 VWPCHybridMotion 的反汇编证据（docs/P0-EVIDENCE.md）：
//   initialize: AppInfo + CarNetConfig(networkConfig=123.0/2.0, debug=NO)
//               → +[CarNetLib initializeWithAppInfo:config:extensionDispatchQueue:]
//   选环境:     +[MbbChinaStage mbbStageWithAuthenticationServerBaseUrl:...]
//               → +[CarNetLib useMbbStage:]
//   登录:       -[stage authenticateWithIdentityToken:accountFunction:]
//               → -[flow executeWithErrorFunction:]
//   车辆:       -[stage/accountActions vehicleVinsWithSuccessFunction:] 等
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MCSDKErrorBlock)(NSError *_Nullable error);
typedef void (^MCSDKVoidBlock)(void);

/// SDK 生命周期与身份会话。
@interface MCSDK : NSObject

+ (instancetype)shared;

/// 启动时是否成功加载全部 SDK 类（CarNetLib 及依赖 framework 可用性探测）。
@property (nonatomic, readonly) BOOL sdkAvailable;

/// 按反汇编还原的初始化序列。完成前 isReady 为 NO。
- (void)initializeSDK:(void (^ _Nullable)(NSError *_Nullable))completion;

/// 用宿主网关颁发的身份令牌登录 MBB。
/// 对应宿主 VWPCHybridMotion.loginMBBWithIdentityToken:completion:。
- (void)loginMBBWithIdentityToken:(NSString *)identityToken
                       completion:(void (^)(NSError *_Nullable error))completion;

/// 账号下全部车辆 VIN（P0 只读验证项）。
- (void)vehicleVinsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable vins,
                                             NSError *_Nullable error))completion;

/// 当前选中车辆（useVehicle: 之后可查状态）。
- (BOOL)useVehicleWithVIN:(NSString *)vin;

/// 只读车辆状态（P0 只读验证项，不发任何控制指令）。
- (void)statusOfCurrentVehicleWithCompletion:(void (^)(NSString *_Nullable summary,
                                                        NSError *_Nullable error))completion;

/// 退出登录并关闭 SDK（对应 shutDown）。
- (void)shutdown;

/// MBB 参数探针：遍历候选 brand（appId 可参数化），定位 400 Invalid Payload 的枚举值。
- (void)probeMBBLoginWithIdentityToken:(NSString *)token
                                brands:(NSArray<NSString *> *)brands
                                 appId:(NSString *)appId
                            onProgress:(void (^)(NSString *brand, NSError *_Nullable err))progress
                               onFinish:(void (^)(NSString *_Nullable okBrand, NSError *_Nullable lastErr))finish;

/// 调试辅助：打印 SDK 关键类的方法签名（验证 Block 签名用）。
+ (void)dumpSDKMethodSignatures;

@end

NS_ASSUME_NONNULL_END
