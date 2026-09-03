# 模块 11：iOS 分享扩展 + Vision OCR

**预估工时**：4h
**依赖**：模块 01, 02
**优先级**：P0

## 功能描述

iOS 端的分享扩展，用户在外卖 APP 截图后，通过系统分享面板选择「餐盘」，后台自动识别菜品并存入数据库，完成后发送本地通知。

## 技术架构

- Share Extension（iOS 原生，Swift）
- Vision 框架（系统自带 OCR）
- App Group 共享 SQLite 数据库
- 本地通知（UserNotifications）

## 涉及文件

```
ios/
  ├── Runner/
  │   └── AppDelegate.swift        — 修改：配置 App Group
  ├── ShareExtension/              — 新建：Share Extension target
  │   ├── ShareViewController.swift
  │   ├── OCRService.swift         — Vision OCR 封装
  │   ├── SharedDatabase.swift     — 共享数据库访问
  │   ├── MealRecorder.swift       — 记录写入逻辑
  │   └── NotificationHelper.swift — 本地通知
  └── Runner.entitlements          — 修改：添加 App Group
```

## Share Extension 流程

```
用户分享图片 → Share Extension 启动
  │
  ├─ 1. 获取分享的图片
  │
  ├─ 2. Vision OCR 识别文字
  │     └─ 识别结果：[String] 文本行
  │
  ├─ 3. 菜品匹配
  │     └─ DishMatcher 匹配 L2 菜品
  │
  ├─ 4. 判断餐次
  │     └─ 根据当前时间判断是早/午/晚/加餐
  │
  ├─ 5. 写入共享数据库
  │     ├─ 写入 meal_records 表
  │     ├─ 更新 pet_states（活力值+成长值）
  │     └─ 更新用户每日结构缓存（可选）
  │
  ├─ 6. 发送本地通知
  │     └─ 识别成功/失败通知
  │
  └─ 7. 结束扩展（不打开主 APP）
```

## App Group 配置

- App Group ID：`group.com.canting.app`
- 主 APP 和 Share Extension 都加入同一个 App Group
- 共享数据库文件放在 App Group 的 Library 目录下

## 共享数据库

```swift
class SharedDatabase {
    static let shared = SharedDatabase()

    // 数据库路径（App Group 内）
    var dbPath: String {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.canting.app")!
        return container.appendingPathComponent("Library/canting.db").path
    }

    // 初始化数据库（如果不存在）
    func setupDatabaseIfNeeded()

    // 查询菜品库（用于匹配）
    func getAllDishes() -> [Dish]

    // 添加餐食记录
    func addMealRecord(_ record: MealRecord)

    // 更新宠物状态
    func updatePet(vitality: Double, growth: Double)

    // 获取用户档案（用于计算）
    func getUserProfile() -> UserProfile?
}
```

## OCRService

```swift
class OCRService {
    func recognizeText(in image: UIImage, completion: @escaping ([String]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion([])
                return
            }
            let textLines = observations.compactMap {
                $0.topCandidates(1).first?.string
            }
            completion(textLines)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
```

## 菜品匹配（Swift 版本）

需要把 Dart 版的 DishMatcher 逻辑用 Swift 实现一遍，或者：

**方案 A**：Swift 重新实现匹配逻辑（推荐，性能好）
**方案 B**：通过 Method Channel 调用 Flutter 侧的匹配（复杂，不推荐）

V1.0 用方案 A，Swift 实现简化版匹配：
- 精确匹配
- 包含匹配
- 关键词归类

## 通知

### 识别成功通知

```swift
func sendSuccessNotification(dishName: String, mealType: String, petText: String) {
    let content = UNMutableNotificationContent()
    content.title = "已记录\(mealType)"
    content.body = "\(dishName) · \(petText)"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: 0.5, repeats: false)

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: trigger)

    UNUserNotificationCenter.current().add(request)
}
```

### 识别失败通知

```
标题：没认出来 🤔
内容：这张图没认出来，打开APP手动添加吧
```

## 主 APP 侧同步

- 主 APP 从后台进入前台时
- 检查是否有新的共享记录
- 如果有，刷新首页数据
- 可以用 `UserDefaults`（App Group）做一个"有新数据"的标记

```swift
// Share Extension 写完后设置标记
UserDefaults(suiteName: "group.com.canting.app")?
    .set(true, forKey: "hasNewData")

// 主 APP 启动时检查
if UserDefaults(suiteName: "group.com.canting.app")?
    .bool(forKey: "hasNewData") == true {
    // 刷新数据
    // 清除标记
}
```

## 边界情况处理

- 图片不是订单截图（识别不出菜名）→ 发失败通知
- 只识别出 1 道菜 → 正常记录
- 识别出多道菜 → 全部记录
- 数据库未初始化（首次使用分享扩展）→ 初始化数据库
- 处理超时（Share Extension 有时间限制）→ 保存已识别的部分，发通知说明

## 验收标准

- [ ] 美团外卖订单截图 → 分享到餐盘 → 收到成功通知
- [ ] 打开 APP → 首页显示新记录
- [ ] 识别成功通知显示正确的菜名和宠物文案
- [ ] 识别失败时发送失败通知
- [ ] 分享扩展处理过程中不打开主 APP
- [ ] 主 APP 从后台切到前台时数据刷新
- [ ] 杀掉 APP 状态下，分享扩展仍能正常工作
- [ ] 多道菜都能正确识别和记录
- [ ] 餐次判断正确（早/午/晚）
- [ ] App Group 数据共享正常
