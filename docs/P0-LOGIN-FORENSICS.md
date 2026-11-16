# P0 登录链路取证记录 — 2026-11-16 晚

> 承接 [P0-RESOLUTION.md](P0-RESOLUTION.md)（MBB 认证与两车只读验证）。本轮目标：密码登录协议取证与冷启动恢复方案。

## 一、密码登录请求未被原生网络层捕获（取证结论）

给原宿主（`com.lukev.aftermarket` 覆盖探针版）注入 NSURLSession 请求侧 hook + tokens 写入 hook，用户完成「退出登录 → 手机号+密码重新登录」全程，捕获 73 个文件（本机受限目录）。结果：

- 17:02 会话：tokens 写为空归档（退出登录动作）✓；17:07 会话：tokens 写入有效内容 + SDK 认证 ✓
- **登录瞬间没有任何 NSURLSession(dataTask/uploadTask) 请求**——密码登录不走原生网络栈，**登录页为 H5（WKWebView 独立网络进程）**，与交接文档「登录页有 WebView」的记录吻合
- `api-ubtas.faw-vw.com` 出现的 POST 均为二进制 TLV 日志协议（unify_logs），非登录
- 顺带捕获：`mbboauth-1d.prd…/mbbcoauth/mobile/oauth2/v1/token` 请求体原文（SDK 认证协议样本）、`bpp.cn-vw.volkswagen-cea.com`（字节 A/B 服务）、完整车控时序（mosc 数字钥匙 → mal 车辆状态 → rolesrights）

**推论**：原生复刻密码登录需要还原 H5 登录页协议（one-app-h5.faw-vw.com 或 idp.mosc 的 Web 流程），成本高于当前收益，列为后续项。

## 二、identity token 生命周期（已确认）

| 项 | 值 | 证据 |
|---|---|---|
| 形态 | JWT，`typ=identity`、`type=identity`、RS256 | SDK 认证入口 hook 捕获 |
| 颁发者 | `https://idp.mosc.faw-vw.com` | JWT iss |
| 有效期 | **60 天**（2026-11-16 12:01 → 2027-01-15） | JWT iat/exp |
| 持久化 | **不在** UserDefaults tokens 归档（idToken=null）；疑似 CATSecureStorage(Keychain) | 归档解码 |
| 当前可用副本 | 本机受限目录（920B），PoC 偏好已注入 | 本轮 |

## 三、Keychain 组共享现状（未通，不阻塞）

- 官方 App keychain 组：`KC9H2N4239.com.fawvw.aftermarket`
- Profile（wildcard）授权 `keychain-access-groups = KC9H2N4239.*`；PoC entitlements 已声明官方组
- PoC 内 `SecItemCopyMatching(kSecClassGenericPassword + 指定官方组)` → **-25300 errSecMissingEntitlement**
- 待查：installd 对 wildcard profile 的 keychain 组剥离；或官方项组名实际不同（keychain-access-group vs application-identifier 派生组）
- 不阻塞原因：identity token 60 天有效 + 导入通道健在；下次颁发前有充足窗口解决

## 四、PoC 当前形态（2026-11-16 17:40 实测）

```
CarNetLib initialized for app BootstrapApp (1.0)     ← codex 取证的真实 AppInfo
useMbbStage → StageActionsImpl
Authenticate against mbb (using identity token)
result: Account(uniqueId=…, mbbUserId=…, mbbTokens=MbbTokens)
```

用户确认：读取车辆 VIN ✓（两辆）、当前车状态（只读）✓。**P0 只读链路（认证→车辆→状态）在独立 21MB 宿主完整可用**。

## 五、剩余工作（优先级）

1. **P1 产品化**：左上角按 VIN 单选下拉（UIMenu）、车名 `seriesName+modelName` 去重、切换防抖、选中车状态/位置统一携带 VIN
2. Keychain 组共享深查（-25300）→ 免导入冷启动
3. H5 密码登录协议还原（2027-01-15 token 到期前完成即可）
4. pin 集合对齐（沿用 RESOLUTION 待办）

## 六、本轮资产

- 探针源码（含登录链 hook、keychain dump）：`implementation/RuntimeProbe/P0RuntimeProbe.m`
- 取证数据（本机受限，不入库）：`/tmp/p1probe/`（设备侧 `Library/Application Support/P0Probe/`）
- PoC 新增：`MCKeychainForensics.{h,m}`、entitlements 官方 keychain 组
- 设备状态：官方 App = 探针版（数据完好）；PoC = 可用状态（偏好含有效 identity token）

## 七、持久会话与滚动延期（2026-11-16 17:51 实测收官）

- **启动自动登录已实现**：冷启动 3 秒自动「初始化→MBB 认证」，无感恢复；实测
  Account 返回 + 用户确认两车 VIN + 状态（里程/油量/续航真实数据）。
- **滚动延期工具**：`implementation/MinimalClient/sync-session.py`——从官方探针
  捕获的最新 identity token 一键同步进 PoC 偏好。60 天窗口内官方 App 重登一次
  → 跑一次脚本即完成"滑动延期"。
- **自动延期展望**：官方 App 的 idp.mosc 刷新请求（RT 体系，JWT rt-id 佐证）尚未
  被捕获——探针常驻官方 App，其自然刷新或下次重登时自动留证，届时还原协议。
