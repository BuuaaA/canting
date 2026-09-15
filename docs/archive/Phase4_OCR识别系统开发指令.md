# Phase 4（OCR 识别系统）开发指令 · 2026-09-04 白天版

> 用法：白天模式，单个对话执行，你可随时查看进度
> 前置状态：Phase 1\~3 全部完成，256 个测试全过，模拟器冒烟已通过
> 关联模块：模块 12（Android 分享+OCR）、模块 14（APP 内拍照识别）

***

## 一、重大发现：MVP 已实现了大部分，模块文档的假设过时了

原模块 12 文档假设「从零搭建 PaddleOCR + 后台静默处理」，但磁盘现状是（已逐文件核实）：

| 组件      | 现状      | 文件                                                                                             |
| ------- | ------- | ---------------------------------------------------------------------------------------------- |
| 分享接收    | ✅ 完整可用  | `ShareActivity.kt`（收图→复制到缓存→拉起主APP）                                                            |
| OCR 引擎  | ✅ 完整可用  | `OCRService.kt`（**ML Kit 中文识别**，端上离线，免费）                                                       |
| 菜名提取    | ✅ 已有    | `DishNameExtractor.kt`（过滤价格/电话/配送费，提取菜名+数量+商家）                                                 |
| 原生桥接    | ✅ 完整可用  | `MainActivity.kt` 三个 channel（share/ocr/pet）+ `lib/platform/android_native_bridge.dart`         |
| 分享识别状态机 | ✅ 完整可用  | `AppState.startSharedRecognition / completeSharedRecognition / failSharedRecognition`（昨晚重建时保留） |
| 识别→记录链路 | ✅ 已通    | `main.dart` 收分享图 → 识别 → `record_detail_page`（source='ocr'）                                     |
| iOS 侧   | ✅ 大部分已有 | Vision OCR + 分享扩展已实现（无法在 Windows 验证，继续搁置）                                                      |

## 二、三个技术决策（基于现状的最优解，不同意可否决重写）

1. **保留 ML Kit，不换 PaddleOCR**。理由：ML Kit 端上离线、免费、已集成且跑通过；换 PaddleOCR 要重写 OCRService + 打包 10MB 模型 + 引入新原生依赖，收益仅是"国产引擎"名分。模块文档写 PaddleOCR 时还不知道 ML Kit 已在。
2. **保留「分享拉起 APP」流程，不做后台静默处理**。原文档设想"后台识别→存库→发通知"，但现有设计（拉起 APP→用户看到识别结果→可修正→保存）**更符合"识别结果可手动修正"的产品要求**，且省掉双进程写库的全部复杂度。
3. **通知改为「保存成功确认」**。用户就在屏幕前看着识别结果，失败时 APP 内已有错误提示；只在 OCR 来源的记录**保存成功后**发一条确认通知（含菜名+宠物台词，遵守设置页开关）。这是对模块 13 文档"识别成功/失败通知"的简化落地。

## 三、实际剩余工作（比原估 8h 少一半）

```
✅ 已有：分享→OCR→提取→识别页→保存（整条链路）
⬜ 任务1：全链路回归——昨晚重构后这条链路没验证过，先修通
⬜ 任务2：APP 内拍照/相册识别（模块14，真缺：无 image_picker 依赖）
⬜ 任务3：OCR 保存成功通知（B3 遗留）
⬜ 任务4：DishNameExtractor 单元测试加固
```

***

## 四、对话指令（复制全文发给 TraeCode）

