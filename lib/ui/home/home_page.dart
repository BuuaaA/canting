import 'package:canting/pet/widgets/evolution_animation_widget.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/home/widgets/food_progress_list.dart';
import 'package:canting/ui/home/widgets/greeting_text.dart';
import 'package:canting/ui/home/widgets/nutrition_ring_chart.dart';
import 'package:canting/ui/home/widgets/pet_area.dart';
import 'package:canting/ui/home/widgets/recommendation_card.dart';
import 'package:canting/ui/home/widgets/summary_card.dart';
import 'package:canting/ui/home/widgets/today_records.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final todayMeals = state.mealsFor(DateTime.now());
    final completion = AppState.completion;
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
            FoodProgressList(values: completion.byCategory),
            const SizedBox(height: 26),
            const PixelSectionHeader(
              title: '下一餐',
              icon: Icons.restaurant_menu,
            ),
            const SizedBox(height: 10),
            RecommendationCard(onTap: () => context.push('/recommendation')),
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
              onAdd: () => context.push('/record_detail'),
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
        ],
      ),
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
}
