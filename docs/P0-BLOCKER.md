# P0 卡点总结（MBB 登录最后一公里）— 2026-11-16

> 给后续接手（zcode/codex）：全部上下文见 `docs/P0-EVIDENCE.md` 与 `docs/ZCODE-RESEARCH-HANDOFF.md` 文末进展日志。工作区已推送 GitHub `LukeSONG2000/fawvw` main 分支。

## 已打通（无需重做）

1. **独立宿主加载**：`implementation/MinimalClient/`（21MB，6 framework 白名单）真机安装运行，CarNetLib 类注册成功；初始化三步全通（AppInfo→initialize→MbbChinaStage→useMbbStage 返回 StageActionsImpl）。
2. **踩坑已修**：iOS 13+ 必须UIScene；主程序不链接 CarNetLib 须 `dlopen(RTLD_NOW)`；`initializeWithAppInfo` 的 queue 参数 Swift 侧 Non-Optional，传 nil 会 fatalError。
3. **MBB 生产端点连通**：`https://mbboauth-1d.prd.cn.vwg-connect.cn`（TLS/pinning 全过）。
4. **clientID 已确认**：`VWGMBB01CNLIV1`（官方会话 JWT `aud[0]`，对应 Widget `loginMBBWithClientId:`）。用 `authenticateWithClientID:identityToken:successFunction:` 后，服务端错误从 `400 HttpMessageNotReadableException(Invalid Request Payload)` 变为 **`AuthError(3:missingAccessRights)`** ——请求格式已被接受，剩下授权级拒绝。

## 当前卡点

`authenticateWithClientID:VWGMBB01CNLIV1 identityToken:<官方AT>` → `AuthError(0:loginNotPossible, wrapped: 3:missingAccessRights)`（响应 0.3s，参数级拒绝）。

**2026-11-16 16:25 探针实测（已排除 brand 假设）**：clientID 路径下 6 个 brand 候选（fawvw/FAWVW/V/VW/FAW_VW/faw-vw）**全部同样 `missingAccessRights`**，错误与 brand 无关 → **头号嫌疑升为 token 类型**：我们喂的是 JWT `typ:"AT"` 的 Access Token，SDK 方法名要求 `identityToken`——MBB 大概率要 ID Token（`idt-id` 指向的那个，不落盘、只在官方 App 登录瞬间存在于内存）。次要嫌疑 AppInfo.appId 占位。

### 官方会话 JWT 的完整结构（本地取证，敏感值已隐去）

```
header: {kid: f4ed8a2a-…, alg: RS256}
claims: scp="openid profile mbb" | cor="CN" | cch="APP" | amr="pwd"
        iss=https://idp.mosc.faw-vw.com | typ/type="AT"
        aud=["VWGMBB01CNLIV1","autonavi.com","E0CEE996-9CAC-4DD3-ADA1-691CE459404F"]
        azp="APP" | appkey="07178593" | aid="21291985"
        tnt="VW_APP_iPhone_E0CEE996-…-…_27.3_4.28.0"
        idt-id=<uuid> | rt-id=<uuid> | jti=<uuid> | exp 有效至 2026-11-19
```

### 剩余嫌疑（按概率排序）

1. **MbbChinaStage.brand 占位值**（"fawvw"）。country="CN" 已被 JWT `cor` 佐证；brand 无本地证据。VW 体系 MBB brand 常见为单字母（V/A/S…）或厂商串。**正在跑的探针**：6 候选 × clientID 路径。
2. **token 类型**：JWT `typ:"AT"`（访问令牌）。SDK 方法名是 `identityToken`——**MBB 可能要求 ID Token（idt-id 指向的那个）而非 AT**。idToken 不落盘（偏好里 idToken=null），只在登录瞬间存在。若 brand 探针全败，优先怀疑此项。
   - 对策：从官方 App 内存抓 idToken（lldb attach 被平台连接问题挡住：`platform select remote-ios` 后 attach 报 platform not connected——iOS 17+ RemotePairing 通道未配好，Xcode GUI 调试一次设备即可解锁命令行 attach）；或抓包登录流程。
3. **AppInfo.appId 占位**（"TODO-RUNTIME"，密文 20B 待解）。appId 可能进入 token 交换请求的 application 标识字段。tnt 中的 `E0CEE996-9CAC-4DD3-ADA1-691CE459404F`（设备/应用 UUID，36 字符）与 20B 不符，不是它；`appkey="07178593"`（8 字符）也不符。
4. identifier/pinning 密文（0x109ebc3f0/0x109ebc430）——影响较低（构造已成功）。

### 尚未用尽的取证途径

- **宿主反汇编 `loginMBBWithIdentityToken:completion:` 的 Block 体**（0x1074ce0fc）里 `authenticateWithIdentityToken:` 前对 token 的 `fetchMbbStage` 处理——注意它 Block 第一行就调用了 `fetchMbbStage`（0x1083859e0），即 stage 是**每次登录时现取**的。宿主 stage 的 brand 从 `mbbStageAuthenticationUrl` 等 getter 来（加密池），**运行时 dump 官方 App 内存**（0x10aade4e0-0x10aade690 一带）可一次拿全 9 个密文参数。attach 通道：先用 Xcode GUI 连一次设备跑调试（解锁 lldb 命令行 attach），或从已归档 IPA 起稳定版抓崩溃期日志。
- **抓包**：mitmproxy + 用户代理（用户手机已确认可开代理）抓官方 App 登录瞬间 `/mbbcoauth/mobile/oauth2/v1/token` 的完整请求体——**一劳永逸**（请求体里 brand/appId/token 类型全暴露）。
- **密码登录协议**（独立于 MBB）：`oneapp-api.faw-vw.com/account/login/loginByPassword/v1` 字段未取证，同样可由抓包获得；响应 data 为 base64 密文（疑 GMObjC/SM4）。

## 快速复现实验环境

```bash
cd implementation/MinimalClient
python3 build.py --ipa      # 构建+签名 21MB PoC + IPA
# 设备：iPhone Air 00008150-001E34E93A12401C，独立 Bundle ID com.lukev.minimalclient（与官方补丁版并存）
xcrun devicectl device install app --device <UDID> ../../output/minimalclient/Payload/MinimalClient.app
# console 抓日志（SDK DEBUG 流走 stderr，官方 App 的 stderr 被其自身关闭，PoC 可见）：
timeout 100 xcrun devicectl device process launch --device <UDID> --terminate-existing --console com.lukev.minimalclient
```

官方会话导入：`output/dropdown-preferences.plist` 的 `com.oneapp.coreentity.tokens`（NSKeyedArchive）→ `accessToken` → 写 PoC 沙盒 `Library/Preferences/com.lukev.minimalclient.plist` 键 `imported.idToken`（devicectl copy to appDataContainer）。**注意 AT 有效期至 2026-11-19，过期需从官方 App 偏好重新提取。**
