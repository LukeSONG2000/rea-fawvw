# P0 MBB 阻塞解决记录

日期：2026-11-16。结论：**MBB 认证、两车列表、逐车绑定和状态读取已在独立最小宿主中通过真机验证。** 完整密码登录与令牌刷新尚未通过，不能据此宣称整个独立客户端已完成。

## 原因与取证

没有继续猜 brand，也没有把 JWT audience 当作注册 clientID。复用已被用户确认可运行的开发重签版，在同一 `com.lukev.aftermarket` 中覆盖加入定点运行时探针，不新增该开发版副本。

探针源码：`implementation/RuntimeProbe/P0RuntimeProbe.m`。它截取 SDK AppInfo、MbbChinaStage 构造、useMbbStage 以及认证入口的实际实参；另读取 VWPCHybridMotion 的本地状态。没有触发物理车辆操作。未依赖 LLDB attach、证书解密或全量抓包。

原宿主实际调用 `authenticateWithClientID:identityToken:successFunction:`；其参数中的注册 clientID 为 UUID 形态，**不是**旧文档由 AT audience 推断出的 `VWGMBB01CNLIV1`。后者没有被实验证明为正确注册参数。

原宿主实际传入的令牌为 JWT，`typ=identity`、`type=identity`，不是此前导入的 `typ=AT` Access Token。探针在 SDK 认证入口捕获，因此是调用实参证据，不只是根据方法名称推测。

| 参数 | 实际运行值 | 原 PoC 值 |
|---|---|---|
| AppInfo.appName | BootstrapApp | OneApp |
| AppInfo.appVersion | 1.0 | 444 |
| AppInfo.appId | com.tima.aftermarket | TODO-RUNTIME |
| AppInfo.clientName | Maton | fawvw |
| AppInfo.clientBrand / stage.brand | VW | fawvw |
| country | CN | CN |
| scope | t2_fawvw:fal | openid profile mbb |
| authenticationServer | https://mbboauth-1d.prd.cn.vwg-connect.cn | 相同 |
| falServer | https://msg.audi-connect.cn/fs-car | https://fal-3a.prd.cn.dp.vwg-connect.cn |
| malServer | https://mal-1a.prd.cn.vwg-connect.cn/api | https://mal-3a.prd.cn.dp.vwg-connect.cn |

因此，六组 brand 候选返回相同错误，不能推出“brand 无关”，更不能排除其他错误配置。旧文档按字符串长度推断的若干“已证实参数”已被本次真实调用推翻。由于多个参数同时纠正，本轮没有做单变量对照，不将失败全部归因于 token 一项。

脱敏运行时证据：`analysis/p0-runtime-resolution.json`。原始身份令牌和注册标识留在本机受限目录，未放入文档/公开证据，也未硬编码到源码。

## 同时修正的适配错误

1. 查询动作与认证动作协议不同。`ExecutableAction` 使用 `executeWithErrorFunction:`；`QueryAction` 使用 **`loadWithErrorFunction:`**。原 PoC 在认证成功后对 vehicleVins 返回的 QueryAction 错发 execute，触发 unrecognized selector 和进程退出。车辆列表、选车、状态三处已按协议修正；返回类型按元数据统一为 void。
2. 原选车方法异步发起后即返回 YES，不能表示已选中。新增 `selectVehicleWithVIN:completion:`，等待绑定完成后再查询状态；切换开始清空旧 vehicleActions，并以 pendingVIN 拒绝过期回调。
3. 移除自动遍历 brand 的逻辑和固定 audience clientID。诊断时可从本机偏好读取真实注册标识；没有该键时走 SDK 的 `authenticateWithIdentityToken:accountFunction:` 路径。
4. `MCReadonlyVerification` 提供仅在环境变量 `MC_P0_AUTORUN=1` 时执行的一次只读验收，写入结构化结果；普通启动不自动读取身份令牌或发起认证。
5. 状态结果解析时间戳、里程、油量和续航等已知属性，记录真实状态对象及字段，不再只显示对象地址。日志摘要不输出 VIN 数组和令牌。

