# 车控与信息查询能力实证清单

日期：2026-11-17。对象为当前账号的高尔夫 GTI 与探影 T-CROSS，基线为已提取的 iOS 444.28.0 CarNetLib。

本轮完成：SDK 导出接口静态目录、两车能力与权限读取、每车 31 项（共 62 项）只读探测、原始状态字段解析。**没有执行开锁、启动、鸣笛、闪灯等物理指令，没有修改围栏、定时、配对或车辆默认设置。**

## 1. 最有价值的结论

- 两车可用功能不同，不能把通用 SDK 的全部方法做成共同按钮。
- GTI 声明支持且当前权限包含发动机启停、锁/解锁、车窗开/关/通风、鸣笛/闪灯；仍需逐项实车验收执行结果。
- 探影声明支持且当前权限包含锁/解锁、鸣笛/闪灯；车窗控制、发动机启停没有对应能力。停车位置查询已成功。
- **两车完整 VSR 状态接口均成功返回 HTTP 200**，推翻先前“均 unknownService，未开通”的结论。探影本次 74 个原始字段、GTI 56 个，其中分别 68/51 个字段有 value；空值、历史告警、占位及 not_supported 也计入原始字段总数，因此不等于 130 个有效传感器。
- SDK 之外额外取到了车窗开度百分比、驻车制动、机油相关原始字段、逐字段时间信息，探影另有室外温度字段。数字胎压本轮未获得有效值。
- 长期、短期、周期三类行程都读通。探影返回 16/500/100 条，GTI 返回 1/41/5 条。它们是本次接口返回量，不保证是账号全部历史；诊断 JSON 每个集合最多保存前 100 条明细，另保留完整返回条数。

## 2. 控制能力矩阵

“声明及授权通过”表示 SDK 子能力标志与当前正确区域权限地图共同支持，**不是已经执行成功**。SPIN、车辆状态、在线情况及服务端风控仍可能影响实际指令。

| 控制 | 高尔夫 GTI | 探影 T-CROSS | 依据 |
|---|---|---|---|
| 锁车 | 声明及授权通过 | 声明及授权通过 | lockSupported + rlu_v1/LOCK |
| 解锁 | 声明及授权通过 | 声明及授权通过 | unlockSupported + rlu_v1/UNLOCK |
| 车窗全开 | 声明及授权通过 | 当前不支持 | windowSunroofOpenSupported + WINDOWSUNROOFOPEN |
| 车窗全关 | 声明及授权通过 | 当前不支持 | windowSunroofCloseSupported + WINDOWSUNROOFCLOSE |
| 车窗通风 | 声明及授权通过 | 当前不支持 | windowSunroofVentingOpenSupported + WINDOWSUNROOFVENTINGOPEN |
| 发动机启动 | 声明及授权通过；SDK 为 SPIN 保护流程 | 当前不支持 | remoteStartFeature + rstart_v1/START_ACTION |
| 发动机停止 | 声明及授权通过 | 当前不支持 | stopActionSupported + STOP_ACTION |
| 闪灯、鸣笛、鸣笛加闪灯 | 声明及授权通过 | 声明及授权通过 | honkFlashFeature + rhonk_v1/P_VREQ；SDK 有三个独立入口 |
| 远程空调、设温、窗加热 | 当前未提供能力 | 当前未提供能力 | climate/pretrip 查询均 featureNotAvailable |
| 辅助加热 | 当前未提供能力 | 当前未提供能力 | auxiliaryHeatingStatus 为 featureNotAvailable |
| 充电启停与设置 | 当前未提供能力 | 当前未提供能力 | 两代 chargerStatus 均 featureNotAvailable |
| 出发计划、空调/充电定时 | 当前未提供能力 | 当前未提供能力 | departure/profile 查询均 featureNotAvailable |

两车寻车配置均返回默认 15 秒、最长 30 秒、honkForbidden=false、flashForbidden=false。maximumDistanceToVehicle 返回 0，语义未确认，不解释为“无限距离”。

