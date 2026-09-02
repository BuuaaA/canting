import SwiftUI
import WidgetKit

@main
struct CantingWidgetBundle: WidgetBundle {
  var body: some Widget {
    CantingPetWidget()
  }
}

struct CantingPetWidget: Widget {
  private let kind = "com.canting.app.pet-widget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PetWidgetProvider()) { entry in
      PetWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("餐盘伙伴")
    .description("查看伙伴活力、今日完成度和下一餐建议。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
