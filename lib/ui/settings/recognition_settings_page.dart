import 'dart:convert';

import 'package:canting/services/recognition_configuration.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecognitionSettingsPage extends StatefulWidget {
  const RecognitionSettingsPage({super.key});

  @override
  State<RecognitionSettingsPage> createState() =>
      _RecognitionSettingsPageState();
}

class _RecognitionSettingsPageState extends State<RecognitionSettingsPage> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _credential = TextEditingController();
  RecognitionConfiguration? _state;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final schema = jsonDecode(
      await rootBundle.loadString(
        'dev-docs/recognition-v2/recognition.schema.json',
      ),
    ) as Map<String, dynamic>;
    final state = RecognitionConfiguration(
      RecognitionContract(schema),
      await SharedPreferences.getInstance(),
    );
    final saved = state.load();
    _endpoint.text = saved['endpoint'] as String? ?? '';
    _model.text = saved['model'] as String? ?? '';
    if (mounted) {
      setState(() {
        _state = state;
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    final state = _state!;
    state.setTemporaryCredential(_credential.text);
    try {
      await state.save({
        ...RecognitionConfiguration.defaults(),
        'mode': 'external',
        'endpoint': _endpoint.text.trim().isEmpty
            ? null
            : _endpoint.text.trim(),
        'model': _model.text.trim().isEmpty ? null : _model.text.trim(),
        'credentialRef': _credential.text.isEmpty
            ? null
            : 'credential:placeholder',
        'delivery': 'undecided',
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存非敏感占位配置；真实识别仍未接入')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('配置格式不正确，未保存')));
      }
    } finally {
      _credential.clear();
      state.clearTemporaryCredential();
    }
  }

  @override
  void dispose() {
    _state?.clearTemporaryCredential();
    _endpoint.dispose();
    _model.dispose();
    _credential.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PixelAppBar(title: '图片识别设置'),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PixelPanel(
                child: Text(
                  kDebugMode
                      ? '开发版可运行固定模拟，也可连接构建时配置的餐盘后端。模拟不会读取图片内容。'
                      : '启用后可连接构建时配置的餐盘后端；关闭时仍可本地 OCR 和手动记餐。',
                ),
              ),
              const SizedBox(height: 16),
              const Text('联网识别'),
              SwitchListTile(
                title: const Text('联网智能识别'),
                subtitle: const Text('关闭后继续使用本地 OCR 和手动记录'),
                value: _state!.cloudEnabled,
                onChanged: (value) async {
                  await _state!.setCloudEnabled(value);
                  if (!value) await _state!.setImageConsent(false);
                  setState(() {});
                },
              ),
              SwitchListTile(
                title: const Text('允许发送识别图片'),
                subtitle: const Text('图片和手机 OCR 文字会发送至餐盘后端并由阿里云百炼处理；可随时撤回'),
                value: _state!.imageConsent,
                onChanged: !_state!.cloudEnabled
                    ? null
                    : (value) async {
                        await _state!.setImageConsent(value);
                        setState(() {});
                      },
              ),
              const Text('客户端只连接餐盘后端，不含百炼 API Key。'),
              const SizedBox(height: 16),
              if (kDebugMode) ...[
                const Text('API 配置占位（仅开发版）'),
                const SizedBox(height: 8),
                TextField(
                controller: _endpoint,
                decoration: const InputDecoration(labelText: '服务地址'),
                ),
                const SizedBox(height: 8),
                TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: '模型名称'),
                ),
                const SizedBox(height: 8),
                TextField(
                controller: _credential,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API Key 交互占位',
                  helperText: '请勿输入真实凭证；内容不会保存、验证或联网',
                ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: const Text('保存占位配置')),
              ],
            ],
          ),
  );
}
