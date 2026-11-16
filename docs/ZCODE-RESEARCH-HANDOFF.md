# zcode 研究交接：独立最小车控客户端

更新：2026-11-16（zcode 首轮进展见文末「zcode 进展日志」）。工作目录：`/Users/lukesong/Work/Workspace/LukeSONG/fawvw`。本轮最后要求是整理研究方向交接给 zcode，已停止继续安装修改版。

## 研究主线

优先验证 **新建原生最小宿主 + 复用 CarNetLib.framework 及其必要依赖**。从原 IPA 用 REA 恢复初始化配置、身份认证、账号与车辆选择、查询及控制流程。验证可行后，用独立可构建的代码替换原 OneApp 主程序。

交付标准是包内实际只包含登录、账号车辆身份、控制和相关查询的代码与资源。隐藏标签、拦截路由、隐藏 WebView、删除页面素材，都不能单独算“彻底移除非车控功能”。

这条路线目前是有实物证据支持的研究方向，不是已验证可独立运行的 SDK 集成方案。必须先证明 SDK 可脱离原宿主启动和认证；尤其要核对一汽大众当前账号体系是否实际使用 SDK 的 FAWVW 身份提供器，不能仅凭同名方法认定可以替代现有登录。

## 用户要求，按此验收

- 保持原账号登录模式和车辆授权体系；优先级：密码 > 短信验证码 > 运营商一键授权 > 微信 > 苹果。先满足最小可用，密码优先。
- 只保留车辆控制和相关信息查询；去掉资讯、商城、营销、活动及冗余内容。
- 不显示开屏广告、首次安装引导、用户协议弹窗及勾选行。已有补丁通过调用原继续事件处理，含自动继续本地协议确认的行为；新客户端须明确复核实际初始化依赖。
- 支持代理；当前补丁版用户已确认代理开启时可以使用。
- **左上角车名打开下拉菜单**，不要底部弹出选区；单选，只标记一个当前车辆；显示可区分的车名/车型。
- 继续使用同一开发版 Bundle ID `com.lukev.aftermarket` 覆盖安装，显示名“一汽大众·车控”，保留数据，不增加重复副本。官方版为另一个 Bundle ID。
- 用户只对之前安装记录损坏的那一次卸载重装给过明确授权；当前覆盖安装已修复，后续不要自行重复卸载。
- 真机登录由用户输入账号密码。不要把备份、令牌、密码、VIN、手机号混入公开交付文档或日志摘要。
- 实际开锁、启动、鸣笛等物理控制没有执行过，不得宣称验证成功；本阶段优先只读验证。

## 为何不能继续靠原包 UI 补丁达到目标

原 `OneApp` 主程序约 187.1 MiB，登录及大量资讯、商城和车控 UI 类型静态链接在同一 Mach-O。仅隐藏原生标签页，其他业务代码和初始化依赖仍在。

独立动态组件中，CarNetLib.framework 约 19.3 MiB，UnityFramework 约 155.9 MiB，另有阿里云音视频、FFmpeg 等组件。这些数字是提取后目录/文件量，不是最终 IPA 压缩大小；不能直接相加推导可删除量。原主程序仍有强链接和绑定引用，直接删 Framework 会造成 dyld 或后续调用失败。

最小宿主应从零列白名单，不复制原 OneApp 可执行文件、Unity、商城/资讯/活动资源或原小程序容器。必要认证组件必须有调用链证据后才纳入，不能机械删除全部 Web 组件而破坏真实登录。

## REA 已找到的 SDK 切入点

目标：`recovered/ios-444.28.0/Payload/OneApp.app/Frameworks/CarNetLib.framework/CarNetLib`。

SHA-256：`c9594a2256eea8438fa0bdfe6891c59bb648bbcac06180328660696e46f25798`。

REA 的 Mach-O 证据：`ev_32520ea95ccfa40c44a26c130ee78490efb2f2776500a9a80dea66271bd7f833`，已完整导出至 `analysis/rea-carnet-sdk-evidence.json`。工具返回曾超过传输预算，分析本身已完成，勿因该传输错误重跑同一分析。

补充本机证据：

- `analysis/carnet-public-symbols.txt`：`nm -gjU` 后 swift-demangle 的导出符号。
- `analysis/carnet-objc-metadata.txt`：SDK 的 `otool -ov` 元数据。
- `analysis/carnet-objc-api-inventory.txt`：由上述元数据抽取的类/方法清单，便于定向定位；不是恢复出的原始头文件。
- `analysis/carnet-information-symbols.txt`：部分查询模型字段。
- `analysis/car-interface-candidates.json`：原主程序中的路径字符串和文件偏移，属于接口候选，未证明每条当前可用。

