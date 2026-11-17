// MCSDK_Internal.h — 适配层内部状态（实现文件间共享，不对外）
#import "MCSDK.h"

@interface MCSDK ()
@property (nonatomic, strong, nullable) id stageActions;
@property (nonatomic, strong, nullable) id rawStage;
@property (nonatomic, strong, nullable) id account;
@property (nonatomic, strong, nullable) id accountActions;
@property (nonatomic, strong, nullable) id vehicleActions;
@property (nonatomic, copy, nullable) NSString *pendingVIN;
@end

@interface MCSDK ()
/// SPIN（车机安全码）：仅内存持有，不落盘。nil = 走低安全级路径。
@property (nonatomic, copy, nullable) NSString *spinCode;
@end
