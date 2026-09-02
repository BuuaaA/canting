import SwiftUI
import UIKit
import WidgetKit

struct PetWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PetWidgetEntry

  var body: some View {
    Group {
      if family == .systemMedium {
        mediumView
      } else {
        smallView
      }
    }
    .widgetURL(URL(string: "canting:///home"))
    .cantingWidgetBackground()
  }

  private var smallView: some View {
    VStack(spacing: 7) {
      PetSpriteView(spriteName: entry.state.petSpriteName, size: 58)
      HStack(spacing: 4) {
        Image(systemName: "heart.fill")
          .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.38))
        Text("\(entry.state.vitality)")
          .font(.system(size: 21, weight: .bold, design: .rounded))
          .monospacedDigit()
      }
      Text(entry.state.vitalityLabel)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
      Text("今天 \(entry.state.todayMealCount) 餐")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(12)
    .accessibilityElement(children: .combine)
  }

  private var mediumView: some View {
    HStack(spacing: 14) {
      VStack(spacing: 6) {
        PetSpriteView(spriteName: entry.state.petSpriteName, size: 68)
        Text(entry.state.petName)
          .font(.caption.weight(.bold))
          .lineLimit(1)
        Text(entry.state.dialogue)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }
      .frame(width: 112)

      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(width: 1)

      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline) {
          Label("活力", systemImage: "heart.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 0.38))
          Spacer()
          Text("\(entry.state.vitality)")
            .font(.title3.bold())
            .monospacedDigit()
        }

        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("今日完成度")
            Spacer()
            Text("\(Int((entry.state.todayCompletionRate * 100).rounded()))%")
              .monospacedDigit()
          }
          .font(.caption2)
          CompletionBar(progress: entry.state.todayCompletionRate)
        }

        Label(entry.state.nextMealSummary, systemImage: "clock")
          .font(.caption)
          .lineLimit(2)
          .foregroundStyle(Color(red: 0.75, green: 0.29, blue: 0.24))

        Text("今天已记录 \(entry.state.todayMealCount) 餐")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .accessibilityElement(children: .combine)
  }
}

private struct PetSpriteView: View {
  let spriteName: String
  let size: CGFloat

  var body: some View {
    Group {
      if let image = UIImage(named: spriteName) ?? UIImage(named: "pet_placeholder") {
        Image(uiImage: image)
          .resizable()
          .interpolation(.none)
      } else {
        Rectangle()
          .fill(Color(red: 0.28, green: 0.64, blue: 0.45))
          .overlay {
            Image(systemName: "pawprint.fill")
              .foregroundStyle(.white)
          }
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

private struct CompletionBar: View {
  let progress: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Rectangle().fill(Color.primary.opacity(0.12))
        Rectangle()
          .fill(Color(red: 0.92, green: 0.67, blue: 0.18))
          .frame(width: proxy.size.width * min(1, max(0, progress)))
      }
    }
    .frame(height: 7)
    .clipShape(RoundedRectangle(cornerRadius: 2))
  }
}

private extension View {
  @ViewBuilder
  func cantingWidgetBackground() -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) {
        Color(red: 0.96, green: 0.97, blue: 0.94)
      }
    } else {
      background(Color(red: 0.96, green: 0.97, blue: 0.94))
    }
  }
}