```
【白天开发任务】「餐盘」APP V1.0 · Phase 4：OCR 识别系统收尾

项目目录：d:\dev\canting（Flutter + Provider + sqflite，Android 优先）
背景：Phase 1~3 已完成，256 个测试全过。OCR 分享链路 MVP 时期已基本实现，本次是收尾而非从零开发。
要求：按顺序完成 4 个任务。每个任务完成后跑 flutter analyze + flutter test 再进下一个。全程不要向我提问，拿不准自行选合理默认并在总结里说明。

## 先读这些（动手前必读）
- dev-docs/module-14-in-app-ocr.md（模块14需求）
- lib/main.dart（分享图接收：_handleSharedImage → appState.startSharedRecognition）
- lib/state/app_state.dart 883-920 行（sharedRecognition 状态机）
- lib/platform/android_native_bridge.dart（recognizeImage / getOcrStatus）
- android/.../ShareActivity.kt、OCRService.kt、MainActivity.kt、DishNameExtractor.kt（原生侧，已完整实现）
- lib/ui/record/record_detail_page.dart（isSharedRecognition → source='ocr' 的保存路径）

## 三个已定的技术决策（不要偏离）
1. OCR 引擎用现有 ML Kit，禁止引入 PaddleOCR / paddle-lite 任何依赖
2. 分享流程保持现有"拉起 APP→识别页→用户确认保存"，禁止改成后台静默处理
3. 通知只在 OCR 来源记录保存成功后发确认通知（菜名+宠物台词，走 NotificationService.showRecognitionSuccess，遵守 recognitionEnabled 开关）；识别失败不发通知（APP 内已有错误提示）

## 任务1：分享→OCR→保存 全链路回归修复
昨晚 record_detail_page 去掉了 Mock 默认菜、改用 buildMealRecord，分享识别链路可能受影响。
1. 通读整条链路：ShareActivity → main.dart → AppState 状态机 → record_detail_page 保存
2. 确认识别出的菜名走 DishMatcher 匹配（buildMealRecord 内部已做，含自定义菜品优先）而不是只信 Kotlin 端提取结果
3. 修复发现的断点；Kotlin 端（ShareActivity/OCRService/MainActivity/DishNameExtractor）原则上不改，确需改动要在总结里单独说明原因
4. 为 Dart 侧链路补测试（如：识别结果进 draft → 保存 → source='ocr' 落库）

## 任务2：模块14 APP 内拍照/相册识别
1. pubspec 添加 image_picker（用当前稳定版）
2. 新建 lib/ui/ocr/in_app_ocr_page.dart 或复用现有入口结构：
   - 首页 FAB 弹层改为三项：拍照识别 / 相册选择 / 手动添加（现在"截图识别"是占位 Snackbar，替换掉）
   - 拍照：image_picker camera；相册：image_picker gallery
3. 关键适配：MainActivity.recognizeImage 只接受 content:// 且 authority==com.canting.fileprovider 的 URI，而 image_picker 返回的是文件路径。解决：参照 ShareActivity.copyToAppCache 的做法，把选到的图片复制到 cacheDir/shared_images/ 再用 FileProvider.getUriForFile 包装，然后走 AppState.startSharedRecognition 同一条识别管线（复用，不要新开管线）
4. 识别结果页复用现有 record_detail_page 流程（source 同样记 'ocr'）
5. 错误处理按模块14文档：取图失败/识别为空/超时，均有友好提示 + 手动添加入口
6. Widget 测试：FAB 弹层三项、各错误分支文案

## 任务3：OCR 保存成功通知
在保存成功路径上（source=='ocr' 且 notificationService.recognitionEnabled==true 时）调用 showRecognitionSuccess(菜名, 宠物台词)。台词复用 pet 的当日对话逻辑，不要新造文案库。可测部分写单元测试。

## 任务4：DishNameExtractor 单元测试加固
新建 android/app/src/test/java/com/canting/canting/DishNameExtractorTest.kt（纯 JVM 测试，不依赖 Android 框架）：
- 覆盖：菜名+数量提取、价格/电话/时间/订单号过滤、excludedTerms 过滤、商家识别、括号规格后缀清理（如"黄焖鸡米饭（大份）"→菜名干净）
- 运行：cd android && gradlew.bat testDebugUnitTest（Windows）
- 若 gradle 测试环境有问题（网络/版本），记录原因，把用例转成 E2E 手册里的验证点，不要死磕

## 质量门槛
1. 每任务：flutter analyze 零问题 + flutter test 全量通过（旧测试禁删禁跳禁弱化）
2. 允许 flutter run 到模拟器验证（白天模式），但注意 flutter 命令互斥，跑完退出再跑测试
3. 改 pubspec.yaml / main.dart / app_state.dart 前先重读磁盘最新版
4. 禁止：git 命令（完成后我来确认提交）、修改 ios/ 目录（无法验证）、删除 PetWidget 相关文件（V1.1 遗产，别动）
5. UI 文案中文，风格与现有一致

## 最终总结
输出：每个任务的改动文件清单 / 新增测试数 / 任务1发现并修复的链路断点（如有）/ 遗留问题 / analyze+test 结果 / Kotlin 侧是否改动及原因。
现在开始任务1。
```