接口中的 windowSunroof 是合并命名，不足以证明车窗和天窗硬件均可独立控制。当前结论限定为车窗开/关/通风能力；具体天窗硬件及独立控制待查。

## 3. 信息查询矩阵

| 信息 | 高尔夫 GTI | 探影 T-CROSS | 本轮实证 |
|---|---|---|---|
| 总里程、燃油百分比、燃油续航 | 成功 | 成功 | SDK VehicleStatus 与原始 VSR |
| 门锁、各车门、尾门、机盖、窗状态 | 成功 | 成功 | bodyStatus 与原始状态；具体未支持分量保留未知值 |
| 车窗开度百分比 | 原始报告有值 | 原始报告有值 | 0x030105 组的百分比字段；不止 SDK 的开/闭枚举 |
| 驻车制动、驻车灯、上报车速 | 原始报告有值 | 原始报告有值 | parking_brake、parking_light、speed_ok |
| 机油相关百分比与显示状态 | 原始报告有值 | 原始报告有值 | oil.level、oilDisplay 字段；非燃油百分比 |
| 室外温度 | 本次报告未见 | 成功 | 0x0301020001，单位 dK，可按 value/10−273.15 转 ℃ |
| 保养/换油剩余天数和里程 | 成功 | 成功 | 四个 nextService/nextOilService 字段与健康报告 |
| 健康/故障提醒 | 查询成功，本次无有效提醒 | 查询成功，本次一条钥匙电池提醒 | healthWarnings；warning.msgA21E 对应“请更换遥控钥匙电池。” |
| 停车经纬度与上报时间 | 当前 MBB 通道不支持 | 成功 | GTI SDK 为 featureNotAvailable、原始 CF 为 403；探影两者均成功 |
| 长期行程 | 1 条 | 16 条 | TripType=0 |
| 短期行程 | 41 条 | 500 条 | TripType=1 |
| 周期行程 | 5 条 | 100 条 | TripType=2 |
| 行程时长、里程、起始/累计里程、均速、平均油耗、结束时间 | 成功 | 成功 | 本次三种行程均有这些非空字段 |
| 电耗、能量回收、零排放里程等 | 本次无有效值 | 本次无有效值 | SDK 字段存在，但当前两车本次为空/未启用 |
| 发动机启动历史 | 查询成功，当前 0 条 | featureNotAvailable | RemoteStartHistory |
| 最近一次发动机操作状态 | 查询成功 | featureNotAvailable | QueryRemoteLastStatus；不代表本轮发起过启动 |
| 防盗通知历史 | 查询成功，当前 0 条 | featureNotAvailable | antiTheftNotifications |
| 手机配对状态与最近结果 | 接口可读；当前状态回调为 nil | featureNotAvailable | nil 不等于已经配对；此体系不能直接等同数字钥匙/Apple Car Key |
| 围栏定义与通知 | featureNotAvailable | 当前账号 403，无相应读取权限 | 探影 SDK 声明服务存在，但 requestDefinitions/HistoryWithUserRoleGranted=false |
| 超速提醒定义与通知 | featureNotAvailable | 当前账号 403，无相应读取权限 | 不能把权限不足归类为车辆硬件不支持 |
| 车辆用户与角色 | 成功 | 成功 | 当前分别 PRIMARY_USER、SECONDARY_USER；正确区域均 HG_3 |
| 年款、车型代码、发动机/变速箱代码、MMI、颜色编码 | 成功 | 成功 | CarportData 与 vehicleDataDetail |
| T-Box/通信模块、SIM 运营商等静态档案 | 可由档案进一步展示 | 可由档案进一步展示 | vehicleDataDetail/vehicleDevices；本轮未把 IMEI 等标识导出到共享证据 |

### 数据含义和时效边界

