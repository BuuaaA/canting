import 'package:canting/state/onboarding_draft.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class Step3Activity extends StatefulWidget {
  const Step3Activity({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  State<Step3Activity> createState() => _Step3ActivityState();
}

class _Step3ActivityState extends State<Step3Activity> {
  static const _options = [
    (
      value: 'sedentary',
      title: '久坐',
      subtitle: '日常以坐着为主，很少专门运动',
      icon: Icons.chair_outlined,
    ),
    (
      value: 'light',
      title: '轻度活动',
      subtitle: '每周有 1-3 次轻松运动',
      icon: Icons.directions_walk,
    ),
    (
      value: 'moderate',
      title: '中等活动',
      subtitle: '每周有 3-5 次中等强度运动',
      icon: Icons.directions_run,
    ),
    (
      value: 'heavy',
      title: '重度活动',
      subtitle: '高强度训练或体力工作较多',
      icon: Icons.fitness_center,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      children: [
        Text('活动水平', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '选择最接近日常状态的一项。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        for (final option in _options) ...[
          _ActivityOption(
            title: option.title,
            subtitle: option.subtitle,
            icon: option.icon,
            selected: widget.draft.activityLevel == option.value,
            onTap: () {
              setState(() => widget.draft.activityLevel = option.value);
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelPanel(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderColor: selected ? scheme.primary : scheme.outline,
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          PixelIconTile(
            icon: icon,
            size: 40,
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHigh,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? scheme.primary : scheme.outline,
          ),
        ],
      ),
    );
  }
}
