import Foundation
import WidgetKit

struct PetWidgetEntry: TimelineEntry {
  let date: Date
  let state: PetWidgetState
}

struct PetWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> PetWidgetEntry {
    PetWidgetEntry(date: Date(), state: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (PetWidgetEntry) -> Void
  ) {
    completion(
      PetWidgetEntry(
        date: Date(),
        state: context.isPreview ? .placeholder : PetWidgetState.load()
      )
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<PetWidgetEntry>) -> Void
  ) {
    let entry = PetWidgetEntry(date: Date(), state: PetWidgetState.load())
    let refreshDate = Calendar.current.date(
      byAdding: .minute,
      value: 15,
      to: entry.date
    ) ?? entry.date.addingTimeInterval(15 * 60)
    completion(Timeline(entries: [entry], policy: .after(refreshDate)))
  }
}
