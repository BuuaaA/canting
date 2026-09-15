import 'dart:convert';
import 'dart:io';

import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/next_meal_recommendation.dart';

import '../test/services/next_meal_recommendation_test.dart' as fixtures;

/// Desktop-only development probe. Read a short-lived token from stdin, use it
/// for one request, and never print or persist it. This is not a phone or
/// production entrypoint; the normal app entry remains disabled by default.
Future<void> main() async {
  stderr.writeln('Paste a short-lived FC Bearer token on stdin; it will not be echoed by this tool.');
  final token = stdin.readLineSync()?.trim() ?? '';
  if (token.isEmpty) {
    stderr.writeln('No token supplied.');
    exitCode = 2;
    return;
  }

  final remote = FcNextMealRemote(
    configuration: FcNextMealConfiguration(
      endpoint: Uri.parse(
        'https://cantingan-proxy-lutwihtgyl.cn-beijing.fcapp.run',
      ),
      enabled: true,
      credentialAccess: (ref, use) async => use(token),
    ),
  );
  final result = await NextMealRecommendationService(remote: remote.call)
      .nextMeal(fixtures.request());
  stdout.writeln(jsonEncode({
    'source': result.source,
    'status': result.status,
    'reasonCode': result.reasonCode,
    'suggestionCount': result.suggestions.length,
    'dishNames': result.suggestions.map((item) => item.dishName).toList(),
  }));
}