SDK 暴露了 ObjC 可调用入口，不必起步就恢复整个 Swift 模块接口：

| 范围 | 元数据/导出中的具体入口 |
|---|---|
| SDK 根类 | `CarNetLib.CarNetLib`，运行时名 `_TtC9CarNetLib9CarNetLib` |
| 初始化 | `initializeWithAppInfo:config:`、`initializeWithAppInfo:config:extensionDispatchQueue:` |
| 环境 | `useIdentityProviderStage:`、`useMbbStage:`、`useBackendConfiguration:` |
| SDK 客户端注册与认证 | `StageActionsImpl.registerClientWithSuccessFunction:`、`authenticateWithClientID:identityToken:successFunction:` |
| 身份提供器密码入口 | `IdentityProviderStageActionsImpl.fetchIdentityTokenWithClientId:username:password:identityTokenFunction:` |
| 验证码候选 | `fetchImageCodeWithClientId:ImageCodeFunction:`、`fetchSMSCodeWithClientId:username:smsCodeFunction:`、`fetchLoginAndRegisterWithClientId:username:smsCode:picContent:picTicket:identityTokenFunction:` |
| 账号车辆 | `useAccount:`、`useVehicle:`、`AccountActionsImpl.vehicleVinsWithSuccessFunction:`、`vehiclesWithVehicleFunction:` |
| 状态与位置 | `VehicleActionsImpl.statusWithStatusFunction:`、`updateStatusWithStatusFunction:`、`locationWithVehicleLocationFunction:` |

上述方法的返回对象、Block 类型、异步执行方式、失败回调和 SPIN 保护不能猜测。由相邻元数据的 type encoding、协议和原宿主调用点恢复准确声明。先建立小型 ObjC 适配层，避免在所有业务代码中散布无类型 objc_msgSend。

SDK 的直接非系统动态依赖已见：AEXML、AnyDate、EVReflectionCore、TrustKit（另有系统 Swift 运行库）。继续做完整递归闭包及运行时资源依赖核查；这是独立宿主初始候选白名单，不代表最终全部必要组件。

## 推荐阶段和停止条件

### P0：证明独立宿主能工作

1. 新建 `implementation/MinimalClient/`，使用可重现的 iOS UIKit 工程/构建脚本；保留原 IPA 和 recovered 输入不动。
2. 通过 REA 定向追原 OneApp 的 SDK 初始化与登录调用：AppInfo、身份服务/令牌交换服务、MBB/FAL/MAL 环境、clientID 来源、成功失败 Block、令牌刷新和持久化。
3. 只带 SDK 依赖白名单，启动并查询 SDK 版本/初始化结果。包中不得带原 OneApp 主程序或整套原 UI 资源。
4. 对照原密码登录链路，证明 SDK 提供器仍适配当前服务；若原 OneApp 使用不同账号网关，单独恢复该网关的密码登录/验证码/刷新协议，再把身份令牌交给 SDK。不要将已登录备份当成完整登录实现。
5. 由用户在设备输入账号密码，完成一次全新登录、退出、冷启动恢复和过期处理；随后只读取得两辆车及一辆车状态。

**P0 未通过之前，不大规模重做页面，不把新宿主覆盖到唯一可用安装上。** 用本机构建和独立宿主验证环境准备好，交接中保留稳定 IPA。正式替换仍使用同 Bundle ID，事先确认数据迁移格式和签名兼容。

### P1：车辆标识与下拉菜单

- 内部唯一主键用非空 VIN，不用显示名称或行号。
- 当前车只存一个 VIN。空 VIN 不得等于空“当前 VIN”从而把所有行打勾。
- 名称建议 `seriesName + operateVehicleModelName/modelName`，重复部分去重；同名车以车牌或 VIN 尾号在本机 UI 区分。
- 菜单锚定左上角车名，使用 `UIButton.menu` / `UIMenu` 的单选能力；不创建底部 sheet。
- 明确“本机当前操作车”与“服务端默认车”的关系。旧补丁尝试复用设默认车流程，会改变账号默认车辆。独立客户端优先通过 SDK 显式选车；若必须修改默认车，记录该行为。
- 切换中禁用重复提交；后端/SDK 成功再更新当前车，失败保持原车；状态、位置、控制请求均带同一选中 VIN，忽略前一辆车迟到的响应。

