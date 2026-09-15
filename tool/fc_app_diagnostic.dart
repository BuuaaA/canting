// Debug host for the actual APP. No credential is compiled or persisted.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:canting/main.dart' as app;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

String? _credential;
bool _busy = false;

Iterable<Element> _elements(Element root) sync* {
  yield root;
  final children = <Element>[];
  root.visitChildren(children.add);
  for (final child in children) {
    yield* _elements(child);
  }
}

String _errorSummary(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      for (final key in ['error', 'message', 'code', 'errorCode']) {
        final value = decoded[key];
        if (value is! String) continue;
        final normalized = value.toLowerCase().replaceAll('_', ' ').trim();
        if (const {
          'prompt too long',
          'provider unavailable',
          'upstream unavailable',
          'invalid prompt',
          'prompt required',
          'invalid json',
          'unauthorized',
        }.contains(normalized)) {
          return normalized;
        }
      }
    }
  } catch (_) {
    return 'non JSON error';
  }
  return 'unclassified error';
}

Future<void> main() async {
  if (!kDebugMode) throw StateError('This host requires debug mode');
  await app.runCantingApp(
    nextMealCredentialAccess: (_, use) async {
      await use(_credential ?? '');
    },
  );
  developer.registerExtension('ext.canting.fcDiagnostic', (_, params) async {
    if (_busy) {
      return developer.ServiceExtensionResponse.result('{"busy":true}');
    }
    _busy = true;
    _credential = params['credential'];
    try {
      if (_credential == null || _credential!.isEmpty) {
        return developer.ServiceExtensionResponse.result(
          '{"credentialMissing":true}',
        );
      }
      final result = <String, Object?>{};
      if (params['action'] == 'fixed') {
        final body = params['body']!;
        final decoded = jsonDecode(body);
        if (decoded is! Map ||
            decoded.length != 1 ||
            decoded['prompt'] is! String) {
          return developer.ServiceExtensionResponse.result(
            '{"invalidFixture":true}',
          );
        }
        final bytes = utf8.encode(body);
        final endpoint = Uri.parse(
          const String.fromEnvironment('CANTING_RECOMMEND_ENDPOINT'),
        ).resolve('/recommend');
        final client = HttpClient();
        try {
          final request = await client
              .postUrl(endpoint)
              .timeout(const Duration(seconds: 10));
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $_credential',
          );
          request.contentLength = bytes.length;
          request.add(bytes);
          final response = await request.close().timeout(
            const Duration(seconds: 35),
          );
          final raw = await response
              .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
              .timeout(const Duration(seconds: 5));
          result.addAll({
            'client': 'android_app_HttpClient',
            'method': 'POST',
            'hostPath': '${endpoint.host}${endpoint.path}',
            'requestBytes': bytes.length,
            'promptChars': (decoded['prompt'] as String).length,
            'sha256': sha256.convert(bytes).toString(),
            'status': response.statusCode,
            'responseBytes': raw.length,
            'contentType': response.headers.contentType?.mimeType,
            'requestId': response.headers.value('x-fc-request-id'),
          });
          if (response.statusCode >= 400) {
            result['error'] = _errorSummary(
              utf8.decode(raw, allowMalformed: true),
            );
          } else {
            result['suggestionCount'] =
                (jsonDecode(utf8.decode(raw))['suggestions'] as List).length;
          }
        } finally {
          client.close(force: true);
        }
      } else if (params['action'] == 'page') {
        final root = WidgetsBinding.instance.rootElement!;
        final application = _elements(root)
            .map((e) => e.widget)
            .whereType<app.CantingApp>()
            .first;
        final state = application.appState;
        final recommendation = await state.loadNextMealRecommendation(
          force: true,
        );
        final materialApp = _elements(root)
            .map((e) => e.widget)
            .whereType<MaterialApp>()
            .first;
        final router = materialApp.routerConfig! as GoRouter;
        router.go('/recommendation');
        await Future<void>.delayed(const Duration(seconds: 1));
        final texts = _elements(root)
            .map((e) => e.widget)
            .whereType<Text>()
            .map((t) => t.data ?? '')
            .toSet();
        result.addAll({
          'action': 'actual_app_page',
          'source': recommendation.source,
          'reasonCode': recommendation.reasonCode,
          'suggestionCount': recommendation.suggestions.length,
          'pageOpened':
              router.routeInformationProvider.value.uri.path ==
              '/recommendation',
          'renderedAiDishes': recommendation.source == 'ai'
              ? recommendation.suggestions
                    .where((s) => texts.contains(s.dishName))
                    .map((s) => s.dishName)
                    .toList()
              : <String>[],
        });
      }
      return developer.ServiceExtensionResponse.result(jsonEncode(result));
    } catch (error) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'failureType': error.runtimeType.toString()}),
      );
    } finally {
      _credential = null;
      _busy = false;
    }
  });
}
