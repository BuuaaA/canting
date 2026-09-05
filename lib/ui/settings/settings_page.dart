import 'package:canting/ui/record/exposure_prompt.dart';

import 'local_food_page.dart';

import 'package:canting/pet.dart';
import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/services/notification_service.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/about/about_page.dart';
import 'package:canting/ui/settings/profile_edit_page.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const PixelAppBar(title: '我的'),
      body: PixelBackdrop(
        child: PixelContentWidth(
          expandHeight: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              _ProfileOverview(state: state),
              const SizedBox(height: 26),
              const _SectionTitle('个人信息'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.monitor_weight_outlined,
                      title: '身体数据',
                      value:
                          '${_formatHeight(profile?.heightCm)} cm · ${profile?.weightKg ?? 55} kg',
                      onTap: profile == null
                          ? null
                          : () => _openProfileEditor(context),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.flag_outlined,
                      title: '饮食目标',
                      value: _goalLabel(profile?.dietGoal ?? 'balanced'),
                      onTap: profile == null
                          ? null
                          : () => _openProfileEditor(context),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.directions_walk,
                      title: '活动量',
                      value: _activityLabel(profile?.activityLevel ?? 'light'),
                      onTap: profile == null
                          ? null
                          : () => _openProfileEditor(context),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.schedule,
                      title: '作息习惯',
                      value: '早餐 ${_formatTime(profile?.breakfastTime)}',
                      onTap: profile == null
                          ? null
                          : () => _openProfileEditor(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('我的宠物'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                color: theme.colorScheme.primaryContainer,
                child: _PetOverviewTile(
                  state: state,
                  onTap: () => context.push('/settings/pet'),
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('提醒设置'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.chat_bubble_outline),
                      title: const Text('识别结果通知'),
                      subtitle: const Text('识别成功或失败时告诉你'),
                      value: NotificationService.recognitionEnabled,
                      onChanged: (value) =>
                          _toggleRecognitionNotification(context, value),
                    ),
                    const Divider(indent: 58),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('用餐提醒'),
                      subtitle: const Text('到饭点了，回来看看'),
                      value: state.mealReminder,
                      onChanged: state.setMealReminder,
                    ),
                    const Divider(indent: 58),
                    SwitchListTile(
                      secondary: const Icon(Icons.tips_and_updates_outlined),
                      title: const Text('缺口提醒'),
                      subtitle: const Text('小挑食想吃菜菜'),
                      value: state.gapReminder,
                      onChanged: state.setGapReminder,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('外卖平台'),
              const SizedBox(height: 9),
              const _DeliveryPlatformSection(),
              const SizedBox(height: 26),
              const _SectionTitle('快捷记录'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: _SettingsTile(
                  icon: Icons.ios_share_outlined,
                  title: '分享扩展',
                  value: '使用说明',
                  onTap: () => _showShareGuide(context),
                ),
              ),
              const SizedBox(height: 26),
              PixelPanel(
                child: _SettingsTile(
                  icon: Icons.notifications_none,
                  title: '记录后的温和提醒',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExposurePreferencesPage(state: state),
                    ),
                  ),
                ),
              ),
              const _SectionTitle('数据管理'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.book_outlined,
                      title: '本机商品记忆',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LocalFoodPage(),
                        ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.download_outlined,
                      title: '导出数据',
                      value: 'JSON / CSV',
                      onTap: () => _showExportOptions(context, state),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.delete_outline,
                      title: '清空数据',
                      titleColor: theme.colorScheme.error,
                      onTap: () => _confirmClear(context, state),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('关于'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: '关于餐盘',
                      value: 'v1.0.0',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const AboutPage(),
                        ),
                      ),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.code,
                      title: '开源许可证',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: '餐盘',
                        applicationVersion: '1.0.0',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(String? value, {String fallback = '08:00'}) =>
      value ?? fallback;

  static String _formatHeight(double? heightCm) =>
      heightCm == null ? '165' : heightCm.round().toString();

  static String _goalLabel(String value) => switch (value) {
    'more_veg' || 'more_vegetables' => '多吃蔬菜',
    'more_protein' => '多补蛋白质',
    'less_carb' || 'control_grains' => '控制主食',
    _ => '吃得更均衡',
  };

  static String _activityLabel(String value) => switch (value) {
    'sedentary' => '久坐',
    'moderate' => '中等活动',
    'heavy' => '重度活动',
    _ => '轻度活动',
  };

  static void _openProfileEditor(BuildContext context) {
    final state = context.read<AppState>();
    final profile = state.profile;
    if (profile == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileEditPage(
          profile: profile,
          guidelines: state.guidelines,
          onSave: (updated) {
            // 修改后今日结构与完成度由 AppState 重算并通知监听者。
            return state.updateProfile(updated);
          },
        ),
      ),
    );
  }

  /// 切换识别结果通知开关；打开时顺带申请系统通知权限。
  static Future<void> _toggleRecognitionNotification(
    BuildContext context,
    bool value,
  ) async {
    NotificationService.recognitionEnabled = value;
    await NotificationSwitchPrefs.save(recognition: value);
    if (value) {
      final granted = await NotificationService.requestPermissions();
      if (context.mounted && !granted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('通知权限未开启，可在系统设置里打开')));
      }
    }
  }

  static void _showShareGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('截图分享记录', style: TextStyle(fontSize: 20)),
              SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.looks_one_outlined),
                title: Text('截取外卖订单或账单'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.looks_two_outlined),
                title: Text('点击系统分享，选择“餐盘”'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.looks_3_outlined),
                title: Text('检查菜品与分量后保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showExportOptions(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('复制 JSON 数据'),
                onTap: () async {
                  final data = await state.exportAllJson();
                  await Clipboard.setData(ClipboardData(text: data));
                  if (!context.mounted || !sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('JSON 数据已复制')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('导出 CSV'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV 导出将在数据层接入后启用')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmClear(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部数据？'),
        content: const Text(
          '所有餐食记录、宠物和设置都将被删除，不可恢复，'
          '清除后会回到初始设置页重新开始。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.clearAllData();
      // 档案清空后路由守卫会自动回到 onboarding 首页。
    }
  }
}

class _ProfileOverview extends StatelessWidget {
  const _ProfileOverview({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PixelPanel(
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Row(
        children: [
          PixelIconTile(
            icon: Icons.restaurant_outlined,
            size: 54,
            color: scheme.primaryContainer,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的餐盘', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text(
                  '${SettingsPage._goalLabel(state.profile?.dietGoal ?? 'balanced')}'
                  ' · ${SettingsPage._activityLabel(state.profile?.activityLevel ?? 'light')}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PetOverviewTile extends StatelessWidget {
  const _PetOverviewTile({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pet = state.pet;
    return ListTile(
      onTap: onTap,
      leading: PetSpriteWidget(
        petType: pet.petType,
        growthStage: pet.growthStage.name,
        vitalityState: pet.vitalityState.name,
        size: 46,
      ),
      title: Text(pet.petName),
      subtitle: Text('活力 ${pet.vitality} · 成长 ${pet.growth}'),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return PixelSectionHeader(title: text);
  }
}

/// 外卖平台设置（模块 10）：开关控制启用，上移/下移调整跳转优先级。
/// 配置经 [DeliveryPlatformPrefsStore] 落盘，推荐页跳转时读取同一份。
class _DeliveryPlatformSection extends StatefulWidget {
  const _DeliveryPlatformSection();

  @override
  State<_DeliveryPlatformSection> createState() =>
      _DeliveryPlatformSectionState();
}

class _DeliveryPlatformSectionState extends State<_DeliveryPlatformSection> {
  static const _store = DeliveryPlatformPrefsStore();
  static final _labelOf = {
    for (final platform in DeliveryJumpService.platforms)
      platform.id: platform.label,
  };

  List<DeliveryPlatformSetting>? _settings;

  @override
  void initState() {
    super.initState();
    _store.loadSettings().then((settings) {
      if (mounted) {
        setState(() => _settings = settings);
      }
    });
  }

  Future<void> _update(List<DeliveryPlatformSetting> settings) async {
    setState(() => _settings = settings);
    try {
      await _store.saveSettings(settings);
    } catch (error) {
      debugPrint('Unable to save delivery platform config: $error');
    }
  }

  void _toggle(int index, bool value) {
    final settings = [..._settings!];
    settings[index] = DeliveryPlatformSetting(
      id: settings[index].id,
      enabled: value,
    );
    _update(settings);
  }

  void _move(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _settings!.length) {
      return;
    }
    final settings = [..._settings!];
    final item = settings.removeAt(index);
    settings.insert(target, item);
    _update(settings);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const PixelPanel(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return PixelPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < settings.length; index++) ...[
            if (index > 0) const Divider(indent: 58),
            ListTile(
              leading: const Icon(Icons.moped_outlined),
              title: Text(_labelOf[settings[index].id] ?? settings[index].id),
              subtitle: settings[index].enabled
                  ? const Text('推荐跳转会优先用它')
                  : const Text('已停用，不在推荐页展示'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上移',
                    onPressed: index == 0 ? null : () => _move(index, -1),
                    icon: const Icon(Icons.arrow_upward_outlined),
                  ),
                  IconButton(
                    tooltip: '下移',
                    onPressed: index == settings.length - 1
                        ? null
                        : () => _move(index, 1),
                    icon: const Icon(Icons.arrow_downward_outlined),
                  ),
                  Switch(
                    value: settings[index].enabled,
                    onChanged: (value) => _toggle(index, value),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: titleColor),
      title: Text(title, style: TextStyle(color: titleColor)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
