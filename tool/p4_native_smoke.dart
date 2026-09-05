import 'package:crypto/crypto.dart';

// P4 emulator-only entrypoint; dedicated DB, no production asset changes.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/ocr/in_app_ocr_launcher.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/theme/app_theme.dart';

class CaptureBridge extends AndroidNativeBridge {
  Map<Object?, Object?>? raw;
  @override
  Future<NativeOcrResult> recognizeImage(String imageUri) async {
    raw = await const MethodChannel('com.canting.app/ocr')
        .invokeMapMethod<Object?, Object?>('recognizeImage', {
          'imageUri': imageUri,
        });
    return NativeOcrResult.fromMap(raw!);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final cache = await getTemporaryDirectory();
  final helper = DatabaseHelper(
    databasePath: '${docs.path}/p4_acceptance_only.db',
  );
  await helper.initialize(
    seedData: FoodDatabase.fromJson(
      dishesJson: await rootBundle.loadString('assets/data/dishes.json'),
      categoriesJson: await rootBundle.loadString(
        'assets/data/categories.json',
      ),
    ),
  );
  final state = AppState(
    databaseHelper: helper,
    guidelines: DietaryGuidelines.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(
          await rootBundle.loadString('assets/data/dietary_guidelines.json'),
        ) as Map,
      ),
    ),
  );
  await state.loadFromDatabase();
  final router = GoRouter(
    initialLocation: '/lab',
    routes: [
      GoRoute(
        path: '/lab',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('P4 合成图原生验收'))),
      ),
      GoRoute(
        path: '/record',
        builder: (_, _) => const RecordDetailPage(
          isSharedRecognition: true,
          returnLocation: '/lab',
        ),
      ),
    ],
  );
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  const lines = ['青青糯山 无糖 小杯 ×1', '香辣鸡腿堡 ×1', '奶油蛋糕30寸 ×1', '配送费 3元'];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1000, 600),
    Paint()..color = Colors.white,
  );
  final painter = TextPainter(
    text: const TextSpan(
      text: '青青糯山 无糖 小杯 ×1\n香辣鸡腿堡 ×1\n奶油蛋糕30寸 ×1\n配送费 3元',
      style: TextStyle(color: Colors.black, fontSize: 40, height: 1.8),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 920);
  painter.paint(canvas, const Offset(40, 40));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1000, 600);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final source = File('${docs.path}/p4_synthetic_input.png');
  await source.writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  painter.dispose();
  final frozenHash = sha256.convert(await source.readAsBytes()).toString();
  final frozenAt = DateTime.now().toUtc().toIso8601String();
  final staleUri = await InAppOcrLauncher.copyIntoSharedImages(source.path);
  final stale = File(
    '${cache.path}/shared_images/${Uri.parse(staleUri).pathSegments.last}',
  );
  await stale.setLastModified(DateTime.now().subtract(const Duration(days: 2)));
  final recentUri = await InAppOcrLauncher.copyIntoSharedImages(source.path);
  final recent = File(
    '${cache.path}/shared_images/${Uri.parse(recentUri).pathSegments.last}',
  );
  final results = <Map<String, Object?>>[];
  for (var repeat = 1; repeat <= 2; repeat++) {
    final uri = await InAppOcrLauncher.copyIntoSharedImages(source.path);
    final copy = File(
      '${cache.path}/shared_images/${Uri.parse(uri).pathSegments.last}',
    );
    final bridge = CaptureBridge();
    final pipeline = OcrPipeline(appState: state, bridge: bridge);
    final watch = Stopwatch()..start();
    pipeline.begin(uri);
    await pipeline.recognize(uri);
    watch.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    results.add({
      'repeat': repeat,
      'source_kind': 'synthetic_image',
      'run_kind': 'native_ocr',
      'input_lines': lines,
      'raw': bridge.raw,
      'duration_ms': watch.elapsedMilliseconds,
      'error': state.recognitionDraft?.error,
      'dishes': state.recognitionDraft?.dishes.map((d) => d.toJson()).toList(),
      'copy_exists_after_native': await copy.exists(),
      'original_exists': await source.exists(),
    });
  }
  // Invalid image exercises native failure cleanup; external paths must survive release.
  final bad = File('${docs.path}/p4_invalid_input.png');
  await bad.writeAsString('not an image');
  final badUri = await InAppOcrLauncher.copyIntoSharedImages(bad.path);
  String? failure;
  try {
    await AndroidNativeBridge().recognizeImage(badUri);
  } catch (e) {
    failure = e.toString();
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await AndroidNativeBridge().releaseImage(source.uri.toString());
  final concurrentUri = await InAppOcrLauncher.copyIntoSharedImages(
    source.path,
  );
  final concurrent = await Future.wait([
    AndroidNativeBridge().recognizeImage(concurrentUri),
    AndroidNativeBridge().recognizeImage(concurrentUri),
  ]);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final recentPreserved = await recent.exists();
  await AndroidNativeBridge().releaseImage(recentUri);
  final output = {
    'input_sha256_before_ocr': frozenHash,
    'frozen_at_before_ocr': frozenAt,
    'stale_copy_exists': await stale.exists(),
    'recent_copy_preserved_by_sweep': recentPreserved,
    'cancelled_recent_copy_exists': await recent.exists(),
    'concurrent_native_results': concurrent
        .map((x) => x.dishes.map((d) => d.name).toList())
        .toList(),
    'concurrent_copy_exists': await File(
      '${cache.path}/shared_images/${Uri.parse(concurrentUri).pathSegments.last}',
    ).exists(),
    'source_kind': 'synthetic_image',
    'run_kind': 'native_ocr',
    'fixture_note': 'Developer authored text raster; no real platform screenshot. Labels fixed in source before rendering.',
    'results': results,
    'invalid_image_error': failure,
    'invalid_copy_exists': await File(
      '${cache.path}/shared_images/${Uri.parse(badUri).pathSegments.last}',
    ).exists(),
    'external_original_preserved': await source.exists(),
    'meal_rows': (await helper.database.query('meal_records')).length,
  };
  await File('${docs.path}/p4_native_result.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  router.go('/record');
  debugPrint('P4_NATIVE_DONE');
}
