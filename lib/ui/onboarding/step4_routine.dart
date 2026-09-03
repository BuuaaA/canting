import 'package:canting/state/onboarding_draft.dart';
import 'package:flutter/material.dart';

class Step4Routine extends StatefulWidget {
  const Step4Routine({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  State<Step4Routine> createState() => _Step4RoutineState();
}

class _Step4RoutineState extends State<Step4Routine> {
  Future<void> _pickTime(
    TimeOfDay initial,
    ValueChanged<TimeOfDay> onPicked,
  ) async {
    final result = await showTimePicker(context: context, initialTime: initial);
    if (result != null) setState(() => onPicked(result));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('作息习惯', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '用于安排温和的吃饭提醒，之后可随时修改。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text('平时几点吃饭？', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _TimeRow(
            label: '早餐',
            icon: Icons.wb_sunny_outlined,
            value: widget.draft.breakfast,
            onTap: () => _pickTime(
              widget.draft.breakfast,
              (value) => widget.draft.breakfast = value,
            ),
          ),
          _TimeRow(
            label: '午餐',
            icon: Icons.sunny,
            value: widget.draft.lunch,
            onTap: () => _pickTime(
              widget.draft.lunch,
              (value) => widget.draft.lunch = value,
            ),
          ),
          _TimeRow(
            label: '晚餐',
            icon: Icons.nights_stay_outlined,
            value: widget.draft.dinner,
            onTap: () => _pickTime(
              widget.draft.dinner,
              (value) => widget.draft.dinner = value,
            ),
          ),
          const SizedBox(height: 20),
          Text('一天从几点切换', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '熬夜吃的宵夜算第二天，默认凌晨 1 点切换。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('0:00')),
                ButtonSegment(value: 1, label: Text('1:00')),
                ButtonSegment(value: 4, label: Text('4:00')),
              ],
              selected: {widget.draft.dayBoundaryHour},
              onSelectionChanged: (value) {
                setState(() => widget.draft.dayBoundaryHour = value.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.schedule, size: 18),
        label: Text(value.format(context)),
      ),
    );
  }
}
