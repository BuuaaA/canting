import Foundation

struct PetWidgetState: Decodable {
  static let appGroupID = "group.com.canting.shared"
  static let defaultsKey = "pet_status_json"

  let petType: String
  let petName: String
  let growthStage: String
  let vitality: Int
  let vitalityState: String
  let todayMealCount: Int
  let todayCompletionRate: Double
  let nextMealSummary: String
  let petSpriteName: String

  init(
    petType: String,
    petName: String,
    growthStage: String,
    vitality: Int,
    vitalityState: String,
    todayMealCount: Int,
    todayCompletionRate: Double,
    nextMealSummary: String,
    petSpriteName: String
  ) {
    self.petType = petType
    self.petName = petName
    self.growthStage = growthStage
    self.vitality = min(100, max(0, vitality))
    self.vitalityState = vitalityState
    self.todayMealCount = max(0, todayMealCount)
    self.todayCompletionRate = min(1, max(0, todayCompletionRate))
    self.nextMealSummary = nextMealSummary
    self.petSpriteName = petSpriteName
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let petType = try values.decodeIfPresent(String.self, forKey: .petType) ?? "cat"
    let growthStage =
      try values.decodeIfPresent(String.self, forKey: .growthStage) ?? "baby"
    let vitalityState =
      try values.decodeIfPresent(String.self, forKey: .vitalityState) ?? "good"
    self.init(
      petType: petType,
      petName: try values.decodeIfPresent(String.self, forKey: .petName) ?? "小挑食",
      growthStage: growthStage,
      vitality: try values.decodeIfPresent(Int.self, forKey: .vitality) ?? 60,
      vitalityState: vitalityState,
      todayMealCount:
        try values.decodeIfPresent(Int.self, forKey: .todayMealCount) ?? 0,
      todayCompletionRate:
        try values.decodeIfPresent(Double.self, forKey: .todayCompletionRate) ?? 0,
      nextMealSummary:
        try values.decodeIfPresent(String.self, forKey: .nextMealSummary) ?? "记录下一餐",
      petSpriteName:
        try values.decodeIfPresent(String.self, forKey: .petSpriteName) ??
        "pet_\(petType)_\(growthStage)_\(vitalityState)_0"
    )
  }

  static let placeholder = PetWidgetState(
    petType: "cat",
    petName: "小挑食",
    growthStage: "baby",
    vitality: 60,
    vitalityState: "good",
    todayMealCount: 0,
    todayCompletionRate: 0,
    nextMealSummary: "打开餐盘记录一餐",
    petSpriteName: "pet_placeholder"
  )

  static func load() -> PetWidgetState {
    guard
      let defaults = UserDefaults(suiteName: appGroupID),
      let json = defaults.string(forKey: defaultsKey),
      let data = json.data(using: .utf8),
      let state = try? JSONDecoder().decode(PetWidgetState.self, from: data)
    else {
      return .placeholder
    }
    return state
  }

  var vitalityLabel: String {
    switch vitalityState {
    case "energetic": return "元气满满"
    case "good": return "状态不错"
    case "low": return "有点累了"
    default: return "等你开饭"
    }
  }

  var dialogue: String {
    switch vitalityState {
    case "energetic": return "今天也很有精神！"
    case "good": return "嗯，吃得不错嘛"
    case "low": return "下一餐要认真吃哦"
    default: return "肚子在等你啦"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case petType = "pet_type"
    case petName = "pet_name"
    case growthStage = "growth_stage"
    case vitality
    case vitalityState = "vitality_state"
    case todayMealCount = "today_meal_count"
    case todayCompletionRate = "today_completion_rate"
    case nextMealSummary = "next_meal_summary"
    case petSpriteName = "pet_sprite_name"
  }
}
