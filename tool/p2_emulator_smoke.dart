import 'package:canting/ui/ocr/in_app_ocr_launcher.dart';

// Emulator-only acceptance entrypoint. No fixture is part of production assets.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/ui/record/record_detail_page.dart';
import 'package:canting/ui/settings/local_food_page.dart';
import 'package:canting/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final helper = DatabaseHelper(
    databasePath: '${dir.path}/p2_acceptance_only.db',
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
      GoRoute(path: '/lab', builder: (context, _) => _Lab(state, helper)),
      GoRoute(
        path: '/record',
        builder: (_, _) => const RecordDetailPage(
          isSharedRecognition: true,
          returnLocation: '/lab',
        ),
      ),
      GoRoute(path: '/memory', builder: (_, _) => const LocalFoodPage()),
    ],
  );
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
}

class _Lab extends StatelessWidget {
  const _Lab(this.state, this.helper);
  final AppState state;
  final DatabaseHelper helper;
  Future<void> open(BuildContext context, List<String> names) async {
    final uri = 'synthetic:${DateTime.now().microsecondsSinceEpoch}';
    state.startSharedRecognition(uri);
    state.completeSharedRecognition(
      imageUri: uri,
      merchant: '',
      dishes: names.map((n) => MealDish(name: n)).toList(),
    );
    context.go('/record');
  }

  Future<void> ocr(BuildContext context) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final painter = TextPainter(
      text: const TextSpan(
        text: '青青糯山 无糖 小杯\n\n白斩鸡\n\n奶油蛋糕30寸',
        style: TextStyle(color: Colors.black, fontSize: 44),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 900);
    painter.paint(canvas, const Offset(40, 50));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1000, 650);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/p2_synthetic_order.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    painter.dispose();
    final pipeline = OcrPipeline(appState: state);
    final contentUri = await InAppOcrLauncher.copyIntoSharedImages(file.path);
    pipeline.begin(contentUri);
    if (context.mounted) context.go('/record');
    await pipeline.recognize(contentUri, timeout: const Duration(seconds: 30));
    debugPrint(
      'P2_NATIVE_OCR ${state.recognitionDraft?.dishes.map((d) => d.name).toList()} error=${state.recognitionDraft?.error}',
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('P2 模拟器验收入口')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('合成订单 · 独立验收数据库 · 以下打开真实业务页面'),
          FilledButton(
            onPressed: () => open(context, ['青青糯山', '白斩鸡']),
            child: const Text('A 未知归类 / 再次复用'),
          ),
          FilledButton(
            onPressed: () => open(context, ['青青糯山 无糖 小杯']),
            child: const Text('B 本次无糖小杯'),
          ),
          FilledButton(
            onPressed: () => open(context, ['香辣鸡腿堡', '巴斯克 小份', '奶油蛋糕30寸']),
            child: const Text('C 食品与蛋糕'),
          ),
          FilledButton(
            onPressed: () => context.go('/memory'),
            child: const Text('D 本机记忆管理'),
          ),
          FilledButton(
            onPressed: () => ocr(context),
            child: const Text('E 原生离线 OCR 合成图'),
          ),
          FilledButton(
            onPressed: () async {
              final dir = await getApplicationDocumentsDirectory();
              await File('${dir.path}/p2_export.json')
                  .writeAsString(await state.exportAllJson());
              debugPrint('P2_EXPORT ${dir.path}/p2_export.json');
            },
            child: const Text('F 导出验收数据'),
          ),
          Text('本机记忆：${state.localFoods.length}'),
          for (final p in state.localFoods)
            Text('${p.facts.name} ${p.facts.category} use=${p.useCount}'),
          Text('今日餐食：${state.mealsFor(DateTime.now()).length}'),
          for (final m in state.mealsFor(DateTime.now()))
            Text(
              '${m.dishes.map((d) => d.name).join(" / ")} complete=${m.structureComplete}',
            ),
        ],
      ),
    );
  }
}