- 这是车辆上报到后端的快照，**不等于实时遥测**。原始字段有各自采集/发送/接收时间，不能把所有字段当成同一时刻。
- SDK 还提供 updateStatusWithStatusFunction:，权限包含车端状态请求相关操作。本轮未主动申请车端刷新，后续可单独验证该只读刷新路径。
- 原始报告中有 1.0 L 的 `0x0204040001`，同组为机油信号；该字段确切含义仍需核对，**不能作为油箱剩余汽油升数**。本轮未取得经过确认的剩余燃油升数。
- 探影出现多个 tyre_invalid 占位，GTI 本次没有有效数字胎压字段。因此不能展示“每个轮胎多少 bar”。告警文字映射含胎压告警定义，也不能等同实时胎压可读。
- 原始 VSR 中出现某个 warning textId 不表示当前告警生效。当前有效提醒以 SDK 健康报告的 warnings 为准，并保留时间戳。
- 保养剩余量可能为负，本轮保留原始数值；不把它自动换算为真实保养结论。

## 4. 本轮解决的研究问题

### 每车必须动态选择后端区域

HomeRegion 实测：

- 探影：`https://mal-1a.prd.cn.vwg-connect.cn/api`
- GTI：`https://mal-3a.prd.cn.dp.vwg-connect.cn/api`

先前原始接口把两车都发到 mal-3a。探影因此被错误读成 GUEST_USER/HG_0，并出现 unknownService。改为每车解析 HomeRegion 后，真实角色为 SECONDARY_USER/HG_3，状态、档案、位置和权限地图均成功。不能将错误区域的失败作为功能不可用证据。

### Accept-Language 必须符合服务端格式

系统自动产生 `zh-CN,zh-Hans;q=0.9`，VSR 将其作为完整 Language 参数校验，返回 FaultCode 9026。原始请求显式指定 en-US 后，GTI VSR 成功。这个错误不是未开通服务。

### 认证 scope 和权限地图 scope 不是一个参数

认证 scope 仍是 `t2_fawvw:fal`。VehicleOperationListService.Scope 的 getter（0x4d9d4c）返回字面值 **All**（字符串偏移 0x555361）。把认证 scope 填进地图会得到 unknown.resource。本轮权限地图采用 `?scope=All`，并保留无 scope 对照。

### 行程枚举先前解释错误

原 SDK 的 TripType 原始值构造器（0x4afb48）与 description getter（0x4af9ac）确认：0=longTerm、1=shortTerm、2=cyclic、3=unknown。原“0 是单次行程”解释不成立。UI 的“行程记录”已改成短期行程，调查则查询前三类。

### 并非所有只读动作都属于 QueryAction

查询型通常调用 loadWithErrorFunction:，但 SDK 的发动机历史/最近结果、配对最近结果、定时配置读取返回 ListenableExecutableAction，需 executeWithErrorFunction:。本轮仅对白名单中经过静态签名确认的四个**读取**方法放行；从未调用 start/stop/update/set/pair/unpair 等动作。

### Swift 调用必须遵守返回 ABI

旧 MCSafeGet 将所有 getter 都按 id 调用，BOOL/整数/浮点会被误当对象指针。现在根据运行时类型编码分别装箱，并拒绝缺失 getter、参数化方法及未经适配的结构体返回。相关 ABI 测试通过。

旧 XML 解析器仅收集元素属性，丢掉 value/unit/textId 子元素。现在同时保留信号值、单位、含义和命名空间权限 ID；空 value 不自动变为零。

调查结果改存 JSON，保留 null/未知值；每项完成即落盘，不依赖短暂 console 窗口。初版尝试把 NSNull 写入 plist 失败，已修复，最终结果以 surveyVersion=3、state=complete 的 JSON 为准。

## 5. 实现与证据

### 可复现的调查

`implementation/MinimalClient/src/MCCapabilitySurvey.m`：31 项逐车白名单，异步串行、超时、动作持有、原始响应保存；不修改车辆默认设置。采用独立的车辆 actions，调查期间不混用 UI 的当前车。

构建：`python3 implementation/MinimalClient/build.py --ipa`。

在当前已安装 PoC 上点击“深度探测”，或用开发启动环境变量 `MC_CAPABILITY_SURVEY=1`，可重跑只读调查。原始结果在设备沙盒 `Documents/capability-survey/survey.json`，响应在同目录。重复运行会更新该诊断结果。

