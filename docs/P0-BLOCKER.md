# P0 状态：MBB 阻塞已解决，完整登录仍待完成

更新：2026-11-16。Codex 接手后通过原宿主定点运行时插桩取得真实参数，并已在独立最小宿主通过 MBB 认证、两车列表和两车状态读取。

**完整解决记录与复现方式见 [P0-RESOLUTION.md](P0-RESOLUTION.md)。**

## 本轮解决

- 实际认证令牌是 `typ=identity`，此前导入的 `typ=AT` 并非该实参。
- 原宿主 SDK 认证传入的是运行时 UUID 注册 clientID，JWT audience 不能等同该标识。
- AppInfo、scope、FAL、MAL、brand 的多处占位/推断值已由真实运行参数纠正。
- 查询动作必须调用 `loadWithErrorFunction:`，不是认证动作的 `executeWithErrorFunction:`；修复了认证成功后的查询崩溃。
- 选车改为等待异步绑定成功再读状态。
- 两种模式均实测成功：导入真实 clientID；不导入 clientID。两辆车均返回可解析状态，没有发送物理控制指令。

## 当前真正未完成的工作

1. 独立客户端通过密码/短信取得 identity token 及刷新，仍待协议取证；本轮使用本机导入身份令牌。
2. 原宿主非空 pin 集合尚未完整复刻，当前 PoC 使用系统 TLS 校验，不应声称 pinning 与原宿主等价。
3. 左上角车型下拉单选菜单、每车能力 UI 和实际控制功能仍待实现/验收。

## 后续不要继续使用的旧假设

- 六组 brand 失败不等于排除了 brand。
- `missingAccessRights` 不能单独证明请求中其他参数全部正确。
- `VWGMBB01CNLIV1` 来自 JWT audience，不是已证实的 SDK 注册 clientID。
- `openid profile mbb` 是 AT 中观察到的 scope，不是原宿主 MbbChinaStage 实参；实际为 `t2_fawvw:fal`。
- 读取/复用已有身份令牌不等于完整密码登录成功。

原始研究上下文仍见 `P0-EVIDENCE.md`；其中早期推断以 `P0-RESOLUTION.md` 和 `analysis/p0-runtime-resolution.json` 的实际运行证据为准。
