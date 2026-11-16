// MCConfiguration.h — MinimalClient 全部运行参数集中定义
//
// 证据等级标注：
//   [EVIDENCE-STATIC]   由原 OneApp 二进制反汇编/明文字符串直接确认
//   [TODO-RUNTIME]      原宿主中为加密 CFString（SM4/流密码池），需运行时取证回填
//
// 证据来源见 docs/P0-EVIDENCE.md 与 analysis/ 目录。

#pragma once
#import <Foundation/Foundation.h>

// [EVIDENCE-RUNTIME] Original-host SDK constructor arguments captured by P0RuntimeProbe.
extern NSString *const MCMbbAuthServerURL;
extern NSString *const MCMbbFalServerURL;
extern NSString *const MCMbbMalServerURL;
extern NSString *const MCMbbScope;
extern NSString *const MCMbbBrand;
extern NSString *const MCMbbCountry;
extern NSString *const MCAppInfoName;
extern NSString *const MCAppInfoVersion;
extern NSString *const MCAppInfoId;
extern NSString *const MCAppInfoClientName;
extern NSString *const MCAppInfoClientBrand;

#pragma mark - NetworkConfig（initializeCarNetLib 明文浮点常量）

// [EVIDENCE-STATIC] fmov d0,=123.0; fmov d1,=2.0 → initWithPollJobTimeout:pollRequestDelay:
extern double const MCPollJobTimeout;        // 123.0
extern double const MCPollRequestDelay;      // 2.0

#pragma mark - 宿主账号网关（P0 身份令牌来源）

// [EVIDENCE-STATIC] 主程序接口路径表 + oneapp-api 生产域名
extern NSString *const MCHostGatewayBaseURL; // https://oneapp-api.faw-vw.com
extern NSString *const MCHostLoginPasswordPath; // account/login/loginByPassword/v1
// [TODO-RUNTIME] loginByPassword/v1 请求体字段与响应 data 解密方式未取证
