import 'dart:convert';
import 'dart:io';

import 'package:canting/core/models/meal_draft_v2.dart';
import 'package:canting/services/recognition_adapter.dart';
import 'package:canting/services/recognition_configuration.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('dev-docs/recognition-v2/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final contract = RecognitionContract(_read('recognition.schema'));
  final examples = _read('examples');
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(jsonEncode(examples[name])) as Map<String, dynamic>;
  Map<String, dynamic> config() => fixture('provider')..['mode'] = 'mock';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fixed mock scenarios are explicit, simulated, and have no usage',
    () async {
      final adapter = RecognitionAdapter(contract);
      final cases = {
        MockRecognitionScenario.success: ['review', null],
        MockRecognitionScenario.noFood: ['empty_food', 'NO_FOOD'],
        MockRecognitionScenario.invalidStructure: ['error', 'RESULT_INVALID'],
        MockRecognitionScenario.quotaExceeded: ['error', 'QUOTA_EXCEEDED'],
        MockRecognitionScenario.cancelled: ['cancelled', null],
      };
      for (final entry in cases.entries) {
        final request = fixture('request');
        if (entry.key == MockRecognitionScenario.noFood) {
          request['sourceKind'] = 'food_photo';
        }
        final response = await adapter.recognize(
          request,
          config(),
          scenario: entry.key,
          mockResult: fixture('screenshot'),
          mockEmptyResult: fixture('empty_food'),
        );
        expect(response['state'], entry.value[0]);
        expect(response['errorCode'], entry.value[1]);
        expect(response['simulated'], true);
        expect(response['usage'], isNull);
        expect(response['draftId'], request['draftId']);
        expect(response['requestId'], request['requestId']);
        expect(response['draftRevision'], request['draftRevision']);
        expect(response['assetIds'], [request['assets'][0]['assetId']]);
      }
    },
  );

  test(
    'timeout and cancellation finish once and late work cannot apply',
    () async {
      final adapter = RecognitionAdapter(contract);
      final request = fixture('request');
      final timedOut = await adapter.recognize(
        request,
        config(),
        scenario: MockRecognitionScenario.timeout,
        timeout: const Duration(milliseconds: 5),
        mockResult: fixture('screenshot'),
      );
      expect(timedOut['errorCode'], 'PROVIDER_TIMEOUT');
      expect(contract.canApply(request, timedOut), false);

      final cancellation = RecognitionCancellation();
      final pending = adapter.recognize(
        request,
        config(),
        cancellation: cancellation,
        timeout: const Duration(seconds: 1),
        mockDelay: const Duration(milliseconds: 50),
        mockResult: fixture('screenshot'),
      );
      cancellation.cancel();
      cancellation.cancel();
      final cancelled = await pending;
      expect(cancelled['state'], 'cancelled');
      expect(contract.canApply(request, cancelled, cancelled: true), false);
    },
  );

  test('invalid or stale responses never become a domain draft', () async {
    final request = fixture('request');
    final adapter = RecognitionAdapter(contract);
    final invalid = await adapter.recognize(
      request,
      config(),
      scenario: MockRecognitionScenario.invalidStructure,
      mockResult: fixture('screenshot'),
    );
    expect(
      () => MealDraftV2.fromResponse(contract, request, invalid),
      throwsFormatException,
    );
    final valid = await adapter.recognize(
      request,
      config(),
      mockResult: fixture('screenshot'),
    );
    request['draftRevision'] = 1;
    expect(contract.canApply(request, valid), false);
    expect(
      () => MealDraftV2.fromResponse(contract, request, valid),
      throwsFormatException,
    );
  });

  test(
    'external settings persist without secret and never call credentials',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final state = RecognitionConfiguration(contract, prefs);
      const fakeSecret = 'FAKE_N2_KEY_DO_NOT_USE';
      var credentialCalls = 0;
      final adapter = RecognitionAdapter(
        contract,
        credentials: (reference, use) async {
          credentialCalls++;
          await use(fakeSecret);
        },
      );
      final external = RecognitionConfiguration.defaults()
        ..addAll({
          'mode': 'external',
          'endpoint': 'https://example.invalid/recognize',
          'model': 'not-connected-model',
          'credentialRef': 'credential:n2-placeholder',
          'delivery': 'byok',
          'region': 'not-connected-region',
        });
      state.setTemporaryCredential(fakeSecret);
      expect(state.maskedCredential, isNot(contains(fakeSecret)));
      await state.save(external);
      expect(state.hasTemporaryCredential, false);
      expect(state.credentialStatus, 'not_configured');
      expect(
        prefs.getString(RecognitionConfiguration.storageKey),
        isNot(contains(fakeSecret)),
      );

      final restarted = RecognitionConfiguration(contract, prefs);
      expect(restarted.load(), external);
      expect(restarted.hasTemporaryCredential, false);
      final response = await adapter.recognize(
        fixture('request'),
        restarted.load(),
      );
      expect(response['state'], 'unavailable');
      expect(response['simulated'], false);
      expect(credentialCalls, 0);
    },
  );

  test('cancel, leave, and clear discard temporary input', () async {
    final prefs = await SharedPreferences.getInstance();
    final state = RecognitionConfiguration(contract, prefs);
    state.setTemporaryCredential('FAKE_CANCELLED_KEY');
    state.clearTemporaryCredential();
    expect(state.hasTemporaryCredential, false);
    state.setTemporaryCredential('FAKE_LEFT_PAGE_KEY');
    await state.clear();
    expect(state.hasTemporaryCredential, false);
    expect(prefs.containsKey(RecognitionConfiguration.storageKey), false);
  });

  test(
    'validation and storage failures always clear temporary input',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final invalid = RecognitionConfiguration(contract, prefs)
        ..setTemporaryCredential('FAKE_INVALID_KEY');
      await expectLater(invalid.save({'mode': 'bad'}), throwsFormatException);
      expect(invalid.hasTemporaryCredential, false);

      final failedWrite = RecognitionConfiguration(
        contract,
        prefs,
        (_, _) async => false,
      )..setTemporaryCredential('FAKE_WRITE_FAILURE_KEY');
      await expectLater(
        failedWrite.save(RecognitionConfiguration.defaults()),
        throwsStateError,
      );
      expect(failedWrite.hasTemporaryCredential, false);
    },
  );
}
