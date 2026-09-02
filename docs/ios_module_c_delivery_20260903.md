# 模块 C：iOS 原生层交付记录

日期：2026-09-03

## 实现状态

### Part 1：Share Extension

- 已创建 `CantingShareExtension` target，并嵌入 Runner。
- 支持从系统分享面板接收一张图片。
- 使用 Vision 完成 OCR，再进行菜名清洗、数量/份量提取和本地菜品匹配。
- 原图与 `pending_shared_meal.json` 均写入 App Group 容器。
- Flutter 主 App 读取共享 JSON 和图片 URI，进入 `/record_detail?source=share`。
- App Group 统一为 `group.com.canting.shared`。
- 重复图片、OCR 失败和未识别菜品均有降级处理。

说明：iOS 对 Share Extension 主动拉起宿主 App 有系统限制。实现会调用
`NSExtensionContext.open` 尝试跳转；系统拒绝时，识别结果仍会可靠保存，
并通过带 deep link 的本地通知让用户进入结果页。

### Part 2：Vision OCR

- `OCRService` 使用 `VNRecognizeTextRequest`。
- 默认 `recognitionLevel = .accurate`。
- 识别语言为 `zh-Hans` 和 `en-US`，启用语言纠错和常见菜名词表。
- `com.canting.app/vision` MethodChannel 提供 `recognizeText`。
- Flutter 接口为 `IOSNativeBridge.instance.recognizeText(imageBytes)`。

### Part 3：WidgetKit

- 已创建 `CantingWidget` target，并嵌入 Runner。
- 小组件支持 `.systemSmall` 和 `.systemMedium`。
- 小尺寸展示占位 sprite、活力值、活力状态和今日餐次。
- 中尺寸增加今日完成度、下一餐建议和宠物对话。
- 宠物 JSON 从 App Group `UserDefaults` 的 `pet_status_json` 读取。
- Flutter 宠物或餐次状态变化后写入 App Group，并调用
  `WidgetCenter.shared.reloadAllTimelines()`。
- 当前 sprite 是 64 x 64 纯色占位图。

## 验证结果

- `flutter analyze`：通过，无问题。
- `flutter test`：102 项全部通过。
- plist/XML、菜品 JSON、Widget asset JSON：结构校验通过。
- App Group、Sources、Resources、Embed App Extensions：静态配置检查通过。
- Windows 环境没有 Xcode/Swift SDK，无法在本机执行原生 iOS 编译。

本地自动验收：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\verify_module_c.ps1
```

日志保存在 `build/module_c_verification/latest.log`。GitHub Actions 工作流
`.github/workflows/module-c-ios.yml` 会在 macOS 上追加执行
`flutter build ios --simulator --debug`。

## 上真机前的一次性配置

1. 在 Apple Developer 后台创建 `group.com.canting.shared`。
2. 为 Runner、`CantingShareExtension`、`CantingWidget` 三个 App ID 开启该
   App Group，并重新生成 provisioning profiles。
3. 在 Xcode 的三个 target 中选择同一 Development Team。
4. 首次需要通知时，由 Flutter 调用
   `IOSNativeBridge.instance.requestNotificationPermission()`。
