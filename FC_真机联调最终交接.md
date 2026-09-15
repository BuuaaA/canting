# 04 Android 真机联调最终交接（2026-09-15）

## 结论与范围

本次要求的实际 APP → FC → 百炼 → 推荐页面链路已取得成功证据；不是独立探针、health、401 或本地候选替代验收。尚未提交或合入，07 继续等待。基线/当前 HEAD 为 `2af8eb2`，分支为 `codex/plate-v1-04-ai-recommendation`，本次结果来自其未提交工作树的开发构建。

最终真机调用：

- POST `cantingan-proxy-lutwihtgyl.cn-beijing.fcapp.run/recommend`，HTTP 200。
- FC 请求 ID：`1-6aa8f8e4-132adda2-082cc3af689f`。
- `source=ai`，`reasonCode=ai_validated`，`suggestionCount=3`。
- 实际 AppState 调用及页面检查耗时 9282ms，未启用异常暂停；未延长 25 秒共享预算。
- 页面组件及截图显示真实返回的清蒸鲈鱼、蒜蓉西兰花、杂粮饭。返回文本未由调试脚本伪造或替换。
- 手机安装包与本地构建 SHA-256 一致：`b32d544fde8e8ebc931c572e0204c74eec19d77ab14de773250b435673a24912`。

## 找到并处理的问题

1. 先前客户端把七天逐日明细重复放入 prompt，固定虚构输入实测超出 FC 的 16000 字符限制。已仅从远端请求中移除 `rolling7d.days`，保留本地逐日统计、汇总及 unknown 语义；见已有 `FC_400_限定修复交接.md`。
2. FC 脱敏分阶段日志证明 HTTPS 建连及发送在累计 22ms 完成，但等待响应头到 25027ms 超时。用户截图确认工作流节点 Qwen3.8-Flash 启用了 `enable_thinking`；用户关闭该项并发布后，同一固定虚构请求体返回 HTTP 200、3 条推荐。未更换模型、口令、Key 或提示词模板。
3. 真实 APP 已得到 `ai / ai_validated`，页面却仍显示无推荐。确定性根因是 `recommendationContextKey()` 使用 `2026-9-15`，而服务结果使用 `2026-09-15`，导致页面上下文校验拒绝结果。已仅统一推荐上下文日期为 YYYY-MM-DD；未修改其他缓存使用的 `_dayKey`、数据库或跨日/跨餐次防串结果规则。

## 本轮新增的业务修复与测试

- `lib/state/app_state.dart`：推荐上下文日期补零。
- `test/ui/recommendation_frontend_closure_test.dart`：新增月份/日期补零测试，以及真实 NextMealRecommendationService → AppState → RecommendationDetailPage 的 AI 菜品显示回归（远端返回使用虚构测试 fixture，不冒充真机验证）。
- 修复前新增页面回归确实失败：服务已是 AI，但找不到菜名；修复后通过。
- 31 项定向测试全部通过，覆盖 FC 适配器、推荐服务、AppState、详情页与跨日/跨餐次隔离。按用户要求未重复执行此前已核对的 587 项全量测试。
- `flutter analyze --no-pub`：No issues found。
- `flutter build apk --debug --no-pub --target tool/fc_app_diagnostic.dart --dart-define=CANTING_RECOMMEND_ENABLED=true --dart-define=CANTING_RECOMMEND_ENDPOINT=https://cantingan-proxy-lutwihtgyl.cn-beijing.fcapp.run`：成功。
- `git diff --check`：通过，仅有既有 LF/CRLF 提示。未回滚或覆盖此前已有业务和平台生成文件改动。

## 证据位置

证据目录：`C:/Users/gxy20/Documents/Codex/2026-09-11/app-04/artifacts/android/`

| 文件 | 内容与性质 |
| --- | --- |
| `20260915-actual-app-success.jsonl` | 从真实调试调用输出保留的白名单结果；不是完整响应正文 |
| `20260915-actual-app-http.log` | 实际 APP logcat 中提取的原始 FC HTTP 白名单行 |
| `20260915-actual-app-ai-verified.png` | 最终真实推荐页面截图，无口令输入框 |
| `20260915-final-apk-hash.json` | 真机与本地 APK 哈希及一致性结果 |
| `20260915-final-credential-cleanup.json` | `appProcessStopped=true` |
| `20260915-context-before-fix.log` | 修复前失败回归原始日志 |
| `20260915-context-targeted-tests.log` | 修复后 31 项定向测试原始日志 |
| `20260915-context-analyze.log` | 静态检查原始日志 |
| `20260915-context-build.log` | 构建原始日志 |
| `20260915-thinking-off-desktop.jsonl` | 关闭思考模式后相同固定虚构请求 HTTP 200 结果 |
| `20260915-fc-header-wait-timeout-user-provided.jsonl` | 用户提供的 FC 分阶段日志，规范化去除聊天转义 |

`20260915-actual-app-final.log` 是较早一次调试连接超时的日志，不是最终成功证据；`20260915-actual-app-ai-page.png` 是日期修复前页面仍无推荐的截图，保留用于对照，不得与 verified 截图混用。

## 凭据与运行方式

- 临时 PROXY_TEST_TOKEN 只经关闭回显的输入进入进程内存，再经本机 ADB 转发的受保护 Dart VM 服务传给 APP 开发宿主；没有写入源码、APK、文件、命令行参数、交接报告或截图。
- 本次使用 `tool/fc_app_diagnostic.dart` 启动真实 `runCantingApp`，调用真实 AppState 和真实路由/页面。开发宿主运行时提供凭据，正常正式入口默认关闭规则未改动。
- 宿主在扩展调用 finally 中清空凭据。取证后已 force-stop APP 并确认进程停止，电脑请求进程也已退出；用户数据未清除。手机上本轮临时截图已删除，工作区 verified 截图保留可用。
- 本次没有再次验收手工输入框的点击流程；它是此前入口改动。最终成功证明的是实际 APP 的运行时凭据注入、生产业务推荐路径及页面显示，而非 release APK 启用 AI。
- 用户应立即轮换已在会话中提供过的临时 PROXY_TEST_TOKEN。

## 必须保留的限制与纠正

- 这是一次真实端到端成功，不等于多网络、多机型、长时间稳定性或延迟 SLA 已验证；超时/失败仍应本地降级。
- 此前将 Android `settings get global mobile_data` 的值据为“手机未联网”的判断错误，已明确撤回；之后系统连接信息确认存在 VALIDATED 蜂窝网络。临时开启的 Wi-Fi 已恢复为此前关闭状态，未修改移动数据设置。
- 本轮有一次实际页面返回 `remote_unavailable`，当时未取得对应 HTTP 诊断；后续异常调试捕获了可恢复的 SocketException，且同次调用最终获得 AI 结果。因此不能把此前所有失败都归结为某一个网络原因，也不能声称没有瞬态失败。
- 原有 HTTP 诊断辅助函数会对成功 JSON 也填写 `errorType=json_error` / `errorMessage=json error response`。最终原始 HTTP 日志保留了这一误标；HTTP 200、AI schema 校验和页面证据才是本次成功判断依据。本轮未为该纯诊断标签额外扩大改动/重新构建。
- 工作区本地调试桥与隔离 Flask/WebSocket 依赖仅用于排错，不属于 APP 依赖。FC 的脱敏诊断版由用户在控制台部署，不代表仓库已自动管理该部署。
- 正式发布、协调复核合入及 07 均未执行。交付后应先复核当前 diff 和证据，再按用户后续指示推进。
