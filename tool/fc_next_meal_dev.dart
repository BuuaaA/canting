import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:flutter/material.dart';

/// Flutter desktop-only development host. The token is entered into an
/// obscured field, used in memory for one request, then cleared. The normal
/// app entry remains disabled by default; this host is not a phone check.
void main() => runApp(const FcNextMealDevApp());

class FcNextMealDevApp extends StatelessWidget {
  const FcNextMealDevApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FC recommendation dev probe',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const FcNextMealDevPage(),
  );
}

class FcNextMealDevPage extends StatefulWidget {
  const FcNextMealDevPage({super.key});

  @override
  State<FcNextMealDevPage> createState() => _FcNextMealDevPageState();
}

class _FcNextMealDevPageState extends State<FcNextMealDevPage> {
  final _tokenController = TextEditingController();
  String _status = '输入短期 FC Bearer 后点击联调';
  bool _busy = false;

  @override
  void dispose() {
    _tokenController.clear();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _status = '未提供凭据');
      return;
    }
    setState(() {
      _busy = true;
      _status = '请求中…';
    });
    final remote = FcNextMealRemote(
      configuration: FcNextMealConfiguration(
        endpoint: Uri.parse(
          'https://cantingan-proxy-lutwihtgyl.cn-beijing.fcapp.run',
        ),
        enabled: true,
        credentialAccess: (ref, use) async => use(token),
      ),
    );
    try {
      final result = await NextMealRecommendationService(
        remoteWithBudget: remote.callWithBudget,
      ).nextMeal(_sampleRequest());
      if (!mounted) return;
      setState(() {
        _status =
            '${result.source}/${result.status}/${result.reasonCode} · '
            '${result.suggestions.length} items';
      });
    } catch (_) {
      if (mounted) setState(() => _status = '联调异常，已结束');
    } finally {
      _tokenController.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  NextMealRequest _sampleRequest() {
    final now = DateTime.now();
    final date = now.toIso8601String().substring(0, 10);
    final start = now.subtract(const Duration(days: 6));
    final startDate = start.toIso8601String().substring(0, 10);
    return NextMealRequest(
      requestId: 'desktop-dev-probe',
      today: TodayIntakeStats(
        date: date,
        revision: 0,
        categories: const {},
        completeness: 'complete',
      ),
      rolling7d: Rolling7dIntakeStats(
        startDate: startDate,
        endDate: date,
        revision: 0,
        days: const [],
        averages: const {},
        foodVarietyAverage: null,
        foodVarietyDenominator: null,
        fishCount: null,
        fishGrams: null,
        nutGrams: null,
        dairyMetDays: 0,
        dairyKnownDays: 0,
        dairyUnknownDays: 7,
        soyMetDays: 0,
        soyKnownDays: 0,
        soyUnknownDays: 7,
        fishCompleteness: 'unknown',
        fishCountCompleteness: 'unknown',
        nutCompleteness: 'unknown',
      ),
      nextMealType: 'dinner',
      availablePlatforms: const [],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FC development probe')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('短期凭据只在内存使用，不写入文件或日志。'),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'FC Bearer token',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _probe,
                child: Text(_busy ? '请求中…' : '开始联调'),
              ),
              const SizedBox(height: 12),
              Text(_status),
            ],
          ),
        ),
      ),
    ),
  );
}