### P2：按能力接入控制和查询

- 每辆车读取能力/服务开通/授权信息，菜单按能力显示；不要因为包里有充电接口就给汽油车显示充电。
- 先接状态、位置与操作结果轮询，再接最小控制。
- SPIN、原有车辆授权、权限和敏感操作验证继续走原体系。
- 指令发起、受理、轮询成功、超时、车辆离线分开处理；HTTP 成功不等于车辆执行成功。

### P3：包内实际精简验收

- 输出依赖白名单、最终包文件清单、各组件大小、Mach-O 动态依赖和删除前后差异。
- 确认原 OneApp 主程序、资讯/商城/广告/活动模块、Unity 与不需要的音视频/小程序资源不存在；必要认证依赖须有解释。
- 检查启动与切换过程中无非车控模块初始化/请求，不能只检查首页截图。
- 签名严格校验、IPA CRC、覆盖安装、登录、两车切换、每车只读状态、冷启动和代理开启逐项验收。
- 保留同一开发版图标和数据；文档与 Obsidian 对应目录同步。

## 车控能力范围：已发现，不等于当前两车全部支持

| 分类 | SDK/包内发现的能力 | 证据与限制 |
|---|---|---|
| 门锁 | 上锁、解锁，门锁状态及结果轮询 | `LockUnlockService/Repository`；当前 GTI 页面入口可见，未发实际指令 |
| 车窗/天窗 | 开、关、通风开度操作；车窗/天窗状态 | `windowSunroofOpen/Close/VentingOpen`；必须按车辆能力区分，未实际执行 |
| 发动机 | 远程启动、停止、状态/历史 | `RemoteStartService/Repository`；GTI 启动入口可见，停止能力未真机确认 |
| 寻车 | 闪灯、鸣笛、位置查询 | `HonkFlashService`、`VehicleActionsImpl.location`；具体组合、持续时间及权限待恢复请求模型 |
| 空调 | 启停、设置、前后窗加热、状态 | `ClimatisationService` 与 Feature 字段；车型条件能力，不代表 GTI 当前可用 |
| 电动车充电 | 启停、充电设置、定时/出发计划、充电状态 | `ChargerService`、`DepartureTimerService` 等；不应作为当前两台燃油车的默认功能 |
| 车况 | 状态时间戳、总里程、油/电/气余量、主/副动力及合计续航 | `VehicleStatus` 字段；本机 GTI 页面已显示续航/油量等，不代表全部字段有值 |
| 车身 | 车门/窗/天窗/机盖/尾门等组件状态、中央门锁 | `BodyStatus`、`InternalWindowSunroofStatus` 等；按支持项解析未知值 |
| 保养/告警 | 下次保养/换油剩余天数和里程、健康告警 | `VehicleStatus`、`InternalWarningsReport`；尚未逐项查验服务返回 |
| 位置/行程 | 停车位置、行程统计 | `location`、`TripStatisticsActionsImpl`；具体可返回字段及历史保留范围待验证 |
| 扩展提醒 | 防盗历史、速度提醒、地理围栏 | 对应 Service/Repository；可能超出用户最小范围，先研究，不自动纳入产品 |

胎压、摄像头/远程影像、远程泊车等在原包其他组件中可能有实现，但目前没有足够证据认定当前两车可读可控，不列入已确认清单。

原主程序中的有用接口候选包括：

- `mycar/base/vehicle/v1/get-function-list`、`get-function-list-by-keys`：能力列表候选。
- `mycar/base/vehicle/v1/vehicle-info-vins`：按 VIN 取车辆信息候选。
- `profile/vehicle/vehicleList/v1`、`getVehicleDetailList/v1`、`setDefaultVehicle/v1`：账号车辆与默认车候选。
- `mycar/car-networking/rvs/v1/get-vehicle-status`：状态查询候选。
- `mycar/car-networking/rlu/v1/get-vehicle-door-locked-state`：门锁状态候选。

这些是静态字符串证据，不是可直接调用的完整 API 文档；请求方法、Base URL、签名、参数、鉴权和响应都需要沿实际调用链确认。

## 当前补丁版现场，避免误当完成品

### 最后已确认可用的归档包

`output/FAWVW-444.28.0-CarControlOnly-dev-signed.ipa`

