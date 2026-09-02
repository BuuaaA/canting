import 'package:canting/state/onboarding_draft.dart';
import 'package:canting/ui/onboarding/step4_routine.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class Step2DietGoal extends StatefulWidget {
  const Step2DietGoal({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  State<Step2DietGoal> createState() => _Step2DietGoalState();
}

class _Step2DietGoalState extends State<Step2DietGoal> {
  static const _goals = [
    (
      value: 'balanced',
      title: '吃得更均衡',
      description: '六类食物都照顾到',
      icon: Icons.pie_chart_outline,
    ),
    (
      value: 'more_vegetables',
      title: '多吃蔬菜',
      description: '每餐多一点新鲜蔬菜',
      icon: Icons.eco_outlined,
    ),
    (
      value: 'more_protein',
      title: '多补蛋白质',
      description: '适合运动和增肌阶段',
      icon: Icons.egg_alt_outlined,
    ),
    (
      value: 'control_grains',
      title: '控制主食',
      description: '适量安排，不需要完全不吃',
      icon: Icons.rice_bowl_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      children: [
        Text('饮食目标', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '先选现在最关心的一项，餐盘会据此调整建议。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _goals.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (context, index) {
            final goal = _goals[index];
            final selected = widget.draft.dietGoal == goal.value;
            return _GoalOption(
              title: goal.title,
              description: goal.description,
              icon: goal.icon,
              selected: selected,
              onTap: () {
                setState(() => widget.draft.dietGoal = goal.value);
              },
            );
          },
        ),
        Step4Routine(draft: widget.draft),
      ],
    );
  }
}

class _GoalOption extends StatelessWidget {
  const _GoalOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderColor: selected ? scheme.primary : scheme.outline,
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PixelIconTile(
                icon: icon,
                size: 38,
                color: selected
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHigh,
              ),
              const Spacer(),
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                color: selected ? scheme.primary : scheme.outline,
                size: 22,
              ),
            ],
          ),
          const Spacer(),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
