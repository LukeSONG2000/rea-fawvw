// MCKeychainForensics.h — 官方会话 keychain 存储位取证（最终形态验证）
//
// PoC 通过 entitlements 声明官方 App 的 keychain 组（KC9H2N4239.com.fawvw.aftermarket），
// 枚举该组 GenericPassword 项的属性（service/account/访问组/长度），定位官方登录
// identity token 的持久化位置。只输出属性摘要，不导出数据本体到日志。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCKeychainForensics : NSObject
/// 枚举全部可访问的 GenericPassword 项，返回属性摘要列表（NSLog 同时打印）。
+ (NSArray<NSDictionary *> *)dumpGenericPasswordSummary;
/// 在官方组中查找 JWT 形态（三段点分）的长条目——identity token 候选。
+ (void)findIdentityTokenCandidates;
@end

NS_ASSUME_NONNULL_END
