// MCHostAuth.h — 一汽大众账号网关登录（P0：密码优先）
//
// [EVIDENCE-STATIC] 宿主登录走自有网关而非 SDK 身份提供器：
//   原主程序 selrefs 只有 useMbbStage:/loginMBBWithIdentityToken:，
//   无 useIdentityProviderStage:/fetchIdentityTokenWithClientId: 引用。
// 网关接口（主程序接口路径表，偏移 0x8ddee6e 附近）：
//   POST {base}/account/login/loginByPassword/v1           密码登录
//   POST {base}/account/login/loginByVerificationCode/v1    短信验证码
//   POST {base}/account/code/sendVerificationCodeByLogin/v1 发验证码
// 响应统一 {"returnStatus":"SUCCEED","data":...}，data 疑似加密（样例为 base64）。
// [TODO-RUNTIME] 请求体字段与 data 解密方式未取证：P0 验证时以实际抓包回填。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCHostAuth : NSObject

/// 密码登录。成功返回宿主身份令牌（供 MCSDK loginMBBWithIdentityToken:）。
+ (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(NSString *_Nullable identityToken,
                                    NSError *_Nullable error))completion;

/// 请求字段名取证辅助：按候选字段集发送并报告网关返回，供验证阶段确定协议。
+ (void)probeLoginSchemaWithUsername:(NSString *)username
                             password:(NSString *)password
                             completion:(void (^)(NSString *_Nullable rawResponse,
                                                  NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
