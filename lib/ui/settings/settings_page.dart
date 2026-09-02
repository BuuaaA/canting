import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
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
                          '${profile?.heightCm ?? 165} cm · ${profile?.weightKg ?? 55} kg',
                      onTap: () => _showInfoDialog(
                        context,
                        '身体数据',
                        '身高 ${profile?.heightCm ?? 165} cm\n'
                            '体重 ${profile?.weightKg ?? 55} kg\n'
                            '年龄 ${profile?.age ?? 28} 岁',
                      ),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.flag_outlined,
                      title: '饮食目标',
                      value: _goalLabel(profile?.dietGoal ?? 'balanced'),
                      onTap: () => _showInfoDialog(
                        context,
                        '饮食目标',
                        '当前目标：${_goalLabel(profile?.dietGoal ?? 'balanced')}',
                      ),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.directions_walk,
                      title: '活动量',
                      value: _activityLabel(profile?.activityLevel ?? 'light'),
                      onTap: () => _showInfoDialog(
                        context,
                        '活动量',
                        '当前活动水平：'
                            '${_activityLabel(profile?.activityLevel ?? 'light')}',
                      ),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.schedule,
                      title: '作息习惯',
                      value: '早餐 ${_formatTime(profile?.breakfast)}',
                      onTap: () => _showInfoDialog(
                        context,
                        '作息习惯',
                        '早餐 ${_formatTime(profile?.breakfast)}\n'
                            '午餐 ${_formatTime(profile?.lunch, fallback: '12:00')}\n'
                            '晚餐 ${_formatTime(profile?.dinner, fallback: '18:30')}',
                      ),
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
              const _SectionTitle('数据管理'),
              const SizedBox(height: 9),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
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
                    const _SettingsTile(
                      icon: Icons.info_outline,
                      title: '版本号',
                      value: '1.0.0',
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
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.feedback_outlined,
                      title: '意见反馈',
                      onTap: () => _showInfoDialog(
                        context,
                        '意见反馈',
                        '感谢你的反馈。当前为 UI 开发版，反馈入口将在接入服务后开放。',
                      ),
                    ),
                    const Divider(indent: 58),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: '隐私政策',
                      onTap: () => _showInfoDialog(
                        context,
                        '隐私政策',
                        '餐盘只使用你主动提供的身体数据与饮食记录来生成建议。',
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

  static String _formatTime(TimeOfDay? value, {String fallback = '08:00'}) {
    if (value == null) return fallback;
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String _goalLabel(String value) => switch (value) {
    'more_vegetables' => '多吃蔬菜',
    'more_protein' => '多补蛋白质',
    'control_grains' => '控制主食',
    _ => '吃得更均衡',
  };

  static String _activityLabel(String value) => switch (value) {
    'sedentary' => '久坐',
    'moderate' => '中等活动',
    'heavy' => '重度活动',
    _ => '轻度活动',
  };

  static void _showInfoDialog(
    BuildContext context,
    String title,
    String content,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
                onTap: () {
                  Clipboard.setData(ClipboardData(text: state.exportJson()));
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
        title: const Text('清空所有饮食记录？'),
        content: const Text('这项操作无法撤销，个人设置和宠物会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      state.clearData();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('饮食记录已清空')));
      }
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
