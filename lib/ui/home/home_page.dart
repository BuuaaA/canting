import 'package:canting/core_engine.dart';
import 'package:canting/pet/widgets/evolution_animation_widget.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/home/widgets/food_progress_list.dart';
import 'package:canting/ui/home/widgets/greeting_text.dart';
import 'package:canting/ui/home/widgets/nutrition_ring_chart.dart';
import 'package:canting/ui/home/widgets/pet_area.dart';
import 'package:canting/ui/home/widgets/recommendation_card.dart';
import 'package:canting/ui/home/widgets/summary_card.dart';
import 'package:canting/ui/home/widgets/today_records.dart';
import 'package:canting/ui/ocr/in_app_ocr_launcher.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final todayMeals = state.mealsFor(now);
    final completion = state.completionFor(now);
    final recommendation = state.recommendationFor(now);
    final eaten = todayMeals.fold(
      Portions.zero,
      (total, meal) => total + meal.portionsTotal,
    );
    final target = state.dailyIntake.portions;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final pendingFrom = state.pendingEvolutionFrom;

    // 无障碍"移除动画"开启时，直接清除进化信号，不播放动画
    if (disableAnimations && pendingFrom != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<AppState>().clearPendingEvolution();
        }
      });
    }

    final body = PixelBackdrop(
      child: PixelContentWidth(
        expandHeight: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
          children: [
            const PetArea(),
            const SizedBox(height: 18),
            const GreetingText(),
            const SizedBox(height: 10),
            SummaryCard(
              mealCount: todayMeals.length,
              completionByCategory: completion.byCategory,
            ),
            const SizedBox(height: 14),
            NutritionRingChart(
              overall: completion.overall,
              values: completion.byCategory,
            ),
            const SizedBox(height: 22),
            const PixelSectionHeader(
              title: '今日任务',
              trailing: '六类食物',
              icon: Icons.checklist,
            ),
            const SizedBox(height: 12),
            FoodProgressList(
              values: completion.byCategory,
              current: eaten,
              target: target,
            ),
            const SizedBox(height: 26),
            const PixelSectionHeader(title: '下一餐', icon: Icons.restaurant_menu),
            const SizedBox(height: 10),
            RecommendationCard(
              recommendation: recommendation,
              onTap: () => context.push('/recommendation'),
            ),
            const SizedBox(height: 26),
            PixelSectionHeader(
              title: '饮食日志',
              trailing: '${todayMeals.length} 餐',
              icon: Icons.menu_book_outlined,
            ),
            const SizedBox(height: 10),
            TodayRecords(
              meals: todayMeals,
              onMealTap: (meal) =>
                  context.push('/record_detail?mealId=${meal.mealId}'),
              onDelete: state.deleteMeal,
              onAdd: () => context.push('/manual_add'),
            ),
          ],
        ),
      ),
    );

    final showEvolution = !disableAnimations && pendingFrom != null;

    return Scaffold(
      appBar: PixelAppBar(
        title: '餐盘 · 今日',
        actions: [
          IconButton(
            tooltip: '添加一餐',
            onPressed: () => context.push('/record_detail'),
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _AddFab(onPressed: () => _showAddSheet(context)),
      body: showEvolution
          ? Stack(
              children: [
                body,
                EvolutionAnimationWidget(
                  petType: state.pet.petType,
                  fromStage: pendingFrom.name,
                  toStage: state.pet.growthStage.name,
                  petName: state.pet.petName,
                  onFinished: () {
                    if (context.mounted) {
                      context.read<AppState>().clearPendingEvolution();
                    }
                  },
                ),
              ],
            )
          : body,
    );
  }

  /// 底部「+」：拍照识别 / 相册选择 / 手动添加（模块 14）。
  void _showAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PixelSectionHeader(
                  title: '添加一餐',
                  icon: Icons.add_circle_outline,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const PixelIconTile(
                    icon: Icons.photo_camera_outlined,
                    size: 42,
                  ),
                  title: const Text('拍照识别'),
                  subtitle: const Text('拍下这餐，自动记菜品'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    InAppOcrLauncher.pickAndRecognize(
                      context,
                      ImageSource.camera,
                    );
                  },
                ),
                ListTile(
                  leading: const PixelIconTile(
                    icon: Icons.photo_outlined,
                    size: 42,
                  ),
                  title: const Text('相册选择'),
                  subtitle: const Text('外卖订单截图自动记账'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    InAppOcrLauncher.pickAndRecognize(
                      context,
                      ImageSource.gallery,
                    );
                  },
                ),
                ListTile(
                  leading: const PixelIconTile(icon: Icons.edit_note, size: 42),
                  title: const Text('手动添加'),
                  subtitle: const Text('搜菜名或填克重，最顺手'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push('/manual_add');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      tooltip: '记一餐',
      heroTag: 'home-add-fab',
      onPressed: onPressed,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: scheme.outline, width: 2),
      ),
      child: const Icon(Icons.add, size: 30),
    );
  }
}
