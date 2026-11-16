# P0 证据记录：CarNetLib 独立宿主可行性

> **2026-11-16 后续更正**：原始阶段的环境参数、audience/clientID 推断及查询动作调用有误。真实运行参数与独立宿主两车状态验证已完成，见 [P0-RESOLUTION.md](P0-RESOLUTION.md)。下文保留为历史过程，不再作为当前配置依据。

更新：2026-11-16。全部结论标注证据等级：**[EVIDENCE-STATIC]**（二进制静态证据）/ **[TODO-RUNTIME]**（需设备运行时取证）。未标注的推测不作为依据。

## 1. 原宿主的 SDK 适配层已定位并反汇编

**[EVIDENCE-STATIC]** 原主程序 `VWPCHybridMotion`（ObjC，`objc-runtime-metadata.txt` 行 2190600 起）是 CarNetLib 适配层，方法与 imp 地址：

| 方法 | imp | 作用 |
|---|---|---|
| `+sharedManager` | 0x1074cca38 | 单例 |
| `sendIdToken:` | 0x1074cd5fc | 接收身份令牌 |
| `fetchVehicleStatusWithVehicle:complete:` | 0x1074cd760 | 只读状态 |
| `fetchVehicleByVin:account:completion:` | 0x1074cdccc | 按 VIN 取车辆 |
| `loginMBBWithIdentityToken:completion:` | 0x1074cdf44 | MBB 令牌交换登录 |
| `initializeCarNetLib` | 0x1074ce314 | SDK 初始化 |
| `fetchMbbStage` | 0x1074ce41c | 构造 MBB 环境 |

另存在 Widget 侧同构管理器 `MosiWidgetCarnetLibManager`（`initializeCarNetLibWithEnviroment:` / `mbbStageAuthenticationUrl` 等，主程序元数据行 1221800 起），其实际二进制 `PlugIns/OneAppWidgetExtension.appex`（22MB）只链接 CarNetLib + 4 个非系统依赖 + GMObjC——**官方 Widget 即"脱离 OneApp 主程序的最小宿主"实证，P0 方向可行**。

## 2. 初始化调用序列（initializeCarNetLib 反汇编还原）

**[EVIDENCE-STATIC]** `initializeCarNetLib`（0x1074ce314）的实际序列：

```objc
// AppInfo：initWithAppName:appVersion:appId:clientName:clientBrand:
//   5 个参数全部为 __DATA_CONST 加密 CFString（0x109ee5690..0x109ee5710，0x20 间隔）
// ActionConfig：initWithPollJobTimeout:pollRequestDelay:  (123.0, 2.0)   ← 明文浮点常量
// CarNetConfig：initWithDebug:networkConfig:actionConfig:loggerExtension: (NO,…,↑,…)  ← stub 0x1083ace60
// CarNetLib 类方法：initializeWithAppInfo:config:extensionDispatchQueue: (appInfo, config, nil)  ← stub 0x1083b1d80
```

`fetchMbbStage`（0x1074ce41c）构造环境（stub 0x1083abc20 = `initWithAuthenticationServer:falServer:malServer:scope:brand:country:vehicleBackendPublicKeyPins:`；URL 来自配置类 `MosiWidgetCarnetLibManager` 的 `mbbStageAuthenticationUrl/mbbPinningUrl/mbbStageMalUrl` getter，UAT/生产双常量选择）。

## 3. 登录链路结论：宿主网关，不是 SDK 身份提供器

**[EVIDENCE-STATIC]** 决定性证据：原主程序符号/selref 中只存在 `useMbbStage:`、`loginMBBWithIdentityToken:completion:`；**不存在** `useIdentityProviderStage:`、`fetchIdentityTokenWithClientId:username:password:`、`FAWVWIdentityProviderStage` 的任何引用。SDK 的 FAWVW 身份提供器（含密码/短信登录入口）在原 App 中**未被使用**——独立客户端不能默认它可用，需按宿主网关协议恢复登录。

`loginMBBWithIdentityToken:completion:` 的 Block 执行体（0x1074ce0fc）反汇编还原：

```objc
id stage = [CarNetLib useMbbStage:[self fetchMbbStage]];              // stub 0x108484e00
id flow  = [stage authenticateWithIdentityToken:idToken                // stub 0x1083460e0
                                    accountFunction:successBlock];
[flow executeWithErrorFunction:failureBlock];                          // stub 0x108382800
```

**[EVIDENCE-STATIC]** `fetchVehicleByVin:account:completion:`（0x1074cdccc）补充车辆链路：

```objc
id accountActions = [CarNetLib useAccount:account];                    // stub 0x108484880
id action = [accountActions vehicleWithVin:vin successFunction:block]; // stub 0x108487720
[action executeWithErrorFunction:…];
// 成功后 [CarNetLib useVehicle:vehicle] → VehicleActionsImpl（与 useMbbStage/useAccount 同构的静态外观）
```

Swift 导出符号确认 Block 签名（`carnet-public-symbols.txt`）：
- `vehicleVins(successFunction: ([String]) -> ()) -> QueryAction`
- `AccountActionsImpl(account: Account)` 构造经 `+[CarNetLib useAccount:]` 外观获得。

## 4. 生产环境参数

**[EVIDENCE-STATIC]**（主程序 __TEXT 明文 + 本机运行日志双重确认，密文长度与明文一致）：

