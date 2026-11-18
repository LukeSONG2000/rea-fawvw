# GTI：信息查询详情与定位排查

日期：2026-11-17。用户已明确后续只研究 GTI。本页不把其他车型的查询结果用于 GTI 结论。

## 已查询到的信息及实例

以下主车况快照时间为北京时间 **2026-11-17 08:45:56**。字段可能各自有不同采集时间，不属于实时遥测。

| 内容 | 本次实例 | 解释/限制 |
|---|---|---|
| 总里程 | 11,634 km | 后端已存快照 |
| 燃油百分比 | 90% | 非剩余汽油升数 |
| 燃油续航 | 370 km | 车辆上报估计值 |
| 四窗开度 | 本次均 0% | 原始 VSR 百分比；不只是 SDK 开闭枚举 |
| 车身状态 | 车门锁定/关闭、尾门、机盖、窗、驻车灯、驻车制动分量 | 每个分量需按枚举/textId 解释，不能将缺失分量视为关闭 |
| 机油相关百分比 | oil.level=75% | 与 fuel.level=90% 不同；不直接解释为油箱燃油量 |
| 机油相关其他字段 | 0x0204040001=1.0 L | 确切含义未完成确认，不能用作剩余汽油升数 |
| 换油剩余距离/天数 | −4,000 km / −342 天 | 服务端原值，不自动当作已核实的保养结论 |
| 检查保养剩余距离/天数 | −9,000 km / −342 天 | 同上 |
| 健康提醒 | 查询成功，warnings=[] | 当前快照无有效提醒；原始报告含历史 textId 不等于当前告警 |
| 发动机操作历史 | 查询成功，actions=[] | 当前接口返回 0 条，不保证覆盖所有设备和所有时间段 |
| 最近发动机操作结果 | operation=5、status=8 | 原始枚举已读通，尚未映射中文，不擅自解释成功/失败 |
| 防盗通知历史 | 查询成功，0 条 | 不等于已经验证实时推送 |
| 手机配对状态 | 状态接口回调 nil；最近结果接口可返回 | 不能据此判定已配对，也不能直接等同数字钥匙/Apple Car Key |
| 用户角色与服务权限 | PRIMARY_USER，HG_3 | 仍需逐服务看 operationList；HG_3 不等于所有服务都有权限 |
| 车辆档案 | 2026 年款；发动机 DTJ；变速箱 WNL；MMI 7UY；颜色编码 L0K1 | SDK CarportData；原始档案另有通信模块信息 |

本次完整 VSR 返回 **56 个 field，51 个有 value**。其中包含状态、里程、区间、时间、告警和占位字段，不等于 56 个有效传感器。

### 行程查询

SDK 枚举经反汇编核对：0=长期、1=短期、2=周期。不是所有短期条目都能认作一次完整驾驶，应保留原 reportReason。

| 类别 | 本次返回数 | 实例 |
|---|---:|---|
| 短期 | 41 | 2026-11-10 19:33:54 结束；27 km；2,520 秒（42 分钟）；均速 39 km/h；平均油耗数值 11.9；起始 11,238 km，结束累计 11,265 km；reportReason=clamp15off |
| 长期 | 1 | 2026-11-17 08:45:41 上报；累计 1,632 km；197,280 秒（54 小时 48 分钟）；均速 30 km/h；平均油耗数值 13.0 |
| 周期 | 5 | 一条为 78 km；9,900 秒（2 小时 45 分钟）；均速 28 km/h；平均油耗数值 12.6 |

平均油耗在现有 PoC 中按 L/100 km 展示；返回模型仅提供 DoubleObject 数值，本轮尚未进一步取证单位来源，因此保留单位核对待办。记录可能由用户重置、点火关闭等不同原因生成，不假定每项 mileage 都等于 end−start 的精确算术差。

电耗、能量回收、零排放里程等模型字段本次为空。数字胎压、室外温度和经过确认的剩余汽油升数，本次均未取到。

### 取证文件

- 本机私密原始结果：`output/private-capability-survey-final/survey.json` 中 modelName 含 GTI 的记录。
- 原始状态：同目录 `vehicle-1-statusReport.txt`；只适用于本次文件索引，后续不依赖固定序号选车。
- 脱敏字段和能力目录：`analysis/vehicle-capability-matrix.json`、`analysis/vehicle-raw-signal-catalog.json`。

## 定位核查结果（2026-11-17）

### 三个环节须分开判断

1. **坐标获取已证实可用**：二开重签版实际使用 MOSC 通道，POST `https://api-c-oneway.mosc.faw-vw.com/vw-digitalkey/api/device-oem/sdk/vehicle/v2/getLastGnss`。HTTP 200、业务 code=0，data 返回 latitude、longitude、speed、course、updateTime、vehicleId。本接口响应为 JSON，不能沿用早期“MOSC 所有接口均密文、放弃直连”的概括。
2. **地图车辆标记与响应一致**：对 MoscCarnetCarFinderViewController 返回的 VehicleAnnotation 读取坐标，与该次 GNSS 响应比较，距离为 0.0 米。比较的是车辆专用标记，不是手机 CoreLocation 蓝点。经纬度、真实地址、车辆标识和凭据只保存在本机受限目录，不写入共享报告。
3. **地址解析失败已证实**：高德 POST `/v3/geocode/regeo` 返回 HTTP 200，但业务 status=0、info=INVALID_USER_SCODE、infocode=10008，没有 formatted_address。已捕获 6 次相同结果，NSURLSessionTaskMetrics 均为 networkLoad=true、localCache=false。问题在转地名的安全校验环节；重签身份与原高德配置不匹配是待核对的解释，尚未通过配置对照证明具体哪一项不匹配。

