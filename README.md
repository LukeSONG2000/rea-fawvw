# fawvw — 一汽大众最小车控客户端

独立原生 iOS 客户端，只保留账号车辆身份、车辆控制与信息查询。当前界面采用拟物遥控器、单色 LCD、中文按键、触觉反馈和分级信息页。原 OneApp 补丁版仅作为过渡和研究证据。

已在真机完成 SDK 初始化、现有身份会话恢复、车辆目录及 GTI 多项只读查询。完整新账号登录、MOSC 定位接入和物理控制逐项验收仍未完成。能力已开通不等于指令已实车成功。

## 开发与构建

```bash
python3 implementation/MinimalClient/build.py --ipa
```

构建自动从本机 `packages/` 原始 IPA 恢复必要的 6 个 SDK，产物为 `output/FAWVW-MinimalClient-PoC-dev.ipa`。签名使用本机 Xcode 已有开发证书和描述文件；不在仓库保存签名私钥、身份令牌或账号密码。

需要继续原宿主逆向或构建过渡版时，再恢复完整研究输入：

```bash
python3 implementation/prepare_inputs.py --full
```

原始 IPA、旧过渡版和完整 ObjC 元数据压缩包已保存在私有 [research-baseline Release](https://github.com/LukeSONG2000/fawvw/releases/tag/research-baseline)。清理后的本地布局与恢复方法见 [LOCAL-MAINTENANCE.md](docs/LOCAL-MAINTENANCE.md)。

## 目录

| 路径 | 内容 |
|---|---|
| `implementation/MinimalClient/` | 独立客户端、构建脚本和测试 |
| `implementation/LocationProbe/` | GTI 只读定位取证探针 |
| `implementation/CarControlOnly/`、`RuntimeProbe/` | 原宿主过渡补丁和认证研究 |
| `analysis/` | 脱敏能力、接口、SDK 和定位证据 |
| `docs/` | 设计、接口结论、交接与验收边界 |
| `packages/` | 原始 IPA，本机保留，不进 Git |
| `recovered/` | 按需解出的输入缓存，不进 Git |
| `output/` | 最新 IPA、必要备份和私密证据；整个目录不进 Git |

- [界面与交互规格](docs/CONTROL-APP-UI.md)
- [GTI 信息能力与定位结论](docs/GTI-INFORMATION-AND-LOCATION.md)
- [能力调查](docs/CAPABILITY-EXPLORATION-2026-11-17.md)

设备备份、运行日志、偏好、VIN、手机号和令牌保留在本机受限目录。该仓库为私有研究仓库。
