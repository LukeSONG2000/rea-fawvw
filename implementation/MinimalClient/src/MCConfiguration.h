// MCConfiguration.h — MinimalClient 全部运行参数集中定义
//
// 证据等级标注：
//   [EVIDENCE-STATIC]   由原 OneApp 二进制反汇编/明文字符串直接确认
//   [TODO-RUNTIME]      原宿主中为加密 CFString（SM4/流密码池），需运行时取证回填
//
// 证据来源见 docs/P0-EVIDENCE.md 与 analysis/ 目录。

#pragma once
#import <Foundation/Foundation.h>

#pragma mark - MBB 生产环境（fetchMbbStage 反汇编 + 主程序明文字符串区）

// [EVIDENCE-STATIC] 长度与密文完全吻合（41B），主程序 __TEXT 存有同值明文
extern NSString *const MCMbbAuthServerURL;   // https://mbboauth-1d.prd.cn.vwg-connect.cn
// [EVIDENCE-STATIC] 34B，运行日志确认实际在用
extern NSString *const MCMbbFalServerURL;    // https://fal-3a.prd.cn.dp.vwg-connect.cn
// [EVIDENCE-STATIC] 40B，运行日志确认实际在用
extern NSString *const MCMbbMalServerURL;    // https://mal-3a.prd.cn.dp.vwg-connect.cn
// [EVIDENCE-STATIC] CarNetLib 内置明文，长度与 fetchMbbStage scope 密文(12B)一致
extern NSString *const MCMbbScope;           // openid profile mbb

#pragma mark - 待运行时取证的加密参数（原宿主 CFString 池密文见 docs/P0-EVIDENCE.md）

// [TODO-RUNTIME] fetchMbbStage brand 参数（密文 2B，密文地址 0x109ee5710；
//                initializeCarNetLib 的 clientBrand 传同一常量）
extern NSString *const MCMbbBrand;
// [TODO-RUNTIME] fetchMbbStage country 参数（密文 2B，0x109ee58b0；高度疑似 "CN"）
extern NSString *const MCMbbCountry;

#pragma mark - AppInfo（initializeCarNetLib 反汇编序列，五参数全部加密）

// [TODO-RUNTIME] appName（密文 12B，0x109ee5690）
extern NSString *const MCAppInfoName;
// [TODO-RUNTIME] appVersion（密文 3B，0x109ee56b0）
extern NSString *const MCAppInfoVersion;
// [TODO-RUNTIME] appId（密文 20B，0x109ee56d0）
extern NSString *const MCAppInfoId;
// [TODO-RUNTIME] clientName（密文 5B，0x109ee56f0；疑似 "fawvw"——主程序明文区两处）
extern NSString *const MCAppInfoClientName;
// [TODO-RUNTIME] clientBrand（密文 2B，0x109ee5710，与 MCMbbBrand 同一常量）
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
