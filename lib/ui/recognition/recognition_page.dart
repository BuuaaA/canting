import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/core/models/meal_record.dart';
import 'package:canting/services/recognition_adapter.dart';
import 'package:canting/services/recognition_configuration.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecognitionPage extends StatefulWidget {
  const RecognitionPage({
    super.key,
    required this.initialSourceKind,
    this.mealId,
  });
  final String initialSourceKind;
  final String? mealId;
  @override
  State<RecognitionPage> createState() => _RecognitionPageState();
}

class _RecognitionPageState extends State<RecognitionPage> {
  RecognitionContract? _contract;
  Map<String, dynamic>? _examples, _request;
  MealDraftV2? _draft;
  RecognitionConfiguration? _configuration;
  Map<String, dynamic>? _cloudResult;
  final Set<String> _cloudSelected = {};
  RecognitionCancellation? _cancellation;
  File? _workingImage;
  late String _sourceKind = widget.initialSourceKind == 'food_photo'
      ? 'food_photo'
      : 'screenshot';
  bool _busy = false, _covered = false, _cropped = false, _saved = false;
  String? _message;
  MockRecognitionScenario _scenario = MockRecognitionScenario.success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staleDir = Directory(
      p.join((await getTemporaryDirectory()).path, 'recognition_v2'),
    );
    if (await staleDir.exists()) {
      await for (final entry in staleDir.list()) {
        if (entry is File) await entry.delete();
      }
    }
    final schema = jsonDecode(
      await rootBundle.loadString(
        'dev-docs/recognition-v2/recognition.schema.json',
      ),
    ) as Map<String, dynamic>;
    final examples = jsonDecode(
      await rootBundle.loadString('dev-docs/recognition-v2/examples.json'),
    ) as Map<String, dynamic>;
    final contract = RecognitionContract(schema);
    final configuration = RecognitionConfiguration(
      contract,
      await SharedPreferences.getInstance(),
    );
    if (!mounted) return;
    MealDraftV2? editing;
    if (widget.mealId != null) {
      final meal = context.read<AppState>().mealById(widget.mealId!);
      if (meal?.recordVersion == 2) {
        editing = MealDraftV2.fromMeal(contract, meal!);
      }
    }
    if (mounted) {
      setState(() {
        _contract = contract;
        _configuration = configuration;
        _examples = examples;
        _draft = editing;
      });
    }
  }

  String _uuid(int salt) {
    final h = sha256
        .convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}:$salt'))
        .toString();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20, 32)}';
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'recognition_v2'),
      );
      await dir.create(recursive: true);
      final copy = await File(picked.path)
          .copy(p.join(dir.path, '${_uuid(0)}${p.extension(picked.path)}'));
      if (await copy.length() > 20 * 1024 * 1024) {
        await copy.delete();
        throw const FileSystemException('too large');
      }
      final old = _workingImage;
      _cancellation?.cancel();
      if (old != null && await old.exists()) await old.delete();
      if (!mounted) {
        await copy.delete();
        return;
      }
      setState(() {
        _workingImage = copy;
        _draft = null;
        _cloudResult = null;
        _cloudSelected.clear();
        _request = null;
        _message = null;
        _busy = false;
        _covered = false;
        _cropped = false;
      });
    } catch (_) {
      if (mounted) setState(() => _message = '无法取得图片。你仍可改用相册或手动记录。');
    }
  }

  Future<void> _recognize() async {
    final image = _workingImage;
    if (image == null || _contract == null || _examples == null) return;
    if (!kDebugMode) {
      setState(() => _message = '真实图片识别尚未接入，请仅在本地手动记录。');
      return;
    }
    final draftId = _uuid(1), requestId = _uuid(2), assetId = _uuid(3);
    final hash = sha256.convert(await image.readAsBytes()).toString();
    final request = _copy(_examples!['request'])
      ..['draftId'] = draftId
      ..['requestId'] = requestId
      ..['sourceKind'] = _sourceKind
      ..['cloudConsent'] = false
      ..['assets'] = [
        {
          'assetId': assetId,
          'hash': hash,
          'crop': _cropped ? [0.08, 0.08, 0.92, 0.92] : [0, 0, 1, 1],
          'capturePhase': 'unknown',
        },
      ];
    final fixture = _copy(_examples![_sourceKind]);
    fixture['draftId'] = draftId;
    fixture['requestId'] = requestId;
    fixture['sourceKind'] = _sourceKind;
    fixture['assets'] = _copyList(request['assets']);
    for (final Map e in fixture['evidence']) {
      e['assetId'] = assetId;
    }
    final empty = _copy(_examples!['empty_food']);
    empty['draftId'] = draftId;
    empty['requestId'] = requestId;
    empty['sourceKind'] = _sourceKind;
    empty['assets'] = _copyList(request['assets']);
    final cancel = RecognitionCancellation();
    setState(() {
      _busy = true;
      _message = null;
      _request = request;
      _cancellation = cancel;
    });
    final response = await RecognitionAdapter(_contract!).recognize(
      request,
      {...RecognitionConfiguration.defaults(), 'mode': 'mock'},
      scenario: _scenario,
      mockResult: fixture,
      mockEmptyResult: empty,
      timeout: const Duration(milliseconds: 40),
      mockDelay: const Duration(milliseconds: 15),
      cancellation: cancel,
    );
    if (!mounted || cancel.isCancelled || !identical(_request, request)) {
      return;
    }
    setState(() {
      _busy = false;
      if (response['state'] == 'review') {
        if (_contract!.canApply(request, response)) {
          _draft = MealDraftV2.fromResponse(_contract!, request, response);
          _message = '模拟结果仅用于测试流程；未分析这张图片。请逐项确认或修改。';
        } else {
          _message = '图片或草稿已经改变，旧结果已丢弃。';
        }
      } else {
        _message = _stateMessage(
          response['errorCode'] as String?,
          response['state'] as String,
        );
      }
    });
  }

  Future<void> _recognizeCloud() async {
    final image = _workingImage, configuration = _configuration;
    if (image == null || configuration == null) return;
    if (!configuration.cloudEnabled) {
      setState(() => _message = '联网识别已关闭。你仍可使用本地 OCR 或手动记录。');
      return;
    }
    if (!configuration.imageConsent) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发送图片进行联网识别？'),
          content: const Text(
            '所选图片和手机本地 OCR 文字将发送至餐盘后端，并由阿里云百炼处理。餐盘后端默认不保存原图。你可随时在设置中撤回。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('不用联网'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('同意并继续'),
            ),
          ],
        ),
      );
      if (allowed != true) {
        setState(() => _message = '未发送图片。可继续本地 OCR 或手动记录。');
        return;
      }
      await configuration.setImageConsent(true);
    }
    const baseUrl = String.fromEnvironment('CANTING_BACKEND_URL');
    final endpoint = RecognitionConfiguration.backendEndpoint(baseUrl);
    if (endpoint == null) {
      setState(() => _message = '餐盘后端地址尚未配置。已保留图片，可手动记录。');
      return;
    }
    final bytes = await image.readAsBytes();
    if (bytes.length > 6 * 1024 * 1024) {
      setState(() => _message = '图片超过 6MB，请换一张较小的图片或手动记录。');
      return;
    }
    final draftId = _uuid(11), requestId = _uuid(12), assetId = _uuid(13);
    String ocrText = '';
    try {
      ocrText = (await AndroidNativeBridge().recognizeImage(image.path))
          .fullText;
    } catch (_) {
      // Cloud image recognition remains useful when local OCR is unavailable.
    }
    final payload = <String, dynamic>{
      'schemaVersion': 'recognition-n0.3',
      'draftId': draftId,
      'requestId': requestId,
      'draftRevision': 0,
      'sourceKind': _sourceKind,
      'assets': [
        {
          'assetId': assetId,
          'imageSha256': sha256.convert(bytes).toString(),
          'crop': [0, 0, 1, 1],
          'capturePhase': 'unknown',
        },
      ],
      'ocrBlocks': ocrText.trim().isEmpty
          ? []
          : [
              {
                'blockId': 'local-ocr-1',
                'assetId': assetId,
                'text': ocrText.length > 2000
                    ? ocrText.substring(0, 2000)
                    : ocrText,
                'bbox': [0, 0, 1, 1],
                'confidence': null,
                'order': 0,
              },
            ],
      'locale': 'zh-CN',
      'cloudConsent': true,
      'consentVersion': RecognitionConfiguration.consentVersion,
    };
    final cancel = RecognitionCancellation();
    _request = payload;
    setState(() {
      _busy = true;
      _message = null;
      _cancellation = cancel;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('recognition_device_id_v1');
      if (deviceId == null) {
        deviceId = _uuid(14);
        await prefs.setString('recognition_device_id_v1', deviceId);
      }
      final response = await RecognitionAdapter(_contract!).recognizeCloud(
        endpoint: endpoint,
        deviceId: deviceId,
        payload: payload,
        image: image,
        cancellation: cancel,
      );
      if (!mounted || cancel.isCancelled || !identical(_request, payload)) {
        return;
      }
      final result = response['result'] as Map<String, dynamic>?;
      setState(() {
        _busy = false;
        _cloudResult = null;
        _cloudSelected.clear();
        _draft = result == null || (result['products'] as List).isEmpty
            ? null
            : MealDraftV2(
                _contract!,
                RecognitionAdapter(_contract!).cloudDraft(payload, response),
                simulated: false,
              );
        _message = result == null
            ? _stateMessage(
                response['errorCode'] as String?,
                response['state'] as String,
              )
            : (result['products'] as List).isEmpty
            ? '没有找到可靠食物。已保留图片，可重试或手动记录。'
            : '请核对识别结果。候选和推荐项默认不计入。';
      });
    } on RecognitionHttpException catch (error) {
      if (mounted && identical(_request, payload)) {
        setState(() {
          _busy = false;
          _message = _cloudError(error.code);
        });
      }
    } on FormatException {
      if (mounted && identical(_request, payload)) {
        setState(() {
          _busy = false;
          _message = '返回结果结构或绑定无效，已丢弃。可重试或手动记录。';
        });
      }
    } catch (_) {
      if (mounted && identical(_request, payload)) {
        setState(() {
          _busy = false;
          _message = '联网识别失败。已保留图片，可重试或手动记录。';
        });
      }
    }
  }

  static String _cloudError(String code) => switch (code) {
    'NO_NETWORK' => '当前无网络。已保留图片，可重试或手动记录。',
    'PROVIDER_TIMEOUT' => '识别超时。不会自动重试，可主动重试或手动记录。',
    'AUTH_REQUIRED' || 'PROVIDER_AUTH_FAILED' => '识别服务授权失效。已保留草稿，请稍后重试或手动记录。',
    'RATE_LIMITED' => '今日识别次数已用完。已保留草稿，可手动记录。',
    'BUDGET_EXCEEDED' => '本月识别预算已用完。已保留草稿，可手动记录。',
    'PROVIDER_UNAVAILABLE' => '识别服务暂不可用。可稍后重试或手动记录。',
    'INVALID_MODEL_OUTPUT' || 'INVALID_REQUEST' => '识别结果不可用，未应用。可重试或手动记录。',
    _ => '联网识别失败。已保留图片，可重试或手动记录。',
  };

  static Map<String, dynamic> _copy(dynamic value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  static List<dynamic> _copyList(dynamic value) =>
      jsonDecode(jsonEncode(value)) as List;
  static String _stateMessage(String? code, String state) => switch (code) {
    'NO_FOOD' => '没有找到可确认的食物。可换图或手动记录。',
    'PROVIDER_TIMEOUT' => '模拟等待超时。已保留图片，可继续手动记录。',
    'QUOTA_EXCEEDED' => '模拟额度错误。可继续手动记录。',
    'RESULT_INVALID' => '模拟结果结构无效，未写入草稿。',
    _ when state == 'cancelled' => '已取消，不会自动重试。',
    _ => '真实图片识别尚未接入，可继续手动记录。',
  };
  void _mutate(void Function(MealDraftV2) action) {
    try {
      action(_draft!);
      setState(() {});
    } catch (_) {
      setState(() => _message = '这项修改不符合份量或结构规则，已保留原内容。');
    }
  }

  Future<void> _editName(String id, String field, String current) async {
    final c = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改名称'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    c.dispose();
    if (value != null && value.isNotEmpty) {
      _mutate((d) => d.editFact(id, field, value));
    }
  }

  Future<void> _setIntake(String id) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('我实际吃了多少？'),
              subtitle: Text('购买数量不会再次相乘'),
            ),
            for (final item in const [
              ('0.5:bowl', '半碗'),
              ('1:bowl', '一碗'),
              ('2:bowl', '两碗'),
              ('0.5:serving', '半份'),
              ('1:serving', '一份'),
              ('none', '没吃'),
              ('unknown', '不确定'),
              ('custom', '自定义数值'),
            ])
              ListTile(
                title: Text(item.$2),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    );
    if (value == null) return;
    if (value == 'custom') {
      await _setCustomIntake(id);
    } else if (value == 'unknown') {
      _mutate((d) => d.setIntake(id, basis: 'unknown'));
    } else if (value == 'none') {
      _mutate(
        (d) => d.setIntake(id, basis: 'personal_consumed', notEaten: true),
      );
    } else {
      final parts = value.split(':');
      _mutate(
        (d) => d.setIntake(
          id,
          basis: 'personal_consumed',
          portion: {
            'value': double.parse(parts[0]),
            'unit': parts[1],
            'band': 'unknown',
          },
        ),
      );
    }
  }

  Future<void> _setCustomIntake(String id) async {
    final controller = TextEditingController();
    var unit = 'g';
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('输入我实际吃的量'),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '数值'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: unit,
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('g')),
                  DropdownMenuItem(value: 'ml', child: Text('ml')),
                  DropdownMenuItem(value: 'bowl', child: Text('碗')),
                  DropdownMenuItem(value: 'cup', child: Text('杯')),
                  DropdownMenuItem(value: 'serving', child: Text('份')),
                ],
                onChanged: (value) => setDialogState(() => unit = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final number = double.tryParse(controller.text);
                if (number != null) Navigator.pop(context, (number, unit));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) {
      _mutate(
        (d) => d.setIntake(
          id,
          basis: 'personal_consumed',
          portion: {'value': result.$1, 'unit': result.$2, 'band': 'unknown'},
        ),
      );
    }
  }

  Future<void> _addComponent(String productId) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加组成'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: '例如：米饭'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.isNotEmpty) {
      _mutate((d) => d.addComponent(productId, name));
    }
  }

  Future<void> _save() async {
    if (_draft == null || _saved) return;
    setState(() => _busy = true);
    try {
      final state = context.read<AppState>();
      if (widget.mealId == null) {
        await state.saveRecognitionMeal(
          _draft!,
          mealType: _mealType(DateTime.now().hour),
          timestamp: DateTime.now(),
        );
      } else {
        final old = state.mealById(widget.mealId!)!;
        final edited = _draft!.toMeal(
          mealType: old.mealType,
          timestamp: old.timestamp,
          estimator: state.servingEstimator,
          dailyIntake: state.dailyIntake,
          policyVersion: state.guidelines?.version,
          knowledgeVersion: state.guidelines == null
              ? null
              : 'guidelines-${state.guidelines!.version}:food_exchange',
        );
        await state.saveMeal(
          MealRecord(
            mealId: edited.mealId,
            mealType: edited.mealType,
            timestamp: edited.timestamp,
            merchant: old.merchant,
            dishes: edited.dishes,
            portionsTotal: edited.portionsTotal,
            completionRate: edited.completionRate,
            sodiumLevel: edited.sodiumLevel,
            recognitionSnapshot: edited.recognitionSnapshot,
          ),
          source: 'recognition_v2_edit',
        );
      }
      _saved = true;
      if (mounted) {
        final meal = state.mealById(_draft!.draftId)!;
        final contributions = meal.recognitionSnapshot!['contributions'] as Map;
        final known = contributions.values
            .where((value) => (value as Map)['portions'] != null)
            .length;
        final unknown = contributions.length - known;
        final feedback = known == 0
            ? '已保存，本餐 $unknown 项未知未计入；今日结构未变化'
            : '已保存，本餐 $known 项已计入今日结构；$unknown 项未知未计入';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(feedback)));
        context.go('/home');
      }
    } on FormatException {
      if (mounted) setState(() => _message = '请至少选择一项食物。未知份量也可以保存。');
    } catch (_) {
      if (mounted) setState(() => _message = '保存失败，未写入不完整数据。请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    final f = _workingImage;
    if (f != null) {
      f.exists().then((v) async {
        if (v) await f.delete();
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _draft?.draft;
    return Scaffold(
      appBar: PixelAppBar(title: widget.mealId == null ? '图片记餐' : '编辑识别记录'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kDebugMode)
            const PixelPanel(
              color: Color(0xffffe4a8),
              child: Text('开发模拟 · 固定样例，不代表图片真实识别结果'),
            ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'screenshot', label: Text('订单截图')),
              ButtonSegment(value: 'food_photo', label: Text('餐食实拍')),
            ],
            selected: {_sourceKind},
            onSelectionChanged: (s) {
              _cancellation?.cancel();
              setState(() {
                _sourceKind = s.first;
                _busy = false;
                _request = null;
                _cloudResult = null;
                _cloudSelected.clear();
              });
            },
          ),
          if (widget.mealId == null) ...[
            const SizedBox(height: 12),
            if (_workingImage != null)
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.file(_workingImage!, fit: BoxFit.cover),
                  ),
                  if (_covered)
                    Positioned(
                      left: 24,
                      right: 24,
                      top: 50,
                      child: Container(height: 48, color: Colors.black),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text('从相册选择'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                ),
                if (_workingImage != null)
                  OutlinedButton(
                    onPressed: () => setState(() => _cropped = !_cropped),
                    child: Text(_cropped ? '恢复完整范围' : '裁掉四周'),
                  ),
                if (_workingImage != null)
                  OutlinedButton(
                    onPressed: () => setState(() => _covered = !_covered),
                    child: Text(_covered ? '移除遮盖' : '遮盖隐私区域'),
                  ),
              ],
            ),
            if (_workingImage != null)
              const Text(
                '裁剪/遮盖目前仅是本地预览标记，不会改写图片字节或上传。'
                '这张临时副本离开后删除，不会删除相册原图。多图功能暂未开放。',
              ),
            if (kDebugMode && _workingImage != null) ...[
              const SizedBox(height: 8),
              DropdownButton<MockRecognitionScenario>(
                value: _scenario,
                isExpanded: true,
                items: MockRecognitionScenario.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text('模拟：${v.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _scenario = v!),
              ),
              FilledButton(
                onPressed: _busy ? null : _recognize,
                child: Text(_busy ? '处理中' : '运行模拟识别'),
              ),
            ],
            if (_workingImage != null)
              FilledButton(
                onPressed: _busy ? null : _recognizeCloud,
                child: Text(_busy ? '识别中…' : '联网智能识别'),
              ),
            if (_busy)
              OutlinedButton(
                onPressed: () {
                  _cancellation?.cancel();
                  setState(() {
                    _busy = false;
                    _request = null;
                    _message = '已取消识别。图片和草稿仍保留在本机。';
                  });
                },
                child: const Text('取消识别'),
              ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!),
            ),
          if (data != null)
            for (final Map product in data['products'])
              _ProductCard(
                product: product,
                onMutate: _mutate,
                onEditName: _editName,
                onIntake: _setIntake,
                onAddComponent: _addComponent,
              ),
          if (_cloudResult != null)
            for (final Map product in _cloudResult!['products'])
              _CloudProductCard(
                product: product,
                selected: _cloudSelected.contains(product['productId']),
                onChanged: (value) => setState(() {
                  final id = product['productId'] as String;
                  value ? _cloudSelected.add(id) : _cloudSelected.remove(id);
                }),
              ),
          if (data == null)
            OutlinedButton.icon(
              onPressed: () => context.push('/manual_add'),
              icon: const Icon(Icons.edit_note),
              label: const Text('不使用识别，手动记餐'),
            ),
        ],
      ),
      bottomNavigationBar: data == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('保存到本机'),
                ),
              ),
            ),
    );
  }

  static String _mealType(int h) => h < 10
      ? 'breakfast'
      : h < 15
      ? 'lunch'
      : h < 21
      ? 'dinner'
      : 'snack';
}

