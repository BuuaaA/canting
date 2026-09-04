import 'dart:async';
import 'dart:io';

import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// APP 内拍照/相册识别入口（模块 14）。
///
/// image_picker 返回的是文件路径，而原生 `recognizeImage` 只接受
/// `content://` 且 authority 为 com.canting.fileprovider 的 URI，
/// 因此参照 ShareActivity.copyToAppCache 的做法：先把图复制进
/// `cacheDir/shared_images/`，再按 file_paths.xml 的映射拼出
/// FileProvider URI，然后走与分享识别相同的管线（识别结果复用
/// RecordDetailPage，source 同样记 'ocr'）。
abstract final class InAppOcrLauncher {
  /// 与 ShareActivity.FILE_PROVIDER_AUTHORITY / file_paths.xml 保持一致。
  static const _fileProviderAuthority = 'com.canting.fileprovider';
  static const _sharedImageDirName = 'shared_images';

  /// 从相机或相册取一张图并进入识别流程。
  ///
  /// 用户取消不提示；取图/复制失败给出模块 14 文案，并提供
  /// 「手动添加」入口。
  static Future<void> pickAndRecognize(
    BuildContext context,
    ImageSource source,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final appState = context.read<AppState>();

    final String? pickedPath;
    try {
      final picked = await ImagePicker().pickImage(source: source);
      pickedPath = picked?.path;
    } catch (_) {
      _showPickFailure(messenger, router);
      return;
    }
    if (pickedPath == null) {
      return; // 用户取消选图，不是错误。
    }

    final String imageUri;
    try {
      imageUri = await copyIntoSharedImages(pickedPath);
    } catch (_) {
      _showPickFailure(messenger, router);
      return;
    }

    final pipeline = OcrPipeline(appState: appState);
    pipeline.begin(imageUri);
    // push 而不是 go：从首页弹层进入，压栈返回时回到原页面；
    // 与手动添加入口的跳转方式保持一致。
    router.push('/record_detail?source=share');
    unawaited(pipeline.recognize(imageUri));
  }

  /// 把选中的图片复制进 `cacheDir/shared_images/`，返回可交给原生
  /// recognizeImage 的 FileProvider content:// URI。
  ///
  /// 复制用同步 IO：截图/照片量级小、耗时可忽略，且能保证进入识别页
  /// 前 URI 指向的文件一定就绪（与 ShareActivity 的同步复制一致）。
  /// [cacheDir] 供测试注入；默认取系统缓存目录。
  static Future<String> copyIntoSharedImages(
    String sourcePath, {
    Directory? cacheDir,
  }) async {
    final resolvedCacheDir = cacheDir ?? (await getTemporaryDirectory());
    final directory = Directory(
      p.join(resolvedCacheDir.path, _sharedImageDirName),
    );
    directory.createSync(recursive: true);

    final extension = p.extension(sourcePath).replaceFirst('.', '');
    final safeExtension = RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)
        ? extension
        : 'jpg';
    final destination = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}.$safeExtension',
      ),
    );
    File(sourcePath).copySync(destination.path);

    return 'content://$_fileProviderAuthority/$_sharedImageDirName/'
        '${destination.uri.pathSegments.last}';
  }

  static void _showPickFailure(
    ScaffoldMessengerState messenger,
    GoRouter router,
  ) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text('获取图片失败，请重试'),
        action: SnackBarAction(
          label: '手动添加',
          onPressed: () => router.go('/manual_add'),
        ),
      ),
    );
  }
}