***

## 五、E2E 验证手册（模拟器上验证分享识别，TraeCode 或我都能跑）

**1. 生成合成订单截图**（Windows 上渲染好文字再推给模拟器，不存在字体问题）：

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(720,1280)
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font("Microsoft YaHei",28)
$lines = @("张记黄焖鸡(美团外卖旗舰店)","黄焖鸡米饭（大份） x1","¥22.0","蒜蓉西兰花 x1","¥12.0","米饭 x2","¥4.0","配送费 ¥3.0","订单号 20260904123456","合计 ¥41.0")
$y=80; foreach($l in $lines){ $g.DrawString($l,$font,[System.Drawing.Brushes]::Black,40,$y); $y+=70 }
$g.Dispose(); $bmp.Save("d:\dev\canting\test_order.png",[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
```

**2. 推到模拟器并触发系统分享**（两种方式，先试 A 不行再 B）：

```powershell
adb push d:\dev\canting\test_order.png /sdcard/DCIM/test_order.png

# 方式A：走 MediaStore 索引后用 content URI 分享
adb shell content call --uri content://media/ --method scan_volume --arg external_primary
adb shell content query --uri content://media/external/images/media --projection _id,_data --where "_data LIKE '%test_order%'"
# 拿到 _id 后：
adb shell am start -n com.canting.canting/.ShareActivity -a android.intent.action.SEND -t image/png --eu android.intent.extra.STream content://media/external/images/media/<id> --f 0x1

# 方式B：MediaStore 不可用时，直接用文件 URI（模拟器 shell 权限通常够）
adb shell am start -n com.canting.canting/.ShareActivity -a android.intent.action.SEND -t image/png --eu android.intent.extra.STREAM file:///sdcard/DCIM/test_order.png
```

（注意方式A的 `extra.STream` 若大小写敏感写成 `android.intent.extra.STREAM`）

**3. 预期现象**：餐盘 APP 被拉起 → 识别页出现「黄焖鸡米饭、蒜蓉西兰花」等 → 保存 → 首页出现记录、收到确认通知。

**4. 实拍验证（最终验收）**：合成截图过了之后，用真机拍一张真实外卖订单截图分享一遍——这个只能你来，模拟器上没有真实外卖 APP。

***

## 六、白天小项指令（Phase 4 完成后另开对话，串行不并行）

```
【白天小任务】「餐盘」APP V1.0 · 遗留小项清尾

项目：d:\dev\canting。Phase 1~4 已完成。按顺序做以下 4 项，每项完成跑 analyze+test：

1. 外卖平台持久化 + 设置页 UI：
   - pubspec 加 shared_preferences
   - 实现 DeliveryPlatformConfigStore（lib/services/delivery_jump_service.dart 已留好接口：loadOrderedPlatformIds / saveOrderedPlatformIds）
   - 设置页新增「外卖平台」分组：开关 + 拖动排序（简单实现：上移/下移按钮即可，不必做拖拽）
   - DeliveryJumpService 接入：跳转时读用户配置
2. 通知开关落盘：recognitionEnabled / mealReminder / gapReminder 统一走 shared_preferences 持久化，启动时恢复
3. 记录页备注编辑：meal_records.note 列和 getNote() 已有，记录详情页补备注展示与编辑 UI
4. 活力值口径抽查：审计「删除回退规则」与「3天重算」两套逻辑在边界场景（当天删除全部记录、跨日）是否一致，不一致给出修复方案并实施，补测试

要求：全程不提问；旧测试禁删禁跳禁弱化；完成后输出改动清单 + analyze/test 结果。现在开始。
```

> 为什么串行：两个任务都要改 pubspec.yaml，白天并行会撞文件。Phase 4 先跑（约 3-4h），完了再跑小项（约 1-2h）。

***

## 七、完成后的状态

Phase 4 + 小项全部完成后，V1.0 就只剩：

- **真机验收**：京东外卖跳转、真实订单截图识别、通知实际到达——需要你的安卓真机

- **模块 16 联调**：全链路回归 + 打磨（约 2h）

- **iOS（模块 11）**：代码大部分已有，需要 Mac 环境构建验证