class _CloudProductCard extends StatelessWidget {
  const _CloudProductCard({
    required this.product,
    required this.selected,
    required this.onChanged,
  });
  final Map product;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final status = product['purchaseStatus'] as String;
    final name = product['displayName']['value'] as String? ?? '未知商品';
    final components = (product['components'] as List? ?? const []).cast<Map>();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          CheckboxListTile(
            value: selected,
            onChanged: (value) => onChanged(value ?? false),
            title: Text(name),
            subtitle: Text(
              '${_status(status)} · ${_confidence(product['confidence'])}${status == 'candidate' || status == 'recommended' ? ' · 默认不计入' : ''}',
            ),
          ),
          for (final component in components)
            ListTile(
              dense: true,
              title: Text(component['name']['value'] ?? '未知组成'),
              subtitle: Text(
                '${component['componentType']} · ${_confidence(component['confidence'])} · 需确认后计入',
              ),
            ),
        ],
      ),
    );
  }

  static String _status(String value) => switch (value) {
    'purchased' => '已购',
    'candidate' => '候选',
    'recommended' => '推荐项',
    _ => '购买状态未知',
  };
  static String _confidence(dynamic value) => switch (value?['grade']) {
    'high' => '高置信',
    'candidate' => '候选置信',
    _ => '置信未知',
  };
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onMutate,
    required this.onEditName,
    required this.onIntake,
    required this.onAddComponent,
  });
  final Map product;
  final void Function(void Function(MealDraftV2)) onMutate;
  final Future<void> Function(String, String, String) onEditName;
  final Future<void> Function(String) onIntake;
  final Future<void> Function(String) onAddComponent;
  @override
  Widget build(BuildContext context) {
    final id = product['productId'] as String,
        name = product['displayName']['value'] as String? ?? '未知商品';
    final components = (product['components'] as List).cast<Map>();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: product['selected'] == true,
              onChanged: (v) => onMutate((d) {
                d.select(id, v!);
                if (v &&
                    product['displayName']['reviewStatus'] == 'unreviewed') {
                  d.reviewFact(id, 'displayName');
                }
              }),
              title: Text(name),
              subtitle: Text(
                '来源：${_source(product['displayName']['provenance'])} · ${product['displayName']['reviewStatus'] == 'accepted' ? '已确认' : '待确认'}',
              ),
              secondary: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => onEditName(id, 'displayName', name),
              ),
            ),
            Row(
              children: [
                const Text('计算方式：'),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: product['nutritionMode'],
                    items: const [
                      DropdownMenuItem(value: 'unknown', child: Text('营养未知')),
                      DropdownMenuItem(value: 'aggregate', child: Text('按整体')),
                      DropdownMenuItem(value: 'children', child: Text('按组成')),
                    ],
                    onChanged: (v) => onMutate((d) => d.setMode(id, v!)),
                  ),
                ),
              ],
            ),
            if (product['nutritionMode'] == 'aggregate')
              TextButton(
                onPressed: () => onIntake(id),
                child: Text(_intake(product['calculation'])),
              ),
            for (final c in components)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 8),
                leading: Checkbox(
                  value: c['selected'] == true,
                  onChanged: (v) => onMutate((d) {
                    d.select(c['componentId'], v!);
                    if (v && c['name']['reviewStatus'] == 'unreviewed') {
                      d.reviewFact(c['componentId'], 'name');
                    }
                  }),
                ),
                title: Text(c['name']['value'] ?? '未知组成'),
                subtitle: Text(
                  '${_source(c['name']['provenance'])} · ${_intake(c['calculation'])}',
                ),
                onTap: () => onIntake(c['componentId']),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      onEditName(
                        c['componentId'],
                        'name',
                        c['name']['value'] ?? '',
                      );
                    } else {
                      onMutate((d) => d.removeComponent(id, c['componentId']));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('修改名称')),
                    PopupMenuItem(value: 'delete', child: Text('删除组成')),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => onAddComponent(id),
              icon: const Icon(Icons.add),
              label: const Text('添加组成'),
            ),
          ],
        ),
      ),
    );
  }

  static String _source(dynamic v) => switch (v) {
    'photo_observed' => '照片可见',
    'text_observed' => '截图文字',
    'name_inference' => '名称推测',
    'user_input' => '用户修改',
    _ => '未知',
  };
  static String _intake(Map c) {
    if (c['notEaten']['value'] == true) return '我没吃';
    final p = c['portion']['value'];
    if (p == null) return '填写我实际吃多少';
    return '我吃了 ${p['value']} ${p['unit']}';
  }
}