- SHA-256：`44ce7107113af661d52365ef4157420a71c03a42e9ab662bcdb960db4856f66b`
- 大小：399209413 字节。
- 用户确认原生密码登录成功、代理开启可进入车控；截图 `output/proxy-car-screen.png` 显示 GTI 页。
- 这是保留原 OneApp 的补丁版；**多车切换不可靠，包内实际精简未完成**，不能标为最终交付。

### 设备当前安装和源码更靠前，尚未验证

最后安装的是新下拉菜单候选，来自 `output/signed/Payload/OneApp.app`，不等于上面的归档 IPA。日志在 `output/dropdown-verify-2.log`。该候选仍出现车辆页重建/重复初始化，默认标记解码错误使所有记录未正确就绪。**不得直接把这个目录重新打包宣称稳定。** 需要时从上述已归档 IPA 恢复同 ID 安装，保留数据，不卸载。

源码 `implementation/CarControlOnly/VehiclePage.m` 在最后安装之后已修正一处归档解码问题，尚未重新部署：

- 原 `FVVehicle` 为 Swift 模型，KVC 无法读取所需字段，导致名称和 VIN 为空。
- 新 `CCOVehicleRecord` 通过 NSKeyedUnarchiver 将 `FVVehicle` 映射为可读记录。
- `isDefaultVehicle` 在归档中是 **NSNumber 对象引用**；必须 `[[coder decodeObjectForKey:@"isDefaultVehicle"] boolValue]`，不能 `decodeBoolForKey:`。后者让 unarchiver 进入错误态，第二辆车也无法解码。
- 本机探针 `analysis/decode_vehicle_records.m` / `output/decode-vehicles` 验证：两条记录均有 17 位 VIN；GTI 默认标记为 true，另一车 false；型号分别 GTI、探影1.5L 自动 悦，系列分别高尔夫 A8、T-CROSS。
- 原车行的 `editToolsBar` 实际为 **UIView 子类 VehicleEditToolsBar**，不是 UICollectionView。现 `DefaultActionInRow` 直接按 UICollectionView 判断，因此操作关联仍失败；应在该 UIView 内找到其 collection，或在独立客户端直接通过 SDK 选车。
- 原 URL `faw-vw://vehicle/list` 有导航副作用，虽已拦截 FVNavigationController 的 push，仍会触发车辆页变化。不要把这个路径作为独立客户端最终选车架构。

### 已定位的两个二进制补丁

- 原主程序文件偏移 `0xe3f8`：`40010036` → `1f2003d5`，独立 Bundle ID 启动身份门禁。
- `0x18af8cc`：`a7a4a995` → `000080d2`，单个业务代理检查回调中的 CFNetworkCopySystemProxySettings 调用改为空结果路径。系统代理路由和通用 TLS 校验未更改；单设 AppSetting.isProxyAllow 不足以解除原拦截。

这些补丁只用于旧宿主过渡版；新宿主不应复制原主程序再继续叠加它们。

## 开发与证据入口

- 原始 IPA：`packages/com.fawvw.aftermarket_444.28.0_cn_iphone_dumpipa.com.ipa`。
- 提取输入：`recovered/ios-444.28.0/Payload/OneApp.app`；不要直接改它。
- 原主程序元数据：`analysis/objc-runtime-metadata.txt`（约 127 MB，定向搜索）。
- REA 初始证据：`analysis/rea-package-evidence.json`、`analysis/rea-native-evidence.json`。
- 旧补丁源码/构建入口：`implementation/CarControlOnly/`。
- 设备：iPhone Air，UDID `00008150-001E34E93A12401C`；开发版 `com.lukev.aftermarket`。
- 签名脚本：`implementation/CarControlOnly/sign-development.py`；现有开发证书/描述文件位置由此查阅，不在交接中复制私密材料。
- 安装修复经验：原商店 `SC_Info` 与被删除的扩展记录导致覆盖安装失败；开发重签副本需清理过时商店安装元数据，原输入不动。现有覆盖安装已成功。
- REA 原生深度提供器当前未配置可用；本轮使用 REA Mach-O 检查，加本机 nm/otool/llvm-objdump。不要把元数据清单说成已反编译完整源码。需要函数反编译时先核查对应 provider，不因缺引擎反复重配 MCP。
- 本机敏感现场：`output/device-backups/`、`output/*preferences.plist` 和原生请求日志。供本机恢复/核查使用，不公开、不随最小 IPA 打包。

## 建议交给 zcode 的首条任务

