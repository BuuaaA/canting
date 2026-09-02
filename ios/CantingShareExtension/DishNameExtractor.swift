import Foundation

struct ExtractedDish {
  let name: String
  let quantity: Int
  let portionSize: String
}

struct DishExtractionResult {
  let merchant: String?
  let dishes: [ExtractedDish]
}

final class DishNameExtractor {
  private let excludedKeywords = [
    "合计", "总计", "实付", "应付", "优惠", "红包", "满减", "打包费", "包装费",
    "配送费", "服务费", "餐盒费", "收货地址", "配送地址", "订单号", "下单时间",
    "送达时间", "联系电话", "手机号", "骑手", "备注", "发票", "支付方式",
  ]

  private let interfaceKeywords = [
    "去评价", "再来一单", "申请售后", "联系商家", "联系骑手", "查看详情",
    "预计送达", "已送达", "订单已完成", "商品", "单价", "数量", "金额",
  ]

  func extract(from lines: [String]) -> DishExtractionResult {
    let normalizedLines = lines
      .flatMap { $0.components(separatedBy: .newlines) }
      .map { normalizeWhitespace($0) }
      .filter { !$0.isEmpty }

    let merchant = normalizedLines.first(where: isLikelyMerchant)
    var seen = Set<String>()
    var dishes = [ExtractedDish]()

    for line in normalizedLines {
      if line == merchant || shouldExclude(line) {
        continue
      }

      let quantity = extractQuantity(from: line)
      let portionSize = extractPortionSize(from: line)
      let name = cleanDishName(line)
      guard isPlausibleDishName(name), seen.insert(name).inserted else {
        continue
      }

      dishes.append(
        ExtractedDish(name: name, quantity: quantity, portionSize: portionSize)
      )
    }

    return DishExtractionResult(merchant: merchant, dishes: dishes)
  }

  private func shouldExclude(_ line: String) -> Bool {
    if excludedKeywords.contains(where: line.contains) ||
      interfaceKeywords.contains(where: line.contains) {
      return true
    }
    if line.range(of: #"^\s*[¥￥]?\s*\d+(?:\.\d{1,2})?\s*(?:元)?\s*$"#, options: .regularExpression) != nil {
      return true
    }
    if line.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil {
      return true
    }
    if line.range(of: #"^\d{1,2}[:：]\d{2}(?:\s*[-~至]\s*\d{1,2}[:：]\d{2})?$"#, options: .regularExpression) != nil {
      return true
    }
    return false
  }

  private func cleanDishName(_ line: String) -> String {
    var value = line
    value = replacing(#"^\s*(?:[·•●▪︎\-–—]|\d+[.)、])\s*"#, in: value)
    value = replacing(#"\s*[xX×*]\s*\d+\s*$"#, in: value)
    value = replacing(#"\s*[¥￥]\s*\d+(?:\.\d{1,2})?\s*(?:元)?\s*$"#, in: value)
    value = replacing(#"\s+\d+(?:\.\d{1,2})?\s*元\s*$"#, in: value)
    value = replacing(#"\s*[（(](?:大|中|小|标准|加大|迷你)?份?[）)]\s*$"#, in: value)
    value = replacing(#"\s*[-–—]\s*(?:微辣|中辣|重辣|不辣|少辣|少盐|少油|免辣)\s*$"#, in: value)
    value = replacing(#"[^\p{Han}A-Za-z0-9·]+"#, in: value, with: "")
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractQuantity(from line: String) -> Int {
    guard
      let match = firstMatch(#"[xX×*]\s*(\d{1,2})"#, in: line),
      let range = Range(match.range(at: 1), in: line),
      let quantity = Int(line[range])
    else {
      return 1
    }
    return max(1, min(quantity, 20))
  }

  private func extractPortionSize(from line: String) -> String {
    if line.range(of: #"(大份|加大)"#, options: .regularExpression) != nil {
      return "large"
    }
    if line.range(of: #"(小份|迷你)"#, options: .regularExpression) != nil {
      return "small"
    }
    return "normal"
  }

  private func isLikelyMerchant(_ line: String) -> Bool {
    guard line.count <= 30 else { return false }
    return line.range(
      of: #"(店|餐厅|餐馆|小馆|食堂|饭堂|厨房|外卖)$"#,
      options: .regularExpression
    ) != nil
  }

  private func isPlausibleDishName(_ value: String) -> Bool {
    guard (2...30).contains(value.count) else { return false }
    guard value.range(of: #"\p{Han}"#, options: .regularExpression) != nil else {
      return false
    }
    return !excludedKeywords.contains(where: value.contains) &&
      !interfaceKeywords.contains(where: value.contains)
  }

  private func normalizeWhitespace(_ value: String) -> String {
    replacing(#"\s+"#, in: value, with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func replacing(
    _ pattern: String,
    in value: String,
    with template: String = ""
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return value
    }
    return expression.stringByReplacingMatches(
      in: value,
      range: NSRange(value.startIndex..., in: value),
      withTemplate: template
    )
  }

  private func firstMatch(
    _ pattern: String,
    in value: String
  ) -> NSTextCheckingResult? {
    try? NSRegularExpression(pattern: pattern)
      .firstMatch(
        in: value,
        range: NSRange(value.startIndex..., in: value)
      )
  }
}
