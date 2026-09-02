import ImageIO
import UIKit
import Vision

enum OCRServiceError: LocalizedError {
  case invalidImage
  case recognitionFailed

  var errorDescription: String? {
    switch self {
    case .invalidImage:
      return "无法读取分享的图片"
    case .recognitionFailed:
      return "未能识别图片中的文字"
    }
  }
}

final class OCRService {
  func recognizeText(
    in image: UIImage,
    completion: @escaping (Result<[String], Error>) -> Void
  ) {
    guard let cgImage = image.normalizedCGImage else {
      completion(.failure(OCRServiceError.invalidImage))
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error {
        completion(.failure(error))
        return
      }

      let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
        .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

      guard !lines.isEmpty else {
        completion(.failure(OCRServiceError.recognitionFailed))
        return
      }
      completion(.success(lines))
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = true
    request.customWords = [
      "黄焖鸡米饭", "番茄炒蛋", "清炒时蔬", "麻辣烫", "麻辣香锅",
      "螺蛳粉", "卤肉饭", "煎饼果子", "豆浆油条", "蒜蓉西兰花",
    ]

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let handler = VNImageRequestHandler(
          cgImage: cgImage,
          orientation: image.cgImageOrientation,
          options: [:]
        )
        try handler.perform([request])
      } catch {
        completion(.failure(error))
      }
    }
  }
}

private extension UIImage {
  var normalizedCGImage: CGImage? {
    if let cgImage {
      return cgImage
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format)
      .image { _ in draw(in: CGRect(origin: .zero, size: size)) }
      .cgImage
  }

  var cgImageOrientation: CGImagePropertyOrientation {
    switch imageOrientation {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .left: return .left
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
