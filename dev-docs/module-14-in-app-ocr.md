# 模块 14：APP 内拍照识别

**预估工时**：2h
**依赖**：模块 02, 11, 12
**优先级**：P0

## 功能描述

APP 内的拍照/选图识别入口，作为分享扩展的补充方式。用户可以在 APP 内直接拍照或从相册选择图片进行识别。

## 涉及文件

```
lib/ui/ocr/
  ├── in_app_ocr_page.dart        — 拍照/选图入口页
  ├── ocr_result_page.dart        — 识别结果页
  └── image_cropper_page.dart     — 图片裁剪确认页（可选）
```

## 入口

- 首页「+ 添加记录」→ 弹出选项：
  - 拍照识别
  - 从相册选择
  - 手动添加

## 流程

```
点击"拍照识别" / "从相册选择"
  ↓
获取图片（image_picker）
  ↓
裁剪/确认（可选，V1.0 先不做裁剪）
  ↓
OCR 识别（调用原生 Method Channel）
  ↓
识别结果页（展示 + 可修改）
  ↓
用户确认保存
  ↓
添加记录 → 返回首页
```

## 原生 OCR 桥接

APP 内的 OCR 复用分享扩展用的同一套原生 OCR 实现，通过 Method Channel 暴露给 Flutter 调用。

### Method Channel 定义

```dart
class OcrChannel {
  static const MethodChannel _channel = MethodChannel('com.canting.app/ocr');

  static Future<List<String>> recognizeText(String imagePath) async {
    final result = await _channel.invokeMethod(
      'recognizeText',
      {'imagePath': imagePath},
    );
    return List<String>.from(result ?? []);
  }
}
```

### iOS 实现

```swift
// AppDelegate 或 OCRService.swift
@objc func recognizeText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["imagePath"] as? String else {
        result(FlutterError(code: "invalid_args", message: nil, details: nil))
        return
    }

    let image = UIImage(contentsOfFile: imagePath)
    OCRService.shared.recognizeText(in: image!) { textLines in
        result(textLines)
    }
}
```

### Android 实现

```kotlin
// MainActivity.kt
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.canting.app/ocr")
        .setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeText" -> {
                    val imagePath = call.argument<String>("imagePath")!!
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    val textLines = PaddleOCRManager(this).recognize(bitmap)
                    result.success(textLines)
                }
                else -> result.notImplemented()
            }
        }
}
```

## 识别结果页

同分享扩展的识别结果页（复用同一个组件），但有以下区别：
- 有「保存」和「取消」按钮
- 保存后跳转到记录详情页或返回首页
- 取消返回上一页

### 页面结构

```
← 识别结果

原图缩略图

识别出 2 道菜：
┌──────────────────────────┐
│ ✅ 黄焖鸡米饭   常规份  ✏️ │
└──────────────────────────┘
┌──────────────────────────┐
│ ⚠️ 蒜蓉西兰花   常规份  ✏️ │  ← 置信度中等，黄色标记
└──────────────────────────┘

未识别的文字：
  "配送费"  "打包费"  "满减"

餐次：[ 午餐 ⌄ ]
时间：[ 12:30 ⌄ ]

[  保存记录  ]
```

## 加载状态

OCR 识别需要 1-3 秒，期间显示加载状态：

```
正在识别中...
   📸 → 🔍 → ✅
```

- 加载动画
- 文案：「正在努力辨认中...」
- 不可取消（避免半途中止）

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 图片获取失败 | 提示「获取图片失败，请重试」 |
| OCR 初始化失败 | 提示「识别功能暂不可用，请稍后重试」 |
| 识别超时（>5秒） | 提示「识别有点慢，图片可能太复杂」+ 提供手动添加入口 |
| 识别结果为空 | 提示「没认出菜品，试试手动添加吧」+ 手动添加入口 |

## 验收标准

- [ ] 首页添加入口显示三个选项
- [ ] 拍照识别流程完整
- [ ] 相册选图识别流程完整
- [ ] OCR 识别能正确返回文字
- [ ] 识别结果页显示正确
- [ ] 可以修改菜品和分量
- [ ] 保存后记录正确添加
- [ ] 加载状态显示正常
- [ ] 错误场景有友好提示
- [ ] iOS 端 Method Channel 正常工作
- [ ] Android 端 Method Channel 正常工作
