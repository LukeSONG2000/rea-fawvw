# fawvw — 一汽大众 App 最小车控客户端研究

目标：用可独立构建的原生最小宿主复用 `CarNetLib.framework`，只保留登录、账号车辆身份、车控与相关查询；去除资讯、商城、营销等非车控功能。原 OneApp UI 补丁版仅作过渡与证据，不以隐藏入口冒充彻底移除。

- 状态：**P0（证明独立宿主能工作）进行中**，尚未宣称 SDK 已可脱离原宿主运行。
- 物理控制（开锁/启动/鸣笛）从未执行过；当前阶段只做只读验证。
- 详见 [docs/ZCODE-RESEARCH-HANDOFF.md](docs/ZCODE-RESEARCH-HANDOFF.md)（验收标准与全部约束）。

## 目录

| 路径 | 内容 |
|---|---|
| `packages/` | 原始 IPA（不进 git，见 Release） |
| `recovered/ios-444.28.0/` | 解包后的 `OneApp.app`（只读输入，不修改） |
| `analysis/` | REA 证据、SDK 符号/ObjC 元数据清单、接口候选、探针源码 |
| `implementation/CarControlOnly/` | 旧宿主过渡补丁（dylib 注入 + 重签脚本） |
| `implementation/MinimalClient/` | P0 独立最小宿主（建设中） |
| `docs/` | 研究文档与交接记录 |
| `output/` | 构建产物、截图、设备验证日志（敏感项不入库） |

## 关键结论速览

- 原宿主通过 `VWPCHybridMotion` 类适配 CarNetLib：`initializeCarNetLib` → `fetchMbbStage` → `loginMBBWithIdentityToken:completion:` → `fetchVehicleByVin:account:completion:` / `fetchVehicleStatusWithVehicle:complete:`。
- CarNetLib 非系统直接依赖仅 4 个：AEXML、AnyDate、EVReflectionCore、TrustKit（见 `analysis/rea-carnet-sdk-evidence.json`）。
- SDK 内有一汽大众专属身份提供器 `FAWVWIdentityProviderStage` 与 `MbbChinaStage`；密码登录入口 `IdentityProviderStageActionsImpl.fetchIdentityTokenWithClientId:username:password:identityTokenFunction:`。

## Release 归档

见 Release `research-baseline`：

- `com.fawvw.aftermarket_444.28.0_cn_iphone_dumpipa.com.ipa`：原始输入 IPA（SHA-256 见交接文档）。
- `FAWVW-444.28.0-CarControlOnly-dev-signed.ipa`：过渡补丁版，用户确认可用（密码登录 + 代理 + GTI 车控页）；多车切换不可靠，不是最终交付。
- `objc-runtime-metadata.txt.gz`：原主程序 133MB ObjC 运行时元数据 dump。

## 安全与合规

- 本仓库为**私有研究仓库**。设备备份、偏好 plist、运行日志、凭据、令牌、VIN、手机号不入库。
- 登录凭据由用户在设备端输入；分析产物仅含静态二进制证据。
