import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VisionOCRResult {
  const VisionOCRResult({required this.lines, required this.text});

  final List<String> lines;
  final String text;

  factory VisionOCRResult.fromJson(Map<String, dynamic> json) {
    final lines = (json['lines'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return VisionOCRResult(
      lines: lines,
      text: json['text'] as String? ?? lines.join('\n'),
    );
  }
}

class SharedDishDraft {
  const SharedDishDraft({
    required this.name,
    required this.quantity,
    required this.portionSize,
    this.matchedDishId,
    this.matchConfidence = 0,
  });

  final String name;
  final int quantity;
  final String portionSize;
  final String? matchedDishId;
  final double matchConfidence;

  factory SharedDishDraft.fromJson(Map<String, dynamic> json) {
    return SharedDishDraft(
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      portionSize: json['portion_size'] as String? ?? 'normal',
      matchedDishId: json['matched_dish_id'] as String?,
      matchConfidence: (json['match_confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SharedMealDraft {
  const SharedMealDraft({
    required this.mealId,
    required this.merchant,
    required this.mealType,
    required this.timestamp,
    required this.dishes,
    this.imageUri,
  });

  final String mealId;
  final String merchant;
  final String mealType;
  final DateTime timestamp;
  final List<SharedDishDraft> dishes;
  final String? imageUri;

  factory SharedMealDraft.fromJson(Map<String, dynamic> json) {
    final rawDishes = json['dishes'] as List<Object?>? ?? const [];
    return SharedMealDraft(
      mealId: json['meal_id'] as String,
      merchant: json['merchant'] as String? ?? '外卖订单',
      mealType: json['meal_type'] as String? ?? 'snack',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      imageUri: json['image_uri'] as String?,
      dishes: rawDishes
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => SharedDishDraft.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((dish) => dish.name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class IOSNativeBridge {
  IOSNativeBridge._();

  static final instance = IOSNativeBridge._();
  static const shareChannel = MethodChannel('com.canting.app/share');
  static const petChannel = MethodChannel('com.canting.app/pet');
  static const visionChannel = MethodChannel('com.canting.app/vision');
  static const notificationChannel = MethodChannel(
    'com.canting.app/notification',
  );

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<SharedMealDraft?> getPendingSharedMeal() async {
    if (!isSupported) return null;
    final value = await shareChannel.invokeMethod<Object?>(
      'getPendingSharedMeal',
    );
    if (value is! Map<Object?, Object?>) return null;
    return SharedMealDraft.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  Future<bool> acknowledgeSharedMeal(String mealID) async {
    if (!isSupported) return true;
    return await shareChannel.invokeMethod<bool>('acknowledgeSharedMeal', {
          'meal_id': mealID,
        }) ??
        false;
  }

  Future<bool> getShareExtensionStatus() async {
    if (!isSupported) return false;
    return await petChannel.invokeMethod<bool>('getShareExtensionStatus') ??
        false;
  }

  Future<VisionOCRResult> recognizeText(Uint8List imageBytes) async {
    if (!isSupported) {
      throw UnsupportedError('Vision OCR is only available on iOS');
    }
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Must not be empty');
    }

    final value = await visionChannel.invokeMethod<Object?>('recognizeText', {
      'image_data': imageBytes,
    });
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Vision OCR returned an invalid response');
    }
    return VisionOCRResult.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  Future<bool> savePetStatus(Map<String, Object?> status) async {
    if (!isSupported) return false;
    return await petChannel.invokeMethod<bool>('savePetStatus', status) ??
        false;
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    return await notificationChannel.invokeMethod<bool>(
          'requestNotificationPermission',
        ) ??
        false;
  }

  Future<bool> sendNotification({
    required String title,
    required String body,
    String? deepLink,
    String? identifier,
  }) async {
    if (!isSupported) return false;
    final arguments = <String, Object?>{'title': title, 'body': body};
    if (deepLink != null) arguments['deep_link'] = deepLink;
    if (identifier != null) arguments['identifier'] = identifier;
    return await notificationChannel.invokeMethod<bool>(
          'sendNotification',
          arguments,
        ) ??
        false;
  }
}
