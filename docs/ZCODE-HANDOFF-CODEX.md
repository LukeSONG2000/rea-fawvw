# zcode → codex 交接：MinimalClient 现状（2026-11-17 上午）

> **2026-11-17 下午定位更正（仅 GTI）**：MOSC `getLastGnss` 已实际返回明文 JSON 经纬度及 updateTime，地图车辆标记与返回坐标一致；高德逆地理编码实际返回 `INVALID_USER_SCODE / 10008`。不能继续用“MBB CF 不可用”推断整车无法定位，也不能用“MOSC 请求全密文”排除此接口。真正官方版为未修改的 `com.fawvw.aftermarket`，探针覆盖的是开发版 `com.lukev.aftermarket`；下表旧记录中的两者身份混淆已更正。最新只读证据及缓存边界见 [GTI-INFORMATION-AND-LOCATION.md](GTI-INFORMATION-AND-LOCATION.md)。

> **2026-11-17 接手更正**：两车 VSR 均已读通，早期失败分别涉及错误 HomeRegion 与 Accept-Language；行程 0 为长期、1 为短期，权限地图 scope 应为 All。已完成 62 项逐车只读调查，详情见 [CAPABILITY-EXPLORATION-2026-11-17.md](CAPABILITY-EXPLORATION-2026-11-17.md)。下文保留为历史交接，非最新能力结论。

> 前情：`P0-RESOLUTION.md`（你们的 MBB 突破）→ 本文档（zcode 后续全量功能轮）。
> 仓库 `LukeSONG2000/fawvw` main 分支最新（本轮全部已提交，最新 commit 见 git log）。

## 一、当前设备状态（重要）

| 安装 | 状态 |
|---|---|
| `com.fawvw.aftermarket`（官方补丁版） | **当前为带探针的重签版**（我扩展的 P0RuntimeProbe：网络请求捕获 + vehicledata/getStatus 响应捕获 + keychain dump）。可正常使用，数据完好。**最终交付前须移除探针恢复**（稳定归档 IPA 未动：`output/FAWVW-444.28.0-CarControlOnly-dev-signed.ipa`） |
| `com.lukev.minimalclient`（PoC） | 最新版 24 按钮（构建 `python3 implementation/MinimalClient/build.py --ipa`）。偏好已注入 identity token（有效至 2027-01-15），启动 2 秒自动登录 |

## 二、本轮新增能力（代码全在 `implementation/MinimalClient/src/`）

**持久会话**
- 启动自动登录（无感恢复，实测过：Account 返回+两车+状态）
- `sync-session.py`：从官方探针捕获的 identity token 一键同步进 PoC（60 天滚动延期）

**控制（用户已明确授权执行；全部带确认弹窗）**
- 寻车闪灯/鸣笛、锁车/解锁、车窗通风/全开/全关（SPIN 保护路径）
- 空调开 22℃（`ClimatisationSettings(heaterSource:0, TemperatureValue(22,0), YES)`）/关
- 辅热开/关（`remoteAuxiliaryHeating` 门面）
- 发动机启（**SPIN 弹窗手动输入**，三 Date 防重放参数传 now；`securityPinWithSecurityPin:` 换 runnable）/停
- ⚠️ **用户尚未逐项反馈控制实测结果**——授权≠验证，逐项实测记录待做

**查询**
- 行程统计 `trips()`（TripData 15 字段/程：时长/里程/均速/平均油耗…）
- 空调状态、健康告警、保养+门窗细态（prettyStatus 扩展 nextService*/bodyStatus）
- 深度探测 `deepProbeAll`（12 项批量：车辆用户/启动历史/寻车配置限制/出发计划/空调定时/围栏/超速/防盗/配对/充电/门窗）
- 原始直连（`MCSDKRawData.rawGet`，Bearer=mbbTokens.accessToken.token）：
  - `vehicleDataDetail_v2_1_0` ✅（两车静态档案：GTI=GOLF 2.0 GTI/DTJ/WNL/2026/MIB3OI/联通T-Box）
  - `vsr statusreport_v1` ⛔ **两车均 unknownService（未开通）→ 绝对油量无通道**，官方 App 也只有百分比
  - `operationlist_v3_0_2`（权限地图，用户点过但我没在 console 窗口内拿到输出）
  - `homeRegion`（json）

## 三、待办（按优先级）

1. **采集深度探测+权限地图结果**：console 抓取（`launch --console` 必须 launch 时附加，窗口 240s 内让用户点击）或改成写 `Documents/deep-probe.txt` 再拉容器。**最终版（三轮闪退修复后）尚未真机验证**
2. **控制逐项实测**（风险序：闪灯→锁/解锁→车窗→空调→辅热→发动机SPIN），记录成功/SPIN 拒绝/不支持
3. P1 打磨：下拉菜单 VIN 显示收缩为尾 6 位；保养/门窗细态做进状态卡
4. keychain 组共享 `-25300`（profile 授权 `KC9H2N4239.*`、entitlements 已声明官方组仍被拒；疑 installd 剥离，或实际组名不同）
5. H5 密码登录协议（60 天窗口内；探针会自动捕获官方 App 刷新/重登流量）
6. 最终交付：官方 App 移除探针；P3 精简验收（对照交接文档 P3 清单）

## 四、本轮踩坑记录（务必避开）

1. **Swift 计算属性未 @objc 暴露时，任何消息调用（valueForKey/objc_msgSend）→ `doesNotRecognizeSelector:` → Swift fatalError → abort**。@try 拦不住！必须先 `respondsToSelector:`。工具函数 `MCSafeGet`（MCSDK_Internal.h）
2. **`QueryAction.loadWithErrorFunction:` 与 `ExecutableAction.executeWithErrorFunction:` 不能混用**（同样 abort）。深度探测的 RunQuery 已自适应
3. `initializeWithAppInfo` 的 queue 参数 Non-Optional（传 nil → 日志渲染时 fatalError）
4. 探针包装 completionHandler 的 block 若捕获 request/entry 等对象 → CFNetwork task 销毁路径析构悬垂崩溃；**只捕不可变副本（copy）安全**
5. devicectl 陷阱：`appDataContainer` 拉取间歇 error 3（重启设备或换时段可恢复）；console 只在 launch 时附加；官方 App stderr 已关闭（PoC 正常）
6. mosc 数字钥匙体系**放弃直连**：请求体全加密（data 密文+protobuf+SE keyAggrement 设备绑定），性价比极低

## 五、接口速查（本轮新取证）

```
GET mal-3a/api/vehicleMgmt/vehicledata/v2/vehicles/{vin}
    Accept: application/vnd.vwg.mbb.vehicleDataDetail_v2_1_0+xml   → 静态档案
GET mal-3a/api/bs/vsr/v1/vehicles/{vin}/status
    Accept: application/vnd.vwg.mbb.VehicleStatusReport_v1_0_0+xml → 未开通
GET mal-3a/api/rolesrights/operationlist/v3/vehicles/{vin}/users/{mbbUserId}
    Accept: application/vnd.vwg.mbb.operationList_v3_0_2+xml       → 权限地图
GET mal-1a/api/cs/vds/v1/vehicles/{vin}/homeRegion  (json)
公共头: Authorization: Bearer <mbbTokens.accessToken.token>, x-app-name: BootstrapApp, x-app-version: 1.0
mbbUserId 来源: Account.mbbUserId（MCSafeGet）
```

密文参数历史与全部早期证据见 `P0-EVIDENCE.md`（顶部有更正声明）/ `P0-LOGIN-FORENSICS.md` / `P0-BLOCKER.md`。
