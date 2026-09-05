import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef SharedImageHandler = Future<void> Function(String imageUri);

class NativeRecognizedDish {
  const NativeRecognizedDish({
    required this.name,
    required this.quantity,
    this.requiresConfirmation = false,
  });

  final bool requiresConfirmation;

  final String name;
  final int quantity;

  factory NativeRecognizedDish.fromMap(Map<Object?, Object?> map) {
    return NativeRecognizedDish(
      requiresConfirmation: map['requiresConfirmation'] == true,
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

class NativeOcrResult {
  const NativeOcrResult({
    this.warnings = const [],
    required this.fullText,
    required this.engine,
    required this.merchant,
    required this.dishes,
  });

  final List<String> warnings;
  final String fullText;
  final String engine;
  final String merchant;
  final List<NativeRecognizedDish> dishes;

  factory NativeOcrResult.fromMap(Map<Object?, Object?> map) {
    final rawDishes = map['dishes'] as List<Object?>? ?? const [];
    return NativeOcrResult(
      warnings: (map['warnings'] as List? ?? []).whereType<String>().toList(),
      fullText: map['fullText'] as String? ?? '',
      engine: map['engine'] as String? ?? 'unknown',
      merchant: map['merchant'] as String? ?? '',
      dishes: rawDishes
          .whereType<Map>()
          .map(
            (dish) =>
                NativeRecognizedDish.fromMap(dish.cast<Object?, Object?>()),
          )
          .where((dish) => dish.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class AndroidNativeBridge {
  AndroidNativeBridge({
    MethodChannel? shareChannel,
    MethodChannel? ocrChannel,
    MethodChannel? petChannel,
  }) : _shareChannel =
           shareChannel ?? const MethodChannel('com.canting.app/share'),
       _ocrChannel = ocrChannel ?? const MethodChannel('com.canting.app/ocr'),
       _petChannel = petChannel ?? const MethodChannel('com.canting.app/pet');

  final MethodChannel _shareChannel;
  final MethodChannel _ocrChannel;
  final MethodChannel _petChannel;
  SharedImageHandler? _sharedImageHandler;
  String? _lastHandledImageUri;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize({required SharedImageHandler onSharedImage}) async {
    if (!isSupported) return;
    _sharedImageHandler = onSharedImage;
    _shareChannel.setMethodCallHandler(_handleShareMethod);

    try {
      final imageUri = await _shareChannel.invokeMethod<String>(
        'getInitialSharedImage',
      );
      if (imageUri != null) {
        await _dispatchSharedImage(imageUri);
      }
    } on MissingPluginException {
      // Android host integration is unavailable in unit/widget tests.
    }
  }

  Future<void> dispose() async {
    _sharedImageHandler = null;
    if (isSupported) {
      _shareChannel.setMethodCallHandler(null);
    }
  }

  Future<NativeOcrResult> recognizeImage(String imageUri) async {
    if (!isSupported) {
      throw UnsupportedError('Native OCR is only available on Android');
    }
    final result = await _ocrChannel.invokeMapMethod<Object?, Object?>(
      'recognizeImage',
      {'imageUri': imageUri},
    );
    if (result == null) {
      throw const FormatException('Android OCR returned no result');
    }
    return NativeOcrResult.fromMap(result);
  }

  Future<void> releaseImage(String uri) async {
    try {
      await _ocrChannel.invokeMethod<void>('releaseImage', {'imageUri': uri});
    } on MissingPluginException {
      /* Host tests and old native hosts. */
    } on PlatformException {
      /* Residual cleanup retries at next native entry. */
    }
  }

  Future<bool> savePetStatus(Map<String, Object?> status) async {
    if (!isSupported) return false;
    return await _petChannel.invokeMethod<bool>('savePetStatus', {
          'json': jsonEncode(status),
        }) ??
        false;
  }

  Future<String?> saveMealRecord(Map<String, Object?> mealRecord) async {
    if (!isSupported) return null;
    return _petChannel.invokeMethod<String>('saveMealRecord', {
      'json': jsonEncode(mealRecord),
    });
  }

  Future<bool> getShareExtensionStatus() async {
    if (!isSupported) return false;
    final status = await _petChannel.invokeMapMethod<Object?, Object?>(
      'getShareExtensionStatus',
    );
    return status?['available'] == true;
  }

  Future<Object?> _handleShareMethod(MethodCall call) async {
    if (call.method != 'onSharedImage') {
      throw MissingPluginException('Unknown share method: ${call.method}');
    }
    final arguments = (call.arguments as Map?)?.cast<Object?, Object?>();
    final imageUri = arguments?['imageUri'] as String?;
    if (imageUri == null || imageUri.isEmpty) return null;
    await _dispatchSharedImage(imageUri);
    return null;
  }

  Future<void> _dispatchSharedImage(String imageUri) async {
    if (_lastHandledImageUri == imageUri) return;
    _lastHandledImageUri = imageUri;
    await _sharedImageHandler?.call(imageUri);
    try {
      await _shareChannel.invokeMethod<void>('acknowledgeSharedImage', {
        'imageUri': imageUri,
      });
    } on MissingPluginException {
      // The URI is still retained by the Android activity for the next launch.
    }
  }
}
