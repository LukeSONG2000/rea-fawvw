# 本地文件保留与恢复

日期：2026-11-18。用户授权提交代码到私有云端并清理本项目本地冗余。范围仅 `/Users/lukesong/Work/Workspace/LukeSONG/fawvw`，不改动其他工作区、Xcode DeviceSupport、模拟器、证书或手机应用。

## 保留

- Git 历史、源码、测试、文档、脱敏分析与接口证据。
- 原始 `packages/com.fawvw.aftermarket_444.28.0_cn_iphone_dumpipa.com.ipa`，SHA-256 `450f0978f4eab1804c0abfef83dfd1c4a2106a9d4eb386567d3593556ba1acea`。
- 最新 `output/FAWVW-MinimalClient-PoC-dev.ipa`，以及本次构建校验记录。
- 本机现有设备环境 `.venv-device`，三个不同阶段的应用数据备份 `output/device-backups/`、必要的会话偏好和开发签名 entitlements。它们包含用户状态，不按普通构建缓存删除，始终忽略于 Git。
- 最终能力查询原始证据 `output/private-capability-survey-final/`、P0 小型原始认证取证、GTI 最终缓存核验 `output/private-gti-location/cache-check-v4/`、官方定位截图和最新清晰的首页/信息目录截图。受限目录权限 0700、文件 0600。

## 清理范围

- `output/signed/`、`output/runtime-probe/`、`output/gti-location-host/` 三个原宿主重签/诊断解包副本。
- 旧过渡版 signed/unsigned IPA、OneApp.patched、临时 dylib、测试可执行文件、重复/失败截图和调试日志。signed IPA 已与私有 research-baseline Release 的 SHA-256 一致核对；需要时从该 Release 恢复。
- `recovered/ios-444.28.0/` 完整解包缓存；清理后仅自动恢复独立客户端所需的 6 个 SDK，完整原输入仍在原始 IPA 中。
- 重复的早期能力调查与定位捕获，保留上述最终证据。历史文档中的旧本机临时路径因此不一定继续存在，以本页和最终脱敏报告为准。
- `analysis/objc-runtime-metadata.txt` 及其重复压缩副本；已核对本机压缩件与私有 Release 的 SHA-256 一致。大型静态分析索引仍保留在 Git 中。
- 旧 output 截图和现场报告从当前 Git 树移除；本次不重写既有 Git 历史。整个 output 目录统一忽略，防止以后重新提交现场数据。

## 重建

独立客户端的构建会自动调用 `implementation/prepare_inputs.py`，仅从原始 IPA 解出 CarNetLib、AEXML、AnyDate、EVReflectionCore、XMLDictionary 和 TrustKit。

继续原宿主分析前运行 `python3 implementation/prepare_inputs.py --full`；旧宿主构建脚本也会自动恢复完整原包。分析脚本若直接读取 OneApp 或 VWCarnet-Core.bundle，先执行同一命令。输入校验失败时停止，不接受未知版本替代。

缺少原始 IPA 时，从私有 research-baseline Release 恢复到 packages；旧 signed 过渡包、完整 ObjC 元数据压缩包也在同一 Release。最新客户端 IPA 本机保留；本次代码提交不创建新 Release 或公开发布。

执行结果以 `analysis/local-cleanup-2026-11-18.json` 为准。清理后重新构建、验签并运行适配层回归测试，不以磁盘文件减少代替构建验收。

## 执行结果

代码提交 `52e6102` 已推送到私有 main 分支。88 项清理清单已执行，之后删除了本次验证重建的临时 app 目录和测试可执行文件。项目磁盘占用由约 5.84 GiB 降至约 1.72 GiB，释放约 4.12 GiB。

从原始 IPA 重新提取 6 个 SDK（约 20.8 MiB）后，客户端完整构建、深度签名、ZIP CRC、SDK 输入哈希与白名单检查通过，构建 0 warning / 0 error；SafeGetter ABI 和 XML 字段/命名空间测试通过。仅保留最新安装包及构建报告，未安装或操作手机。

最新 IPA SHA-256：`941817b1d91853f2500a74843cc70af8e274f82097e3d25ff2de27b46d203570`。既有已安装包的真机验收记录保持历史原值；本次重签包只完成构建校验，不扩大实车验收结论。Git 历史完整保留，已执行普通 git gc，未重写历史。
