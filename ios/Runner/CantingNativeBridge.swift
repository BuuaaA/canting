import Flutter
import Foundation
import UIKit
import UserNotifications
import WidgetKit

final class CantingNativeBridge: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  private static let appGroupID = "group.com.canting.shared"
  private static let pendingMealFilename = "pending_shared_meal.json"
  private static let petStatusKey = "pet_status_json"

  private enum Channel {
    static let share = "com.canting.app/share"
    static let pet = "com.canting.app/pet"
    static let vision = "com.canting.app/vision"
    static let notification = "com.canting.app/notification"
  }

  private let ocrService = OCRService()

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CantingNativeBridge()
    for name in [
      Channel.share,
      Channel.pet,
      Channel.vision,
      Channel.notification,
    ] {
      let channel = FlutterMethodChannel(
        name: name,
        binaryMessenger: registrar.messenger()
      )
      registrar.addMethodCallDelegate(instance, channel: channel)
    }
    UNUserNotificationCenter.current().delegate = instance
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPendingSharedMeal":
      getPendingSharedMeal(result: result)
    case "acknowledgeSharedMeal":
      acknowledgeSharedMeal(call.arguments, result: result)
    case "getShareExtensionStatus":
      let groupAvailable = sharedContainerURL != nil
      let extensionURL = Bundle.main.builtInPlugInsURL?
        .appendingPathComponent("CantingShareExtension.appex")
      let extensionExists = extensionURL.map {
        FileManager.default.fileExists(atPath: $0.path)
      } ?? false
      result(groupAvailable && extensionExists)
    case "recognizeText":
      recognizeText(call.arguments, result: result)
    case "savePetStatus":
      savePetStatus(call.arguments, result: result)
    case "requestNotificationPermission":
      requestNotificationPermission(result: result)
    case "sendNotification":
      sendNotification(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func savePetStatus(_ arguments: Any?, result: FlutterResult) {
    guard
      let status = arguments as? [String: Any],
      JSONSerialization.isValidJSONObject(status),
      let defaults = UserDefaults(suiteName: Self.appGroupID)
    else {
      result(
        FlutterError(
          code: "invalid_pet_status",
          message: "Pet status must be a JSON-compatible dictionary",
          details: nil
        )
      )
      return
    }

    do {
      let data = try JSONSerialization.data(
        withJSONObject: status,
        options: [.sortedKeys]
      )
      guard let json = String(data: data, encoding: .utf8) else {
        throw CocoaError(.fileWriteInapplicableStringEncoding)
      }
      defaults.set(json, forKey: Self.petStatusKey)
      WidgetCenter.shared.reloadAllTimelines()
      result(true)
    } catch {
      result(
        FlutterError(
          code: "pet_status_write_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "notification_permission_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(granted)
        }
      }
    }
  }

  private func sendNotification(
    _ arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = arguments as? [String: Any],
      let title = arguments["title"] as? String,
      let body = arguments["body"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_notification",
          message: "title and body are required",
          details: nil
        )
      )
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let deepLink = arguments["deep_link"] as? String {
      content.userInfo["deep_link"] = deepLink
    }
    let identifier = arguments["identifier"] as? String ??
      "canting-\(UUID().uuidString)"
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: nil
      )
    ) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "notification_send_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        } else {
          result(true)
        }
      }
    }
  }

  private func recognizeText(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let typedData = arguments["image_data"] as? FlutterStandardTypedData,
      let image = UIImage(data: typedData.data)
    else {
      result(
        FlutterError(
          code: "invalid_image",
          message: "image_data must contain a valid encoded image",
          details: nil
        )
      )
      return
    }

    ocrService.recognizeText(in: image) { recognitionResult in
      DispatchQueue.main.async {
        switch recognitionResult {
        case .success(let lines):
          result([
            "lines": lines,
            "text": lines.joined(separator: "\n"),
          ])
        case .failure(let error):
          result(
            FlutterError(
              code: "vision_ocr_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func getPendingSharedMeal(result: FlutterResult) {
    guard let fileURL = pendingMealURL else {
      result(
        FlutterError(
          code: "app_group_unavailable",
          message: "App Group group.com.canting.shared is unavailable",
          details: nil
        )
      )
      return
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(nil)
      return
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let object = try JSONSerialization.jsonObject(with: data)
      result(object)
    } catch {
      result(
        FlutterError(
          code: "shared_meal_read_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func acknowledgeSharedMeal(
    _ arguments: Any?,
    result: FlutterResult
  ) {
    guard
      let arguments = arguments as? [String: Any],
      let expectedID = arguments["meal_id"] as? String,
      let fileURL = pendingMealURL
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "meal_id is required",
          details: nil
        )
      )
      return
    }

    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        result(true)
        return
      }
      let data = try Data(contentsOf: fileURL)
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard object?["meal_id"] as? String == expectedID else {
        result(false)
        return
      }
      try FileManager.default.removeItem(at: fileURL)
      result(true)
    } catch {
      result(
        FlutterError(
          code: "shared_meal_ack_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private var sharedContainerURL: URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupID
    )
  }

  private var pendingMealURL: URL? {
    sharedContainerURL?.appendingPathComponent(Self.pendingMealFilename)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if
      let value = response.notification.request.content.userInfo["deep_link"]
        as? String,
      let url = URL(string: value)
    {
      UIApplication.shared.open(url, options: [:]) { _ in
        completionHandler()
      }
    } else {
      completionHandler()
    }
  }
}
