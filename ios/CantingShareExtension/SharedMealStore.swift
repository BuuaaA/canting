import CryptoKit
import Foundation

enum SharedMealStoreError: LocalizedError {
  case appGroupUnavailable
  case serializationFailed

  var errorDescription: String? {
    switch self {
    case .appGroupUnavailable:
      return "无法访问餐盘的共享存储"
    case .serializationFailed:
      return "识别结果无法保存"
    }
  }
}

final class SharedMealStore {
  static let appGroupID = "group.com.canting.shared"
  static let pendingMealFilename = "pending_shared_meal.json"
  private static let sharedImagePrefix = "shared_meal_"

  private let defaults = UserDefaults(suiteName: appGroupID)

  func isRecentDuplicate(imageData: Data, now: Date = Date()) -> Bool {
    guard
      let defaults,
      defaults.string(forKey: "last_shared_image_hash") == imageHash(imageData),
      let savedAt = defaults.object(forKey: "last_shared_image_date") as? Date
    else {
      return false
    }
    return now.timeIntervalSince(savedAt) < 12 * 60 * 60
  }

  func save(
    imageData: Data,
    merchant: String?,
    dishes: [MatchedDish],
    rawLines: [String],
    now: Date = Date()
  ) throws -> String {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupID
      )
    else {
      throw SharedMealStoreError.appGroupUnavailable
    }

    let mealID = UUID().uuidString.lowercased()
    let imageFilename = "\(Self.sharedImagePrefix)\(mealID).image"
    let imageURL = directory.appendingPathComponent(imageFilename)
    let portionsTotal = totalPortions(for: dishes)
    let meal: [String: Any] = [
      "meal_id": mealID,
      "merchant": merchant ?? "外卖订单",
      "meal_type": mealType(for: now),
      "timestamp": ISO8601DateFormatter().string(from: now),
      "image_uri": imageURL.absoluteString,
      "image_file_name": imageFilename,
      "dishes": dishes.map(\.json),
      "portions_total": portionsTotal,
      "completion_rate": 0.0,
      "sodium_level": highestSodiumLevel(in: dishes),
      "source": "share_extension",
      "source_ocr_lines": rawLines,
    ]
    guard JSONSerialization.isValidJSONObject(meal) else {
      throw SharedMealStoreError.serializationFailed
    }

    let data = try JSONSerialization.data(
      withJSONObject: meal,
      options: [.prettyPrinted, .sortedKeys]
    )
    do {
      try imageData.write(to: imageURL, options: .atomic)
      do {
        try data.write(
          to: directory.appendingPathComponent(Self.pendingMealFilename),
          options: .atomic
        )
      } catch {
        try? FileManager.default.removeItem(at: imageURL)
        throw error
      }
    }
    removeStaleSharedImages(in: directory, keeping: imageFilename)

    defaults?.set(imageHash(imageData), forKey: "last_shared_image_hash")
    defaults?.set(now, forKey: "last_shared_image_date")
    return mealID
  }

  private func totalPortions(for dishes: [MatchedDish]) -> [String: Double] {
    var result: [String: Double] = [
      "grains": 0,
      "vegetables": 0,
      "fruits": 0,
      "protein": 0,
      "protein_soy": 0,
      "oil_base": 0,
    ]
    for dish in dishes {
      let quantity = Double(dish.extracted.quantity)
      for (key, value) in dish.portions {
        result[key, default: 0] += value * quantity
      }
    }
    return result.mapValues { ($0 * 100).rounded() / 100 }
  }

  private func highestSodiumLevel(in dishes: [MatchedDish]) -> String {
    let levels = dishes.map(\.sodiumLevel)
    if levels.contains("high") { return "high" }
    if levels.contains("mid") { return "mid" }
    return "low"
  }

  private func mealType(for date: Date) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 0..<10: return "breakfast"
    case 10..<15: return "lunch"
    case 15..<21: return "dinner"
    default: return "snack"
    }
  }

  private func imageHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func removeStaleSharedImages(
    in directory: URL,
    keeping filename: String
  ) {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else {
      return
    }
    for file in files
    where file.lastPathComponent.hasPrefix(Self.sharedImagePrefix) &&
      file.lastPathComponent != filename {
      try? FileManager.default.removeItem(at: file)
    }
  }
}
