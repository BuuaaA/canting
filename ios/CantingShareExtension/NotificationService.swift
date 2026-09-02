import Foundation
import UserNotifications

final class NotificationService {
  private let center = UNUserNotificationCenter.current()

  func sendRecordedMealNotification(
    dishes: [MatchedDish],
    mealType: String
  ) {
    let content = UNMutableNotificationContent()
    content.title = "已识别\(localizedMealType(mealType))"

    if dishes.isEmpty {
      content.body = "好像没认出菜呢，打开餐盘搜索添加吧"
    } else {
      let names = dishes.prefix(2).map { $0.extracted.name }.joined(separator: "、")
      let unmatchedCount = dishes.filter { $0.dishID == nil }.count
      content.body = unmatchedCount == 0
        ? "已找到 \(dishes.count) 道菜：\(names)，打开餐盘核对"
        : "已识别 \(dishes.count) 道菜，还有的可以手动调整"
    }
    content.sound = .default
    content.userInfo = ["deep_link": "canting:///record_detail?source=share"]

    center.add(
      UNNotificationRequest(
        identifier: "canting-share-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
    )
  }

  func sendOCRFailureNotification() {
    let content = UNMutableNotificationContent()
    content.title = "餐盘识别未完成"
    content.body = "这张图没看清，打开餐盘手动添加吧"
    content.sound = .default
    content.userInfo = ["deep_link": "canting:///record_detail?source=share"]
    center.add(
      UNNotificationRequest(
        identifier: "canting-share-error-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
    )
  }

  func sendDuplicateNotification() {
    let content = UNMutableNotificationContent()
    content.title = "餐盘"
    content.body = "今天这顿已经记录过了"
    center.add(
      UNNotificationRequest(
        identifier: "canting-share-duplicate-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
    )
  }

  private func localizedMealType(_ value: String) -> String {
    switch value {
    case "breakfast": return "早餐"
    case "lunch": return "午餐"
    case "dinner": return "晚餐"
    default: return "加餐"
    }
  }
}