拉取到本机受限目录后执行：

```sh
python3 analysis/summarize_capability_survey.py output/private-capability-survey-final
```

脱敏证据：

- `analysis/vehicle-capability-matrix.json`：两车模型、能力标志、服务权限、31 项结果、条数与控制实测边界。
- `analysis/vehicle-raw-signal-catalog.json`：每车原始字段 ID、textId、单位、有值与时间字段模式；不含 VIN、经纬度和传感器实际读数。
- `analysis/sdk-interface-catalog.json`：69 类 Service/Repository/ActionsImpl 的 287 个公开调用签名。包含账号/其他车型接口，**不等于 287 个可用车控功能**。
- `analysis/sdk-enum-and-query-evidence.json`：SDK 哈希、scope/TripType 定位、只读 ExecutableAction 白名单。
- `analysis/rea-carnet-sdk-evidence.json`：REA 既有完整 Mach-O 证据；本轮复用同一库及元数据，未重复无关引擎配置。

SDK SHA-256：`c9594a2256eea8438fa0bdfe6891c59bb648bbcac06180328660696e46f25798`。

原始私密现场在 `output/private-capability-survey-final/` 与调试日志，均已排除 Git，并限制本机权限。脱敏摘要不导出令牌、VIN、账号、经纬度或 IMEI。

### 修正的控制适配器

本轮静态修正了几个确定的调用错误：鸣笛/闪灯在 VehicleActionsImpl 根对象上；控制动作使用 execute 而非 query load；SPIN 保护动作缺码时直接返回提示；空调 start/stop 的首参按 NSInteger 枚举签名处理。它们仅通过编译和元数据核对，**没有实车执行验证**，不能据此宣称所有控制已完成。

验证：两车 62 项调查完整落盘，无查询崩溃；原始状态/档案/权限地图按正确区域成功；SafeGetterTests、RawXMLParserTests、codesign 深度严格校验通过。具体支持/拒绝结果见矩阵，未把预期的不支持错误伪装成测试通过的功能。

## 6. 建议接入顺序

1. **先把已成功的信息做好**：状态时间、里程、燃油/续航、门窗和锁、保养、机油相关已确认字段、行程三分类、健康提醒。探影加停车位置和室外温度。
2. **按车型显示控制**：GTI 增发动机与车窗，探影显示锁/解锁和寻车；未开通的空调/充电等不要作为共同功能。
3. **逐项验证实际控制**：以当前权限矩阵作为候选清单，在用户明确的现场操作范围内逐项验证受理、SPIN、执行结果、超时和离线；保留每车每项记录，不用按钮存在代表成功。
4. **补 GTI 的其他定位通道**：当前 MBB 不支持，但原宿主还有 `mycar/base/vehicle/v1/get-vehicle-point-info` 等静态接口候选。下一轮沿原应用真实调用取证，不能由 MBB 403 推出车辆所有定位通道都不可用。
5. **补权限受限的设置类能力**：探影围栏/超速提醒服务存在而当前副用户无权限；只在具备相应权限后继续验证定义读取与设置，不猜测绕过。
6. **其他车型/通道作为后续专题**：SDK 有电动车空调、充电和定时接口，原包还有远程泊车、数字钥匙/配对及 CEA 组件，但当前两车与本轮六框架宿主没有足够运行证据。摄像头、泊车、Car Key 不列为当前已支持功能。

本轮目标是查明可支持范围。完整密码/短信登录、身份令牌刷新和最终 UI 仍是原有待办；本轮使用现有身份会话，不宣称独立登录已经完成。

## 本轮调查版归档

`output/FAWVW-MinimalClient-PoC-dev.ipa`，Bundle ID `com.lukev.minimalclient`，大小 21838192 字节，SHA-256 `1edfef4c3fe07c770e94b63e7ec5da016884035b2608d419d1d7d3617906d347`。已覆盖现有 PoC；普通启动确认 MBB 认证成功、两车目录加载和状态回调，调查任务不会在普通启动自动重跑。最终验证记录为 `analysis/capability-verification-2026-11-17.json`。
