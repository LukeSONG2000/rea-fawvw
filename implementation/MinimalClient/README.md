# MinimalClient — CarNetLib 独立最小宿主（P0）

目标：验证 CarNetLib.framework 脱离原 OneApp 主程序独立完成「网关密码登录 → MBB 令牌交换 → 车辆列表 → 只读状态」。全部调用序列与参数依据 [docs/P0-EVIDENCE.md](../../docs/P0-EVIDENCE.md) 的反汇编证据，未验证项显式标注 `TODO-RUNTIME`。

## 构建

```bash
python3 build.py --ipa
# 产物：output/minimalclient/Payload/MinimalClient.app
#       output/FAWVW-MinimalClient-PoC-dev.ipa
```

- 仅依赖 Xcode 命令行工具（clang + codesign），无 .xcodeproj，可重现。
- 输入只读：`recovered/ios-444.28.0` 的 6 个 framework + 本目录 src/。
- Bundle ID `com.lukev.minimalclient`，wildcard 开发证书签名；与设备上唯一可用安装 `com.lukev.aftermarket` 并存。

## 结构

| 文件 | 职责 |
|---|---|
| `src/MCConfiguration.h/.m` | 全部运行参数集中定义（EVIDENCE-STATIC / TODO-RUNTIME 分级标注） |
| `src/MCSDK.h/.m` | CarNetLib ObjC 适配层：typed objc_msgSend 集中封装，序列对齐 VWPCHybridMotion 反汇编 |
| `src/MCHostAuth.h/.m` | 宿主网关密码登录（account/login/loginByPassword/v1），含协议探针 |
| `src/MainViewController.*` | P0 验证 UI（登录→VIN→只读状态）；P1 才做左上角下拉菜单 |
| `build.py` | 编译、白名单打包、深度签名、IPA |

## 当前状态（2026-11-16）

- ✅ 真机 arm64 构建通过，`codesign --deep --strict` 通过，21MB。
- ✅ 真机安装（独立 Bundle ID 与现有安装并存）、启动、进程存活。
- ✅ **CarNetLib 在独立宿主进程中加载成功，「SDK 类探测：可用」**（见 P0-EVIDENCE 第 7 节）。
  - 踩坑两处已修：iOS 13+ 必须实现 UIScene 生命周期；主程序不链接 CarNetLib，需 `dlopen(RTLD_NOW)` 显式加载 Frameworks。
- ⬜ 9 个加密参数运行时取证（P0-EVIDENCE 第 5 节），回填 MCConfiguration。
- ⬜ 网关登录字段名取证（probeLoginSchema 或抓包）。
- ⬜ 用户凭据真机登录 → 两车 VIN → 一车状态，全链路只读验证。

**红线**：P0 验证通过前不覆盖 `com.lukev.aftermarket`；物理控制（锁车/启动/鸣笛）从未执行，本阶段仅只读。