> 在本工作区用 REA 验证 CarNetLib 脱离 OneApp 的最小宿主。先恢复 SDK 初始化和一汽大众密码登录→身份令牌→MBB 账号→车辆列表→状态读取的真实链路，交付可构建 PoC、精确依赖白名单和证据记录。用户输入凭据，只进行只读验证。P0 成功后再做左上角按 VIN 单选的车型下拉菜单、最小车控 UI 和逐项控制能力。最终 IPA 不含原 OneApp 主程序和非车控业务模块；当前补丁版只作为过渡与证据，不能以隐藏入口冒充彻底移除。

## zcode 进展日志（2026-11-16 首轮）

成果与证据全文见 `docs/P0-EVIDENCE.md`（证据分级：EVIDENCE-STATIC / TODO-RUNTIME），此处只列结论：

1. **宿主 SDK 适配层定位并反汇编**：`VWPCHybridMotion`（initializeCarNetLib / fetchMbbStage / loginMBBWithIdentityToken / fetchVehicleByVin 等 imp 已知）；Widget 侧 `MosiWidgetCarnetLibManager` 同构，官方 `OneAppWidgetExtension.appex`（22MB）即"最小宿主"实证。
2. **登录链路定性（回答交接核心疑问）**：原宿主**不使用** SDK 的 FAWVW 身份提供器（selref 无任何引用）；密码登录走宿主网关 `oneapp-api.faw-vw.com/account/login/loginByPassword/v1` 拿身份令牌，再 `useMbbStage:` → `authenticateWithIdentityToken:accountFunction:` → `executeWithErrorFunction:` 换 MBB 令牌。
3. **生产环境参数确认**：mbboauth-1d/fal-3a/mal-3a `.prd.cn…vwg-connect.cn`、scope `openid profile mbb`、ActionConfig(123.0, 2.0)。brand/country/AppInfo×5 等 9 个参数为逐串独立密钥的流密码密文（静态不可解），已列取证清单。
4. **依赖白名单闭包（6 件）**：CarNetLib + AEXML + AnyDate + EVReflectionCore + **XMLDictionary**（EVReflectionCore 递归依赖，易漏）+ TrustKit。
5. **MinimalClient PoC 已建并真机运行**：`implementation/MinimalClient/`（纯脚本构建，21MB，Bundle ID `com.lukev.minimalclient` 与现有安装并存）；iPhone Air 实测**进程存活、SDK 类探测「可用」**——CarNetLib 脱离 OneApp 独立加载成功。踩坑记录：iOS 13+ 须 UIScene 生命周期；主程序未链接 CarNetLib 时须 `dlopen(RTLD_NOW)`。
6. **归档**：GitHub 私有仓库 `LukeSONG2000/fawvw`（main + Release `research-baseline`：原始 IPA / 补丁版 IPA / 133MB 元数据 gz）；敏感备份、偏好、运行日志未入库。

### 下一步（按优先级）

1. 运行时取证 9 个加密参数：设备上运行原 App 时 dump `MosiWidgetCarnetLibManager` 各 getter 返回值与 AppInfo 五参数（一次操作全部拿到），回填 `MCConfiguration`。
2. 网关登录协议：一次抓包或 `probeLoginSchema` 确认 loginByPassword/v1 字段与 data 解密（响应样例显示 data 为 base64 密文，注意 GMObjC）。
3. 用户输凭据全链路只读验证：登录 → MBB → 两车 VIN → 一车状态（P0 验收线）。
4. P0 通过后：P1 左上角按 VIN 单选下拉（`UIButton.menu`/`UIMenu`），再 P2 能力化车控。

## zcode 进展补记（2026-11-16 晚，交接 codex）

- 闪退已修：initializeWithAppInfo 的 queue 参数为 Non-Optional（传 nil 触发 SDK 日志渲染 fatalError）；改为 dispatch_get_main_queue 后初始化三步全通。
- MBB 已连到生产端点；clientID=VWGMBB01CNLIV1（官方会话 JWT aud[0]）使错误从 400 Invalid Payload 进化为 AuthError(3:missingAccessRights)。
- brand 探针 6 候选全败（错误与 brand 无关）；头号嫌疑是 token 类型（官方 AT vs SDK 期望的 ID Token，idToken 不落盘）。
- 官方会话导入通道可用（偏好 tokens 归档 → PoC 沙盒 imported.idToken）；AT 有效期至 2026-11-19。
- 完整卡点与取证途径见 `docs/P0-BLOCKER.md`；全部代码已推送 GitHub main（最新 commit 含探针与 clientID 路径）。
