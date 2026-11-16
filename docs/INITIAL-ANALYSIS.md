# 一汽大众 iOS 静态分析

日期为 2026-11-16。本轮采用 REA 包清单、提取与 Mach-O 检查，并用本地 plist 和 Mach-O 段解析补充元数据。

## 应用身份

| 项目 | 结果 |
|---|---|
| 名称 | 一汽大众 |
| Bundle ID | com.fawvw.aftermarket |
| 版本 / Build | 444.28.0 / 518 |
| 最低系统 | iOS 15.0 |
| 主程序 | OneApp，arm64 |
| IPA SHA-256 | 450f0978f4eab1804c0abfef83dfd1c4a2106a9d4eb386567d3593556ba1acea |
| 主程序 SHA-256 | 484508e3e4284ba1aaba400b184f0b209cdb5a9973f094c4649f995168ffa28a |

## 结构和技术栈

REA 清单报告 3,716 个文件项和 635 个目录项，提取结果报告 3,715 个常规文件。两个计数按各自工具口径保留，差异尚未逐项核对。提取物保存在 recovered/ios-444.28.0。

主程序包含 Objective-C 元数据和 Swift 类型、字段及反射段。__objc_classname 段提取到 9,330 个非空名称，包含 SDK 类及协议名称，业务类数量待进一步归属。

| 组件证据 | 可支持的判断 |
|---|---|
| CarNetLib、VWCeaVehicleDefinitions | 包含车辆互联相关组件 |
| Car2PhonePairing、RHPCar2PhonePairing、BeaconScanner | 包含手机配对及信标相关组件 |
| RemoteParkAssistPlugin、RemoteParkAssistCoreMEB、VWRPAConnection 和 RHP 系列 | 包含远程泊车相关组件 |
| UnityFramework | 集成 Unity 引擎，具体场景待资源和调用分析 |
| Nebula、Ariver、MPNebulaAdapter 的资源及 JavaScript 桥 | 包含 mPaaS/H5/小程序容器相关资源 |
| AliyunPlayer、AliyunMediaDownloader、alivcffmpeg | 包含音视频播放和下载组件 |
| TrustKit、CATSecureStorage、CATKeychain 系列 | 包含传输信任及安全存储相关组件 |

上述模块判断来自包内名称、资源及元数据，实际启用条件与运行行为待验证。完整框架和 Web 文件清单见 analysis/package-summary.json。

## 入口和恢复条件

主程序 LC_MAIN 的 entryoff 为 230556。LC_ENCRYPTION_INFO_64 的 cryptid 为 0，cryptoff 为 32768，cryptsize 为 161742848，可继续开展静态反汇编与函数分析。

声明的 URL scheme 包括 fawvwapp、faw-vw，以及支付、分享等回调。后台模式声明包括 fetch、location、remote-notification 和 bluetooth-central。

REA 返回 165 个依赖、9,239 条导入记录、121 条导出记录和 7 个 segment。导入导出的覆盖度由 REA 标为非穷尽。

## 证据与当前覆盖

- analysis/rea-package-evidence.json 保存包清单和提取证据。
- analysis/rea-native-evidence.json 保存累计 REA 证据及 Mach-O 检查。
- analysis/load-commands.txt 保存 otool 原始加载命令。
- analysis/native-layout.json 保存加密字段及段位置。
- analysis/objc-classnames.txt 保存主程序名称段。
- analysis/module-class-candidates.txt 保存按登录、车辆、充电、主页与 WebView 等词筛出的名称候选。

本轮完成包结构和主程序静态基线。函数伪代码、业务调用链、接口请求模型、页面结构及真机运行行为仍待分析。下一步可从 AppDelegate、车辆服务和小程序桥的实际引用定位业务入口，并进一步追踪登录与车辆绑定链路。
