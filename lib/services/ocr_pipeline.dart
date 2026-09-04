import 'dart:async';

import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter/services.dart';

/// OCR 识别管线：分享图与 APP 内拍照/相册识别共用同一条
/// （startSharedRecognition 进加载态 → 原生识别 → complete/fail）。
///
/// 识别页（RecordDetailPage）监听 recognitionDraft 展示进度与结果，
/// 本类只负责推进状态机，不做任何 UI。
class OcrPipeline {
  OcrPipeline({required this._appState, AndroidNativeBridge? bridge})
    : _bridge = bridge ?? AndroidNativeBridge();

  final AppState _appState;
  final AndroidNativeBridge _bridge;

  /// 进入识别加载态。应在跳转识别页之前调用，保证页面打开即有草稿。
  void begin(String imageUri) {
    _appState.startSharedRecognition(imageUri);
  }

  /// 调原生 OCR 并落 complete/fail 状态。识别页打开后调用。
  ///
  /// [timeout] 覆盖模块 14「识别超时」场景：超时按失败处理并提示手动
  /// 添加；.timeout 会丢弃迟到的原生结果，失败态不会被覆盖。
  Future<void> recognize(
    String imageUri, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final recognition = await _bridge
          .recognizeImage(imageUri)
          .timeout(timeout);
      _appState.completeSharedRecognition(
        imageUri: imageUri,
        merchant: recognition.merchant,
        dishes: recognition.dishes
            .map(
              (dish) =>
                  MealDish(name: dish.name, quantity: dish.quantity.toDouble()),
            )
            .toList(growable: false),
      );
    } on TimeoutException {
      _appState.failSharedRecognition(
        imageUri: imageUri,
        message: '识别有点慢，图片可能太复杂，试试手动添加吧',
      );
    } on PlatformException catch (error) {
      _appState.failSharedRecognition(
        imageUri: imageUri,
        message: error.code == 'OCR_UNAVAILABLE'
            ? '当前设备无法使用文字识别，请手动添加菜品'
            : '这张图没看清，请手动添加菜品',
      );
    } catch (_) {
      _appState.failSharedRecognition(
        imageUri: imageUri,
        message: '这张图没看清，请手动添加菜品',
      );
    }
  }

  /// begin + recognize 一步到位（不需要先跳页的场景）。
  Future<void> run(String imageUri) async {
    begin(imageUri);
    await recognize(imageUri);
  }
}
