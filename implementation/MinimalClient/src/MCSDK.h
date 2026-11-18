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
- (void)selectVehicleWithVIN:(NSString *)vin completion:(void (^_Nullable)(NSError *_Nullable error))completion;

/// 只读车辆状态（P0 只读验证项，不发任何控制指令）。
- (void)statusOfCurrentVehicleWithCompletion:(void (^)(NSString *_Nullable summary,
                                                        NSError *_Nullable error))completion;

/// 退出登录并关闭 SDK（对应 shutDown）。
- (void)shutdown;

/// 调试辅助：打印 SDK 关键类的方法签名（验证 Block 签名用）。
+ (void)dumpSDKMethodSignatures;

@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN

/// 车辆人类可读信息（VIN → CarportData 映射）。
@interface MCVehicleInfo : NSObject
@property (copy) NSString *vin;
@property (copy) NSString *modelCode, *modelName, *modelYear, *color, *engine, *transmission, *mmi, *countryCode;
@property (copy) NSString *brand, *country;          // VehicleData
@property (copy) NSString *displayName;              // modelName 优先
@property (strong) NSArray<NSString *> *features;    // 支持的能力标识列表
@property (strong) id rawVehicle;                    // SDK Vehicle 对象（选车用）
@end

@interface MCSDK (Catalog)
/// 拉取全部车辆并解析人类可读信息（CarportData + 能力矩阵）。
- (void)catalogWithCompletion:(void (^)(NSArray<MCVehicleInfo *> *_Nullable infos,
                                        NSError *_Nullable error))completion;
/// 能力标识 → 中文说明 + 对应控制接口（只读展示用）。
+ (NSDictionary<NSString *, NSString *> *)featureDescriptions;
+ (NSDictionary<NSString *, NSString *> *)controlCatalog;
/// 只读位置查询（P0 范围内）。
- (void)locationOfCurrentVehicleWithCompletion:(void (^)(NSString *summary, NSError *error))completion;
@end

@interface MCSDK (Control)
/// SPIN（车机安全码）：仅内存，不落盘。nil = 走低安全级路径。
@property (nonatomic, copy, nullable) NSString *spinCode;
/// 物理控制（用户已授权执行；UI 层负责确认弹窗）。
- (void)flashLights:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)honkAndFlash:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)lockVehicle:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)unlockVehicle:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)windowVenting:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)windowOpen:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)windowClose:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)climateStart:(double)tempC onStatus:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)climateStop:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)auxHeatStart:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)auxHeatStop:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)engineStartWithSpin:(NSString *)spin onStatus:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
- (void)engineStop:(void (^)(NSString *status))onStatus error:(void (^)(NSString *error))onError;
@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
@interface MCSDK (Trips)
/// 当前车历史行程列表（单次车程：时长/里程/均速/平均油耗等）。
- (void)tripsOfCurrentVehicleWithCompletion:(void (^)(NSArray<NSDictionary *> *_Nullable trips,
                                                       NSError *_Nullable error))completion;
@end

@interface MCSDK (StatusQueries)
- (void)climateStatusWithCompletion:(void (^)(NSString *_Nullable summary, NSError *_Nullable error))completion;
- (void)healthWarningsWithCompletion:(void (^)(NSString *_Nullable summary, NSError *_Nullable error))completion;
@end

@interface MCSDK (RawData)
/// 当前 MBB 访问令牌（内存，来自 SDK 会话）。
- (NSString *_Nullable)mbbAccessToken;
/// Resolve each vehicle's HomeRegion before querying a regional GET endpoint.
- (void)rawRegionalGETForVIN:(NSString *)vin path:(NSString *)path accept:(NSString *)accept
                completion:(void (^)(NSString *_Nullable body, NSError *_Nullable error))completion;
/// 直连 MAL vehicledata v2 原始信号（XML）。completion 返回全文。
- (void)rawGet:(NSString *)urlString accept:(NSString *)accept
    completion:(void (^)(NSString *_Nullable body, NSError *_Nullable error))completion;
- (void)rawVehicleDataForVIN:(NSString *)vin
                  completion:(void (^)(NSString *_Nullable xml, NSError *_Nullable error))completion;
- (void)rawStatusReportForVIN:(NSString *)vin
                   completion:(void (^)(NSString *_Nullable xml, NSError *_Nullable error))completion;
/// XML → 字段表（每个元素的属性对）。
- (NSArray<NSDictionary *> *)parseRawXML:(NSString *)xml;
@end


@interface MCSDK (Deep)
/// 深度探测：SDK 门面下全部剩余查询，逐行回调结果（只读）。
- (void)deepProbeAll:(void (^)(NSString *line))onLine;
/// 原始：操作权限地图（operationlist v3 XML）与家区域（JSON）。
- (void)rawOperationListForVIN:(NSString *)vin completion:(void (^)(NSString *_Nullable xml, NSError *_Nullable error))completion;
- (void)rawHomeRegionForVIN:(NSString *)vin completion:(void (^)(NSString *_Nullable json, NSError *_Nullable error))completion;
@end

@interface MCSDK (Information)
/// 按明确只读白名单查询当前车辆，返回结构化数据供分级信息页使用。
- (void)informationForKey:(NSString *)key completion:(void (^)(id _Nullable value, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
