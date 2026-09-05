import 'package:flutter/material.dart';
import 'package:canting/core/exposure.dart';
import 'package:canting/state/app_state.dart';

Future<void> showExposurePrompt(
  BuildContext context,
  AppState state,
  ExposurePrompt? prompt,
) async {
  if (prompt == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _Prompt(state: state, prompt: prompt),
  );
}

class _Prompt extends StatefulWidget {
  const _Prompt({required this.state, required this.prompt});
  final AppState state;
  final ExposurePrompt prompt;
  @override
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  String? error;
  bool busy = false;
  Future<void> save(String? family, {bool prefer = false}) async {
    setState(() => busy = true);
    try {
      final prefs = await widget.state.exposurePreferences();
      if (family != null) {
        prefs['muted_$family'] = widget.state
            .clock()
            .add(const Duration(days: 7))
            .toUtc()
            .toIso8601String();
      }
      if (prefer) prefs['next_time_preference'] = 'no_added_sugar';
      await widget.state.saveExposurePreferences(prefs);
      if (mounted) {
        setState(() => error = prefer ? '已记住下次偏好，本次记录保持原样' : '已暂停此类提醒7天');
      }
    } catch (_) {
      if (mounted) setState(() => error = '偏好未保存，可再次点击重试；餐食已经保存');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '已保存，给下次一个小建议',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            for (final e in widget.prompt.counts.entries) ...[
              Text(
                e.key == 'sugary_drink' &&
                        widget.prompt.nextTimePreference == 'no_added_sugar'
                    ? '最近7天已记录过含糖饮品。你记住的下次偏好是不另外加糖，可在下单时自行选择。'
                    : Exposure.messages[e.key]!,
              ),
              Text('最近7天记录中出现${e.value}餐；不是实际摄入总次数或安全额度。'),
              TextButton(
                onPressed: busy ? null : () => save(e.key),
                child: Text('暂停此类提醒7天 · ${Exposure.labels[e.key]}'),
              ),
            ],
            if (widget.prompt.counts.containsKey('sugary_drink'))
              TextButton(
                onPressed: busy ? null : () => save(null, prefer: true),
                child: const Text('记住下次偏好：不另外加糖'),
              ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExposurePreferencesPage extends StatefulWidget {
  const ExposurePreferencesPage({super.key, required this.state});
  final AppState state;
  @override
  State<ExposurePreferencesPage> createState() => _PreferencesState();
}

class _PreferencesState extends State<ExposurePreferencesPage> {
  Map<String, dynamic>? prefs;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await widget.state.exposurePreferences();
      if (mounted) setState(() => prefs = p);
    } catch (_) {
      if (mounted) setState(() => error = '读取失败，请重试');
    }
  }

  Future<void> save(Map<String, dynamic> p) async {
    try {
      await widget.state.saveExposurePreferences(p);
      if (mounted) {
        setState(() {
          prefs = p;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记录后的温和提醒')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('仅在主动保存后显示，不是系统通知。关闭不影响记录统计和推荐安全过滤。'),
        if (error != null) ...[
          Text(error!),
          TextButton(onPressed: load, child: const Text('重试')),
        ],
        if (prefs != null) ...[
          SwitchListTile(
            title: const Text('保存后显示重复记录提醒'),
            value: prefs!['enabled'] != false,
            onChanged: (v) => save({...prefs!, 'enabled': v}),
          ),
          SwitchListTile(
            title: const Text('下次偏好：不另外加糖'),
            subtitle: const Text('仅供未来提示，不修改任何订单糖型'),
            value: prefs!['next_time_preference'] == 'no_added_sugar',
            onChanged: (v) => save({
              ...prefs!,
              'next_time_preference': v ? 'no_added_sugar' : null,
            }),
          ),
          for (final family in Exposure.labels.keys)
            ListTile(
              title: Text(Exposure.labels[family]!),
              subtitle: Text(
                prefs!['muted_$family'] == null
                    ? '未暂停'
                    : '暂停至 ${DateTime.parse(prefs!['muted_$family'] as String).toLocal()}',
              ),
              trailing: TextButton(
                onPressed: () => save({...prefs!, 'muted_$family': null}),
                child: const Text('恢复提醒'),
              ),
            ),
          TextButton(
            onPressed: () async {
              try {
                await widget.state.clearExposurePreferences();
                await load();
              } catch (_) {
                if (mounted) setState(() => error = '清除失败，请重试');
              }
            },
            child: const Text('清除提醒偏好'),
          ),
        ],
      ],
    ),
  );
}
