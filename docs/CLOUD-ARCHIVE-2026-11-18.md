# 研究与二开产物云端归档

用户要求在完整推送研究成果和二开产物后，清空本地 `fawvw` 工作区所有文件。本次范围仅该目录，不包含 LukeSONG 其他项目或 Obsidian 知识库。

## 云端入口

私有仓库：https://github.com/LukeSONG2000/fawvw

- 源码、研究文档、SDK 接口目录、GTI 查询与定位结论：main 分支。
- 本次归档：https://github.com/LukeSONG2000/fawvw/releases/tag/research-and-carcontrol-2026-11-18
- 原始输入、旧宿主过渡版、完整 ObjC 元数据：https://github.com/LukeSONG2000/fawvw/releases/tag/research-baseline

本次 Release 包含：最新 MinimalClient 开发签名 IPA；研究与开发套件 ZIP（源码、文档、静态分析、6 个原始 SDK、脱敏查询/定位证据、首页画面）；SHA-256 校验清单与归档说明。ZIP 内有逐文件摘要。既有 baseline 附件不重复上传，统一在归档说明中列出名称、大小、下载位置和摘要。

不上传会话偏好、身份令牌、账号密码、SPIN、安全签名材料原值、设备数据备份、未脱敏车辆位置或完整 VIN。私密查询证据只导出脱敏副本；本地原件及备份随工作区清空，不额外在本机建立备份。

## 恢复方法

1. 克隆私有仓库，或下载本次研究开发套件 ZIP。
2. 从 baseline Release 下载原始 IPA 放入 packages。
3. 使用本机自己的签名证书和 provisioning profile 配置构建脚本。
4. 运行 `python3 implementation/MinimalClient/build.py --ipa`。完整原宿主研究需要先运行 `python3 implementation/prepare_inputs.py --full`。
5. 账号会话不随归档保存。新账号独立密码/验证码登录和长期刷新仍未实现；需要后续继续接入。MOSC 原生坐标已证实可读，但独立客户端尚未完成认证/签名接入。物理控制与触觉/SPIN 等真机验收边界保持不变。

## 清空条件

仅在以下核验全部通过后删除本地目录内容：main 提交已在远端；新 Release 附件均已上传且服务端 SHA-256/大小与本地一致；新附件回下载的 SHA-256 校验通过；既有 baseline 三个附件摘要与记录一致；源码工作树没有未提交内容。

最终删除包括 .git、.venv-device、packages、recovered、output、源码与文档，只保留空的 fawvw 目录。云端归档与 Obsidian 文档作为恢复入口，不把本地清空误写为项目或云端仓库删除。
