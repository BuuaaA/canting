import 'package:canting/pet.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PetSettingsPage extends StatefulWidget {
  const PetSettingsPage({super.key});

  @override
  State<PetSettingsPage> createState() => _PetSettingsPageState();
}

class _PetSettingsPageState extends State<PetSettingsPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<AppState>().pet.petName,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.runes.isEmpty || name.runes.length > 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('昵称需要 1-6 个字符')));
      return;
    }
    context.read<AppState>().renamePet(name);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('昵称已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<AppState>().pet;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: const PixelAppBar(title: '我的宠物', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              PixelPanel(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    PetSpriteWidget(
                      petType: pet.petType,
                      growthStage: pet.growthStage.name,
                      vitalityState: pet.vitalityState.name,
                      size: 104,
                    ),
                    const SizedBox(height: 12),
                    Text(pet.petName, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 5),
                    Text(
                      '${_typeLabel(pet.petType)} · ${_stageLabel(pet.growthStage)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: '活力值',
                            value: '${pet.vitality}',
                            icon: Icons.favorite,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            label: '成长值',
                            value: '${pet.growth}',
                            icon: Icons.trending_up,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const PixelSectionHeader(
                title: '修改昵称',
                icon: Icons.edit_outlined,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '伙伴昵称',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存昵称'),
              ),
              const SizedBox(height: 28),
              const PixelSectionHeader(
                title: '桌面小组件',
                icon: Icons.widgets_outlined,
              ),
              const SizedBox(height: 10),
              PixelPanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: const PixelIconTile(
                    icon: Icons.widgets_outlined,
                    size: 42,
                  ),
                  title: const Text('把伙伴放到桌面'),
                  subtitle: const Text('在系统桌面长按空白处，选择“餐盘”小组件'),
                  trailing: IconButton(
                    tooltip: '查看添加方法',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (context) => const Padding(
                        padding: EdgeInsets.fromLTRB(24, 4, 24, 32),
                        child: Text('打开系统的小组件列表，搜索“餐盘”，选择喜欢的尺寸并添加到桌面。'),
                      ),
                    ),
                    icon: const Icon(Icons.help_outline),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _typeLabel(String value) => switch (value) {
    'cat' => '小猫',
    'dog' => '小狗',
    _ => '仓鼠',
  };

  static String _stageLabel(GrowthStage value) => switch (value) {
    GrowthStage.egg => '萌芽期',
    GrowthStage.baby => '幼年期',
    GrowthStage.adult => '成年期',
  };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