## 真机验证

设备为当前已配对 iPhone Air。保持 zcode 已建立的 PoC 标识 `com.lukev.minimalclient`，均覆盖安装现有 PoC，没有新建第三个研究版标识。

| 场景 | MBB 认证 | 车辆列表 | 逐车绑定 | 状态返回 |
|---|---|---|---|---|
| 导入原宿主实际 identity token + 注册 clientID | 成功 | 2 辆 | 2/2 成功 | 2/2 成功 |
| 只导入同一 identity token，移除 imported.clientID | 成功 | 2 辆 | 2/2 成功 | 2/2 成功 |

第二次测试也核对了设备偏好中不存在 imported.clientID。它证明代码可以不显式导入该标识完成认证；**没有单独追踪注册网络交换或清除 SDK 所有可能缓存**，不夸大为完全干净设备上的全新注册验收。

两辆车均返回 `CarNetLib.VehicleStatus`，可解析各自状态时间、里程、油量与续航，返回值不同。它们可能是后端存储的车辆快照，不代表强制唤醒车辆取得最新实时数据。整个测试没有开锁、上锁、启动、鸣笛、闪灯等物理操作。

构建：`python3 implementation/MinimalClient/build.py --ipa`。

验证启动：

```sh
xcrun devicectl device process launch --device <设备UDID> --terminate-existing \
  --environment-variables '{"MC_P0_AUTORUN":"1"}' --console com.lukev.minimalclient
```

先在 PoC 的本机受限偏好中准备 `imported.idToken`（键名沿用历史，值必须是本次实际捕获的 identity token）。可选 `imported.clientID`；缺省时 SDK 自行走认证流程。不要把令牌写在命令行、文档或 Git。

结构化结果位于设备沙盒 `Documents/p0-readonly-result.plist`。正确验收应同时检查 authenticated、vehicleCount、每辆车 selected/statusReceived，不应只看 stage=complete。

本机原始验证结果和日志在 `output/private-p0-probe-latest/`、`output/p0-query-verify.log`、`output/p0-fresh-client-verify.log`，仅用于本机核对，均不入 Git。敏感目录权限已收紧；`.gitignore` 新增了探针凭据及诊断重签副本的排除规则。

最终本轮 IPA：`output/FAWVW-MinimalClient-PoC-dev.ipa`。

- 大小：21656192 字节。
- SHA-256：`3e562ffd132a0c60fe139b1cc10e0fe3500e03561aae2a75fcda2cbbab6d5369`。
- 6 framework 白名单、自研主程序；没有复制原 OneApp 主程序。
- codesign 深度严格校验、真机覆盖安装、两种输入模式的只读链路通过；Git diff --check 通过。

## 仍需完成

1. **宿主网关完整登录**：账号密码/短信获得 identity token 的请求、响应解密及刷新，仍不能用会话导入代替。下一步沿原宿主“网关响应解码→身份模型→SDK认证实参”取证；不把 AT 当 identity，不根据空字段猜 token 类型。
2. **生产 pin 集合对齐**：原宿主的七参数 stage 构造收到非空 pins 数组；本轮探针仅记录其类型，PoC 使用六参数工厂与系统 TLS 校验，没有完整复刻原 pin 集合。不能宣称与原宿主 pinning 等价。后续定向补采真实集合，无需关闭系统 TLS 校验。
3. **P1/P2 产品实现**：左上角按 VIN 单选的车型下拉菜单、车型/车牌区分、每车能力与状态 UI、实际控制指令逐项验收。
4. **诊断收尾**：`com.lukev.aftermarket` 当前仍为带本机探针的过渡版，原始稳定归档 IPA 未改。最终发布前移除探针和诊断凭据；PoC 的凭据不包含在 IPA 内。当前这是研究安装，不是最终用户版本。

MBB 阻塞已解决；全新登录、刷新和正式最小产品尚未完成。
