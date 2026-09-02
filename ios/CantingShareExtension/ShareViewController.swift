import UIKit
import UniformTypeIdentifiers
import WidgetKit

@objc(ShareViewController)
final class ShareViewController: UIViewController {
  private let activityIndicator = UIActivityIndicatorView(style: .medium)
  private let statusLabel = UILabel()
  private let ocrService = OCRService()
  private let extractor = DishNameExtractor()
  private let matcher = DishCatalogMatcher()
  private let store = SharedMealStore()
  private let notifications = NotificationService()
  private var hasStarted = false

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !hasStarted else { return }
    hasStarted = true
    processSharedImage()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground
    statusLabel.text = "正在识别菜品..."
    statusLabel.font = .preferredFont(forTextStyle: .body)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
    activityIndicator.startAnimating()
  }

  private func processSharedImage() {
    guard let provider = imageProvider() else {
      finishWithError(message: "没有找到可识别的图片")
      return
    }

    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
      [weak self] data, error in
      guard let self else { return }
      guard error == nil, let data, let image = UIImage(data: data) else {
        self.finishWithError(message: "图片读取失败")
        return
      }

      if self.store.isRecentDuplicate(imageData: data) {
        self.notifications.sendDuplicateNotification()
        self.finishAndOpenApp(status: "这张图片已经处理过")
        return
      }

      self.ocrService.recognizeText(in: image) { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let lines):
          self.handleRecognizedLines(lines, imageData: data)
        case .failure:
          self.saveEmptyResultAndFinish(imageData: data)
        }
      }
    }
  }

  private func handleRecognizedLines(_ lines: [String], imageData: Data) {
    let extraction = extractor.extract(from: lines)
    let dishes = extraction.dishes.map(matcher.match)

    do {
      _ = try store.save(
        imageData: imageData,
        merchant: extraction.merchant,
        dishes: dishes,
        rawLines: lines
      )
      notifications.sendRecordedMealNotification(
        dishes: dishes,
        mealType: currentMealType
      )
      WidgetCenter.shared.reloadAllTimelines()
      finishAndOpenApp(
        status: dishes.isEmpty ? "未识别出菜品，请手动添加" : "识别完成，正在打开餐盘"
      )
    } catch {
      finishWithError(message: error.localizedDescription)
    }
  }

  private func saveEmptyResultAndFinish(imageData: Data) {
    do {
      _ = try store.save(
        imageData: imageData,
        merchant: nil,
        dishes: [],
        rawLines: []
      )
      notifications.sendOCRFailureNotification()
      finishAndOpenApp(status: "没有看清图片，请手动添加")
    } catch {
      finishWithError(message: error.localizedDescription)
    }
  }

  private func imageProvider() -> NSItemProvider? {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    return items
      .flatMap { $0.attachments ?? [] }
      .first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
  }

  private func finishAndOpenApp(status: String) {
    DispatchQueue.main.async {
      self.activityIndicator.stopAnimating()
      self.statusLabel.text = status
      let deepLink = URL(string: "canting:///record_detail?source=share")!
      self.extensionContext?.open(deepLink) { _ in
        self.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  private func finishWithError(message: String) {
    DispatchQueue.main.async {
      self.activityIndicator.stopAnimating()
      self.statusLabel.text = message
      self.notifications.sendOCRFailureNotification()
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        self.extensionContext?.completeRequest(returningItems: nil)
      }
    }
  }

  private var currentMealType: String {
    switch Calendar.current.component(.hour, from: Date()) {
    case 0..<10: return "breakfast"
    case 10..<15: return "lunch"
    case 15..<21: return "dinner"
    default: return "snack"
    }
  }
}
