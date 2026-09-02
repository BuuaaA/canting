import Foundation

struct MatchedDish {
  let extracted: ExtractedDish
  let dishID: String?
  let confidence: Double
  let portions: [String: Double]
  let sodiumLevel: String

  var json: [String: Any] {
    [
      "name": extracted.name,
      "quantity": extracted.quantity,
      "portion_size": extracted.portionSize,
      "matched_dish_id": dishID.map { $0 as Any } ?? NSNull(),
      "match_confidence": confidence,
      "portions": portions,
    ]
  }
}

final class DishCatalogMatcher {
  private struct CatalogDish {
    let id: String
    let name: String
    let terms: [String]
    let portions: [String: Double]
    let sodiumLevel: String
  }

  private lazy var catalog = loadCatalog()

  func match(_ extracted: ExtractedDish) -> MatchedDish {
    let query = normalize(extracted.name)
    var best: (dish: CatalogDish, score: Double)?

    for dish in catalog {
      for term in dish.terms {
        let normalizedTerm = normalize(term)
        let score: Double
        if normalizedTerm == query {
          score = term == dish.name ? 1.0 : 0.95
        } else if normalizedTerm.contains(query) || query.contains(normalizedTerm) {
          let shorter = min(normalizedTerm.count, query.count)
          let longer = max(normalizedTerm.count, query.count)
          score = longer == 0 ? 0 : 0.78 + 0.12 * Double(shorter) / Double(longer)
        } else {
          continue
        }

        if best == nil || score > best!.score {
          best = (dish, score)
        }
      }
    }

    guard let best else {
      return MatchedDish(
        extracted: extracted,
        dishID: nil,
        confidence: 0,
        portions: zeroPortions,
        sodiumLevel: "mid"
      )
    }
    return MatchedDish(
      extracted: extracted,
      dishID: best.dish.id,
      confidence: best.score,
      portions: scaledPortions(
        best.dish.portions,
        portionSize: extracted.portionSize
      ),
      sodiumLevel: best.dish.sodiumLevel
    )
  }

  private func loadCatalog() -> [CatalogDish] {
    guard
      let url = Bundle.main.url(forResource: "dishes", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }

    return rows.compactMap { row in
      guard
        let id = row["dish_id"] as? String,
        let name = row["dish_name"] as? String
      else {
        return nil
      }
      let aliases = row["aliases"] as? [String] ?? []
      let keywords = row["search_keywords"] as? [String] ?? []
      let portions = (row["portions_normal"] as? [String: Any] ?? [:])
        .compactMapValues { ($0 as? NSNumber)?.doubleValue }
      return CatalogDish(
        id: id,
        name: name,
        terms: [name] + aliases + keywords,
        portions: portions,
        sodiumLevel: row["sodium_level"] as? String ?? "mid"
      )
    }
  }

  private func scaledPortions(
    _ portions: [String: Double],
    portionSize: String
  ) -> [String: Double] {
    let scale = switch portionSize {
    case "small": 0.7
    case "large": 1.3
    default: 1.0
    }
    return portions.mapValues { ($0 * scale * 100).rounded() / 100 }
  }

  private func normalize(_ value: String) -> String {
    value
      .folding(options: [.widthInsensitive, .caseInsensitive], locale: .current)
      .replacingOccurrences(
        of: #"[^\p{Han}A-Za-z0-9]"#,
        with: "",
        options: .regularExpression
      )
      .lowercased()
  }

  private var zeroPortions: [String: Double] {
    [
      "grains": 0,
      "vegetables": 0,
      "fruits": 0,
      "protein": 0,
      "protein_soy": 0,
      "oil_base": 0,
    ]
  }
}