因此，用户关于“能获取坐标，但无法映射地名”的判断已有运行时证据支持。地名失败与车辆坐标查询失败不是同一件事。后续独立客户端应分别显示位置、位置采集时间和地址解析状态；地址不可用时保留地图标记和经纬度，不把整个定位页判为失败。

### 本地缓存与服务端最后位置

- 首次捕获 17:21:16—17:21:52 的五次 GNSS 响应；再次在 **17:28:18—17:28:44** 对坐标 POST 强制使用 ReloadIgnoringLocalCacheData 后，仍收到四次 HTTP 200/code=0，且与地图车辆标记一致。
- 这些响应中的车辆 updateTime 都为 **2026-11-17 16:45:57 +08:00**，即服务端返回的最后定位记录时间没有随刷新推进。不能将发出请求、HTTP 200、手机定位或地图刷新时间当作车辆实时采集时间。
- 独立临时 NSURLSession（无 URLCache）确实发出了网络请求，但原样重放被业务 code=16010011 /“请勿重复提交”拒绝，因此这次重放不能作为成功获取坐标的证明，也不能直接当作独立客户端调用已通。最终改为对原生请求增加 task metrics 观察，不重放请求；结果见下方最终核验。即使本地缓存被排除，也不能声称已经排除服务端存储/缓存，或已经验证车端刚刚更新。

### 最终缓存核验：原生成功请求的网络指标

**17:33:41、17:33:46** 的两次原生 getLastGnss 请求均取得：

- cachePolicy=1（ReloadIgnoringLocalCacheData）；HTTP 200，业务 code=0。
- NSURLSessionTaskMetrics：**networkLoad=true、localCache=false**。
- 响应含车辆经纬度，地图车辆专用标记与返回坐标距离 **0.0 米**。
- 车辆 updateTime 同为 **16:45:57**；相对本次请求已约 48 分钟。

**可排除本轮只是靠手机 URLCache 中旧坐标维持正确地图。** 当前原生链路确实通过网络拿到了服务端保存的位置；标记坐标与该响应一致。仍未证明“车端刚刚重新定位”或“实时追踪”，服务端最后记录未更新的原因尚未确认。HTTP 缓存网络未命中也不能排除服务器内部保存/复用最后位置。

最终采集末尾有一条请求在复制证据时尚未完成；只以上述两条具备成功响应和完整指标的请求作为结论依据。取证补丁只增加该原生任务的 metrics delegate，未改变其会话、URL、签名、认证或请求正文，也不再重放请求。

### MBB 与 MOSC 是不同通道

GTI 的 CarNetLib LastParkingPositionFeature 为空；SDK 返回 featureNotAvailable。按实际 HomeRegion `mal-3a.prd.cn.dp.vwg-connect.cn/api` 请求 `/bs/cf/v1/vehicles/{VIN}/position`，返回 HTTP 403 / `mbbc.rolesandrights.unknownService`，当前车辆找不到 carfinder_v1 服务。operationList?scope=All 也没有该服务；当前角色为 PRIMARY_USER/HG_3。

这仅说明当前 MBB 的旧 carfinder_v1 服务不可用，**不能推导 GTI 不能定位**。本轮已找到可用的 MOSC getLastGnss 通道，最小客户端下一步应研究其认证、车辆绑定、请求签名和刷新生命周期，不应继续只围绕 MBB CF 接口排查。

### 其他已排除的误判

- `GET /mycar/base/vehicle/v1/get-vehicle-point-info` HTTP 200/SUCCEED，但 data 是 CNS、CNS3.0_GP_SOP3、ODP 等设备/车型路由资料，没有经纬度，不能当作坐标接口。
- `carfinder/v1/vehicle-switch-status` HTTP 200/SUCCEED，locationStatus=true、onlineServiceStatus=false，附带移动车联网数据连接关闭提示。这是后端提示，不是已独立确认的实车设置，也不足以解释本次已成功返回的 GNSS 坐标。
- 真正官方 `com.fawvw.aftermarket` 444.28.0 已通过设备全量应用清单与地图截图确认存在并能显示车辆位置、位置更新时间和距离。devicectl 默认仅列开发应用；官方容器不可读不表示官方未安装。系统日志未提供官方坐标 HTTP 明文，不把二开版流量冒充官方流量。本轮未重签或修改官方版。

### 复现与证据

- 探针源码：`implementation/LocationProbe/GTILocationProbe.m`；受控覆盖安装于 `com.lukev.aftermarket`，不新增副本。
- 本地私密捕获：`output/private-gti-location/cache-check/`、`cache-check-v2/`、`cache-check-v3/`、`cache-check-v4/`；目录 0700，文件 0600，Git 忽略。
- 重放被拒的脱敏记录：`analysis/gti-location-replay-check.json`；不作为坐标成功响应的网络证明。
- 脱敏结果：`analysis/gti-location-cache-verification.json`；通过 `python3 analysis/summarize_gti_location.py <私密捕获目录> --output <脱敏结果>` 重建。导出时不含请求头、完整 URL 查询、坐标、地址或车辆标识。
- 官方版脱敏观察：`analysis/gti-official-location-observation.json`。
- 仅查询定位和被动观察原生页面网络；本轮未由探针调用锁车、解锁、鸣笛、闪灯、启动等物理车控。
