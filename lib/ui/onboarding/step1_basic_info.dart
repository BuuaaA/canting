import 'package:canting/state/onboarding_draft.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class Step1BasicInfo extends StatefulWidget {
  const Step1BasicInfo({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  State<Step1BasicInfo> createState() => _Step1BasicInfoState();
}

class _Step1BasicInfoState extends State<Step1BasicInfo> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      children: [
        Text('身体信息', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '用于估算每天适合你的食物份数。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        Text('性别', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'female',
              label: Text('女'),
              icon: Icon(Icons.female),
            ),
            ButtonSegment(
              value: 'male',
              label: Text('男'),
              icon: Icon(Icons.male),
            ),
          ],
          selected: {widget.draft.gender},
          onSelectionChanged: (value) {
            setState(() => widget.draft.gender = value.first);
          },
        ),
        const SizedBox(height: 28),
        _NumberSlider(
          label: '身高',
          value: widget.draft.heightCm.toDouble(),
          min: 130,
          max: 210,
          divisions: 80,
          suffix: 'cm',
          onChanged: (value) {
            setState(() => widget.draft.heightCm = value.round());
          },
        ),
        const SizedBox(height: 22),
        _NumberSlider(
          label: '体重',
          value: widget.draft.weightKg,
          min: 35,
          max: 150,
          divisions: 230,
          suffix: 'kg',
          decimals: 1,
          onChanged: (value) {
            setState(
              () => widget.draft.weightKg = (value * 2).roundToDouble() / 2,
            );
          },
        ),
        const SizedBox(height: 22),
        _NumberSlider(
          label: '年龄',
          value: widget.draft.age.toDouble(),
          min: 16,
          max: 80,
          divisions: 64,
          suffix: '岁',
          onChanged: (value) {
            setState(() => widget.draft.age = value.round());
          },
        ),
      ],
    );
  }
}

class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PixelPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
      child: Semantics(
        label: '$label ${value.toStringAsFixed(decimals)}$suffix',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                PixelBadge(
                  label: '${value.toStringAsFixed(decimals)} $suffix',
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
