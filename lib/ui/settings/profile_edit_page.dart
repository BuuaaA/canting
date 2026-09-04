import 'package:canting/core_engine.dart';
import 'package:canting/ui/settings/profile_update.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 个人信息编辑页（模块 10）。
///
/// 页面不直接依赖 AppState：数据通过 [profile] 传入，保存结果通过
/// [onSave] 回调交给调用方落库，便于独立构建与测试。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.profile,
    this.guidelines,
    this.onSave,
  });

  final UserProfile profile;

  /// 膳食指南数据；为 null 时保存会被拒绝（与 onboarding 的兜底一致）。
  final DietaryGuidelines? guidelines;

  /// 保存回调；返回 Future 以便调用方完成落库后再提示。
  final Future<void> Function(UserProfile profile)? onSave;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _ageController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late String _gender;
  late String _activityLevel;
  late String _dietGoal;
  late TimeOfDay _breakfast;
  late TimeOfDay _lunch;
  late TimeOfDay _dinner;
  late int _dayBoundaryHour;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _ageController = TextEditingController(text: '${profile.age}');
    _heightController = TextEditingController(
      text: profile.heightCm.round().toString(),
    );
    _weightController = TextEditingController(
      text: profile.weightKg.round().toString(),
    );
    _gender = profile.gender;
    _activityLevel = profile.activityLevel;
    _dietGoal = profile.dietGoal;
    _breakfast = _parseTime(
      profile.breakfastTime,
      const TimeOfDay(hour: 8, minute: 0),
    );
    _lunch = _parseTime(
      profile.lunchTime,
      const TimeOfDay(hour: 12, minute: 0),
    );
    _dinner = _parseTime(
      profile.dinnerTime,
      const TimeOfDay(hour: 18, minute: 30),
    );
    _dayBoundaryHour = int.tryParse(profile.dayStartTime.split(':').first) ?? 1;
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  static TimeOfDay _parseTime(String value, TimeOfDay fallback) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickTime({
    required String label,
    required TimeOfDay current,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: label,
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final age = int.tryParse(_ageController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    if (age == null || height == null || weight == null) {
      _toast('身高、体重、年龄需要填写数字');
      return;
    }
    final error = ProfileUpdate.validate(
      age: age,
      heightCm: height,
      weightKg: weight,
    );
    if (error != null) {
      _toast(error);
      return;
    }
    if (widget.guidelines == null) {
      _toast('膳食指南数据未加载，暂时无法保存');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('修改后今日数据会重新计算，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final updated = ProfileUpdate.apply(
      current: widget.profile,
      guidelines: widget.guidelines!,
      gender: _gender,
      age: age,
      heightCm: height,
      weightKg: weight,
      activityLevel: _activityLevel,
      dietGoal: _dietGoal,
      breakfastTime: _formatTime(_breakfast),
      lunchTime: _formatTime(_lunch),
      dinnerTime: _formatTime(_dinner),
      dayStartTime: '${_dayBoundaryHour.toString().padLeft(2, '0')}:00',
    );
    await widget.onSave?.call(updated);
    if (mounted) {
      _toast('已保存，今日目标份数已重新计算');
      Navigator.of(context).pop();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelAppBar(title: '个人信息', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              const PixelSectionHeader(
                title: '身体数据',
                icon: Icons.monitor_weight_outlined,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '身高（厘米）',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '体重（公斤）',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '年龄（岁）',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'female', label: Text('女')),
                              ButtonSegment(value: 'male', label: Text('男')),
                            ],
                            selected: {_gender},
                            onSelectionChanged: (selection) =>
                                setState(() => _gender = selection.first),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PixelSectionHeader(
                title: '活动量与目标',
                icon: Icons.directions_walk,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日常活动量', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _activityOptions)
                          ChoiceChip(
                            label: Text(option.label),
                            selected: _activityLevel == option.value,
                            onSelected: (_) =>
                                setState(() => _activityLevel = option.value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('饮食目标', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _dietGoalOptions)
                          ChoiceChip(
                            label: Text(option.label),
                            selected: _dietGoal == option.value,
                            onSelected: (_) =>
                                setState(() => _dietGoal = option.value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PixelSectionHeader(
                title: '作息习惯',
                icon: Icons.schedule,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.free_breakfast_outlined),
                      title: const Text('早餐时间'),
                      trailing: Text(_formatTime(_breakfast)),
                      onTap: () => _pickTime(
                        label: '早餐时间',
                        current: _breakfast,
                        onPicked: (time) => setState(() => _breakfast = time),
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.lunch_dining_outlined),
                      title: const Text('午餐时间'),
                      trailing: Text(_formatTime(_lunch)),
                      onTap: () => _pickTime(
                        label: '午餐时间',
                        current: _lunch,
                        onPicked: (time) => setState(() => _lunch = time),
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.dinner_dining_outlined),
                      title: const Text('晚餐时间'),
                      trailing: Text(_formatTime(_dinner)),
                      onTap: () => _pickTime(
                        label: '晚餐时间',
                        current: _dinner,
                        onPicked: (time) => setState(() => _dinner = time),
                      ),
                    ),
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.dark_mode_outlined),
                      title: const Text('一天从几点开始'),
                      subtitle: const Text('过了这个点才算新的一天'),
                      trailing: Text('$_dayBoundaryHour:00'),
                      onTap: _pickDayBoundary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存修改'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDayBoundary() {
    const hours = [0, 1, 4];
    return showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('一天从几点开始'),
        children: [
          for (final hour in hours)
            SimpleDialogOption(
              onPressed: () {
                setState(() => _dayBoundaryHour = hour);
                Navigator.pop(context);
              },
              child: Text('${hour.toString().padLeft(2, '0')}:00'),
            ),
        ],
      ),
    );
  }

  static const _activityOptions = [
    (value: 'sedentary', label: '久坐'),
    (value: 'light', label: '轻度活动'),
    (value: 'moderate', label: '中等活动'),
    (value: 'heavy', label: '重度活动'),
  ];

  static const _dietGoalOptions = [
    (value: 'balanced', label: '吃得更均衡'),
    (value: 'more_veg', label: '多吃蔬菜'),
    (value: 'more_protein', label: '多补蛋白质'),
    (value: 'less_carb', label: '控制主食'),
  ];
}
