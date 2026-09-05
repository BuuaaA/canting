# 餐盘 Canting · 0.9.0-beta

Android 优先、离线优先的饮食记录与宠物陪伴 App。用户主动分享订单截图或选择/拍摄图片，在本地识别、确认并保存；通过最近7天与28天的饮食结构获得温和的下一餐建议。

## 当前功能

- 本地中文 OCR、候选确认、未知项手动归类，纠正结果在本机复用。
- SQLite 持久化餐食、历史、用户设置和宠物状态；可编辑、删除与导出。
- 确定性膳食规则、7/28天记录覆盖说明和推荐安全过滤；不精确计算热量，不替代医疗建议。
- 猫/狗/仓鼠伙伴、成长及动画，桌面 Widget；本版新增橘猫餐盘 App 图标。
- Widget 快照标注记录日期；刷新时发现跨日或时区偏移变化，会隐藏旧数值并提示打开 App 更新。

## 安装前请读

这是测试版，不代表 V1 正式封版或真机验收完成。GitHub Release 提供 arm64 主 APK 和 universal 备用 APK；ABI 不确定时先核对设备。两包 versionCode 均为5003，包名 com.canting.canting，沿用旧 beta 的 Android Debug 测试签名。

手机已有重要数据时，**先暂停覆盖升级**：当前有 JSON 导出，但没有经过验证的完整导入/恢复流程，系统自动备份也已禁用。由开发协助验证备份恢复后再升级，不卸载、不清数据、不强制降级。相同包名/签名与更高版本码只证明静态相容条件。

从 [GitHub Releases](https://github.com/BuuaaA/canting/releases) 获取最终审核后的测试包，先阅读随包 START-HERE.md、package-info.md、known-limitations.md，并核对 SHA256SUMS.txt。

## 隐私与测试边界

release Manifest 无 INTERNET / ACCESS_NETWORK_STATE；无遥测和云同步。截图只用于本次识别；临时副本处理及系统备份行为仍需设备核验。反馈前请去除姓名、地址、电话等信息。

小米安装、桌面图标、Widget刷新/缩放/重启、旧包真实升级、原生首次离线/无GMS OCR：not_run。自动化结果不能替代真机证据。真实截图、独立留出和危险场景仍需按 dev-docs/p5-device-checklist.md 补验。

## 开发与证据

Flutter / Dart + Provider + SQLite；Android 原生内置中文 ML Kit。沿用现有依赖，不新增运行时依赖。先读 AGENTS.md。

设置新的 CANTING_P6A_RUN_ID 后，从仓库根目录依次运行：

```powershell
$env:CANTING_P6A_RUN_ID='my-new-run'
python scripts/p6a/run.py analyze
python scripts/p6a/run.py full
python scripts/p6a/run.py kotlin
python scripts/p6a/run.py universal
python scripts/p6a/run.py split
python scripts/p6a/validate_configuration.py
```

工具使用本机已安装的 Flutter、Android SDK 和 JBR；换机器先配置工具路径与依赖缓存，不自动升级依赖。Gradle使用离线模式，避免并行构建。构建前确保 android/local.properties 中 flutter.versionCode/Name 与 pubspec.yaml 一致；实际身份由 APK 核验。

P6-A报告：dev-docs/p6a-test-package-report.md。精简说明：dev-docs/ponytail-simplification-report.md。最终beta交接：dev-docs/beta-0.9.0-review-handoff.md。

宠物美术更新延后 V1.1。后续先完成 Owner 小米验证，再按既定路线组织5–10人、7个自然日封闭试用；正式签名和V1发布另行验收。