| 参数 | 生产值 | 证据 |
|---|---|---|
| MBB 认证 | `https://mbboauth-1d.prd.cn.vwg-connect.cn` | 主程序明文字符串；密文 41B 吻合 |
| FAL | `https://fal-3a.prd.cn.dp.vwg-connect.cn` | 运行日志实际请求；密文 34B 吻合 |
| MAL | `https://mal-3a.prd.cn.dp.vwg-connect.cn` | 运行日志实际请求；密文 40B 吻合 |
| scope | `openid profile mbb` | CarNetLib 内置明文；密文 12B 吻合 |
| MBB 注册/令牌端点 | `/mbbcoauth/mobile/register/v1`、`/mbbcoauth/mobile/oauth2/v1/token`、`/as/token.oauth2` | CarNetLib 字符串 |
| 宿主账号网关 | `https://oneapp-api.faw-vw.com` + `account/login/loginByPassword/v1`（密码）、`loginByVerificationCode/v1`（验证码）、`oneTapLogin/v1`（一键）、`account/code/sendVerificationCodeByLogin/v1`（发码） | 主程序接口路径表（文件偏移 0x8ddee6e） |
| 网关响应结构 | `{"returnStatus":"SUCCEED","data":…}`（data 疑似 base64 加密载荷） | 主程序内嵌样例 |

## 5. 待运行时取证清单（加密 CFString 池）

宿主将关键参数存于 `__DATA_CONST`/`__DATA` 的 16 字节对齐密文池（每串独立密钥的流密码，XOR 密钥流呈 9/12 字节周期），静态不可解。设备验证时从运行中的原 App dump 一次即全部获得：

| 参数 | 密文地址 | 长度 | 用途 |
|---|---|---|---|
| appName | 0x109ee5690 | 12B | AppInfo |
| appVersion | 0x109ee56b0 | 3B | AppInfo |
| appId | 0x109ee56d0 | 20B | AppInfo / 可能即 clientID |
| clientName | 0x109ee56f0 | 5B | AppInfo（疑似 "fawvw"） |
| clientBrand | 0x109ee5710 | 2B | AppInfo + MbbStage.brand（同一常量） |
| scope | 0x109ee5890 | 12B | MbbStage（已有 SDK 内置默认值） |
| country | 0x109ee58b0 | 2B | MbbStage（疑似 "CN"） |
| mbbStageIdentifier | 0x109ebc3f0 | 16B | 环境标识 |
| pinning URL | 0x109ebc430 | 31B | TrustKit pin 配置来源 |

另有 `loginByPassword/v1` 的请求体字段与 data 解密方式，需一次抓包或网关探针确认。

## 6. 依赖白名单（递归闭包）

**[EVIDENCE-STATIC]** CarNetLib 全部 27 个 LC_LOAD_DYLIB 中非系统项仅 4 个；递归后共 6 件：

```
CarNetLib.framework → AEXML, AnyDate, EVReflectionCore, TrustKit
EVReflectionCore   → XMLDictionary
XMLDictionary      → （无非系统依赖）
```

Swift 运行库（libswiftCore 等 12 项）为 `@rpath` 系统 `/usr/lib/swift`，iOS 12.2+ 内置，不需打包。

## 7. PoC 构建产物与真机验证（2026-11-16）

`implementation/MinimalClient/`（build.py 一键可重现构建，无 Xcode 工程文件）：

- Bundle ID `com.lukev.minimalclient`（wildcard 团队证书；**不覆盖** `com.lukev.aftermarket` 唯一可用安装）
- 组成：自研 ObjC 可执行（UIKit + 系统框架，零第三方链接依赖）+ 6 framework 白名单
- 总大小 21MB（`codesign --deep --strict` 通过；IPA `output/FAWVW-MinimalClient-PoC-dev.ipa`）
- 适配层 `MCSDK` 严格按第 2/3 节证据序列调用；网关登录 `MCHostAuth` 按第 4 节接口实现，字段名留探针

### 真机验证记录（iPhone Air，iOS 27.3）

| 步骤 | 结果 |
|---|---|
| devicectl 安装 `com.lukev.minimalclient` | ✅ 与现有 `com.fawvw.aftermarket`（补丁版）并存 |
| 首次启动 | ❌ EXC_BREAKPOINT `NoSceneLifecycleAdoption`（iOS 13+ scene 生命周期）→ 已修复：SceneDelegate |
| 二次启动 | ✅ 进程存活，但 `NSClassFromString` 找不到 SDK 类 → 原因：主程序未链接 CarNetLib，dyld 不会自动加载 Frameworks/ 目录 → 已修复：`dlopen(RTLD_NOW)` 显式拉起 |
| 三次启动 | ✅ **进程存活 +「SDK 类探测：可用」**（CarNetLib 与 MbbChinaStage 类完成 ObjC 运行时注册），截图 `output/minimalclient-poc-screen2.png` |

**结论**：CarNetLib 及其 5 个依赖 framework 可在脱离原 OneApp 的独立 21MB 宿主进程中加载并注册（与 Widget 扩展同为官方支持的最小宿主形态）。P0 可行性已从「官方 Widget 佐证」升级为「本 PoC 实测」。

**尚未验证**（需用户凭据与运行时取证，见第 5 节）：真实网关登录、MBB 令牌交换、两车 VIN 只读、状态读取。在上述完成前，P0 不宣称通过；物理控制仍从未执行。
