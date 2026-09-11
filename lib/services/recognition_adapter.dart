import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'recognition_contract.dart';

abstract final class MealDraftFact {
  static const empty = {
    'value': null,
    'provenance': 'unknown',
    'reviewStatus': 'unreviewed',
    'evidenceRefs': <String>[],
  };
}

enum MockRecognitionScenario {
  success,
  noFood,
  invalidStructure,
  timeout,
  cancelled,
  quotaExceeded,
}

class RecognitionCancellation {
  bool _cancelled = false;
  final Completer<void> _done = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _done.complete();
  }
}

/// Future secure input/injection seam. The trusted transport gets a scoped
/// callback; credentials are never fields of configuration, requests or drafts.
/// N0 never invokes this callback. Platform secure storage/UI belongs later.
typedef CredentialAccess = Future<void> Function(
  String credentialRef,
  Future<void> Function(String secret) use,
);

/// Explicitly selected local fixtures only. Contains no network implementation.
class RecognitionAdapter {
  RecognitionAdapter(this.contract, {this.credentials});
  final RecognitionContract contract;
  final CredentialAccess? credentials;

  Future<Map<String, dynamic>> recognizeCloud({
    required Uri endpoint,
    required String deviceId,
    required Map<String, dynamic> payload,
    required File image,
    String? bearerToken,
    RecognitionCancellation? cancellation,
    Duration timeout = const Duration(seconds: 20),
    HttpClient? client,
  }) async {
    final http = client ?? HttpClient();
    try {
      final boundary = 'canting-${payload['requestId']}';
      final request = await http
          .postUrl(endpoint.resolve('/v1/recognitions'))
          .timeout(timeout);
      request.headers
        ..set(
          HttpHeaders.contentTypeHeader,
          'multipart/form-data; boundary=$boundary',
        )
        ..set('X-Device-Id', deviceId);
      if (bearerToken?.isNotEmpty == true) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      void text(String value) => request.add(utf8.encode(value));
      text(
        '--$boundary\r\nContent-Disposition: form-data; name="payload"\r\n\r\n',
      );
      text(jsonEncode(payload));
      text(
        '\r\n--$boundary\r\nContent-Disposition: form-data; name="images"; filename="meal.jpg"\r\nContent-Type: ${_mime(image.path)}\r\n\r\n',
      );
      await request.addStream(image.openRead());
      text('\r\n--$boundary--\r\n');
      if (cancellation?.isCancelled == true) throw const _Cancelled();
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (cancellation?.isCancelled == true) throw const _Cancelled();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _validateCloudResponse(payload, decoded);
        return decoded;
      }
      final error = decoded['error'] as Map?;
      throw RecognitionHttpException(
        response.statusCode,
        error?['code'] as String? ??
            decoded['errorCode'] as String? ??
            'HTTP_ERROR',
      );
    } on TimeoutException {
      throw const RecognitionHttpException(408, 'PROVIDER_TIMEOUT');
    } on SocketException {
      throw const RecognitionHttpException(0, 'NO_NETWORK');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  static String _mime(String path) => path.toLowerCase().endsWith('.png')
      ? 'image/png'
      : path.toLowerCase().endsWith('.webp')
      ? 'image/webp'
      : 'image/jpeg';

  static void _validateCloudResponse(Map request, Map response) {
    final hashes = (request['assets'] as List)
        .map((a) => a['imageSha256'])
        .toList();
    if (response['schemaVersion'] != 'recognition-n0.3' ||
        response['draftId'] != request['draftId'] ||
        response['requestId'] != request['requestId'] ||
        response['draftRevision'] != request['draftRevision'] ||
        jsonEncode(response['assetHashes']) != jsonEncode(hashes) ||
        response['modelPolicyVersion'] is! String ||
        response['promptVersion'] != 'recognition-prompt-n0.3') {
      throw const FormatException('STALE_OR_INVALID_RESPONSE');
    }
    final state = response['state'];
    final hasResult = state == 'review' || state == 'empty_food';
    if (!['review', 'empty_food', 'unavailable', 'error'].contains(state) ||
        (hasResult != (response['result'] is Map))) {
      throw const FormatException('INVALID_RESPONSE_STATE');
    }
    if (response['result'] case final Map result) {
      if (result['schemaVersion'] != response['schemaVersion'] ||
          result['draftId'] != request['draftId'] ||
          result['requestId'] != request['requestId'] ||
          result['draftRevision'] != request['draftRevision'] ||
          result['modelPolicyVersion'] != response['modelPolicyVersion'] ||
          result['promptVersion'] != response['promptVersion'] ||
          result['products'] is! List) {
        throw const FormatException('INVALID_RESULT_BINDING');
      }
      for (final product in result['products'] as List) {
        if (product is! Map ||
            ![
              'purchased',
              'candidate',
              'recommended',
              'unknown',
            ].contains(product['purchaseStatus']) ||
            product['displayName'] is! Map ||
            product['confidence'] is! Map ||
            product['components'] is! List) {
          throw const FormatException('INVALID_RESULT_STRUCTURE');
        }
      }
    }
  }

  /// Converts the deliberately smaller backend/model contract into the local
  /// editable meal draft. Provider candidates remain unselected.
  Map<String, dynamic> cloudDraft(
    Map<String, dynamic> request,
    Map<String, dynamic> response,
  ) {
    _validateCloudResponse(request, response);
    final source = response['result'] as Map<String, dynamic>;
    Map<String, dynamic> fact(Map value) => {
      'value': value['value'],
      'provenance': switch (value['basis']) {
        'observed' => 'text_observed',
        'inferred' => 'name_inference',
        _ => 'unknown',
      },
      'reviewStatus': 'unreviewed',
      'evidenceRefs': value['evidenceRefs'],
    };
    Map<String, dynamic> emptyCalculation() => {
      'active': false,
      'portionBasis': 'unknown',
      'portion': MealDraftFact.empty,
      'allocationRatio': MealDraftFact.empty,
      'consumedRatio': MealDraftFact.empty,
      'estimateRange': MealDraftFact.empty,
      'notEaten': MealDraftFact.empty,
    };
    final draft = <String, dynamic>{
      'schemaVersion': 'meal-v2.1',
      'draftId': request['draftId'],
      'requestId': request['requestId'],
      'draftRevision': request['draftRevision'],
      'sourceKind': request['sourceKind'],
      'assets': [
        for (final Map asset in request['assets'])
          {
            'assetId': asset['assetId'],
            'hash': asset['imageSha256'],
            'crop': asset['crop'],
            'capturePhase': asset['capturePhase'],
          },
      ],
      'evidence': [
        for (final Map evidence in source['evidence'])
          {
            'evidenceId': evidence['evidenceId'],
            'type': evidence['kind'] == 'ocr_text'
                ? 'text_observed'
                : 'image_inferred',
            'assetId': evidence['assetId'],
            'bbox': evidence['bbox'] ?? [0, 0, 1, 1],
            'textSpan': evidence['text'],
          },
      ],
      'products': [
        for (final Map product in source['products'])
          {
            'productId': product['productId'],
            'selected': false,
            'displayName': fact(product['displayName']),
            'rawName': fact(product['displayName']),
            'purchaseQuantity': {
              'value': null,
              'provenance': 'unknown',
              'reviewStatus': 'unreviewed',
              'evidenceRefs': <String>[],
            },
            'purchaseState': product['purchaseStatus'] == 'purchased'
                ? 'purchased'
                : product['purchaseStatus'] == 'unknown'
                ? 'unknown'
                : 'not_evidenced',
            'nutritionMode': product['nutritionMode'],
            'components': [
              for (final Map component in product['components'])
                {
                  'componentId': component['componentId'],
                  'selected': false,
                  'name': fact(component['name']),
                  'categoryId': MealDraftFact.empty,
                  'calculation': emptyCalculation(),
                  'completeness': 'unknown',
                  'confidence': {
                    'raw': component['confidence']['score'],
                    'calibrated': null,
                    'grade': component['confidence']['grade'],
                  },
                },
            ],
            'calculation': emptyCalculation(),
            'completeness': 'unknown',
            'confidence': {
              'raw': product['confidence']['score'],
              'calibrated': null,
              'grade': product['confidence']['grade'],
            },
            'specifications': <dynamic>[],
          },
      ],
      'modelVersion': source['modelVersion'],
      'promptVersion': source['promptVersion'],
    };
    return contract.draft(draft, fromModel: true);
  }

  Future<Map<String, dynamic>> recognize(
    dynamic input,
    dynamic configuration, {
    Map<String, dynamic>? mockResult,
    Map<String, dynamic>? mockEmptyResult,
    MockRecognitionScenario scenario = MockRecognitionScenario.success,
    RecognitionCancellation? cancellation,
    Duration timeout = const Duration(seconds: 20),
    Duration mockDelay = Duration.zero,
  }) async {
    final request = contract.request(input);
    final config = contract.provider(configuration);
    final simulated = config['mode'] == 'mock';
    if (!simulated) return _response(request, state: 'unavailable');
    if (scenario == MockRecognitionScenario.cancelled ||
        cancellation?.isCancelled == true) {
      return _response(request, state: 'cancelled', simulated: true);
    }
    if (scenario == MockRecognitionScenario.quotaExceeded) {
      return _response(
        request,
        state: 'error',
        simulated: true,
        errorCode: 'QUOTA_EXCEEDED',
      );
    }
    if (scenario == MockRecognitionScenario.invalidStructure) {
      return _response(
        request,
        state: 'error',
        simulated: true,
        errorCode: 'RESULT_INVALID',
      );
    }
    if (scenario == MockRecognitionScenario.timeout) {
      await Future<void>.delayed(timeout);
      if (cancellation?.isCancelled == true) {
        return _response(request, state: 'cancelled', simulated: true);
      }
      return _response(
        request,
        state: 'error',
        simulated: true,
        errorCode: 'PROVIDER_TIMEOUT',
      );
    }

    final fixture = scenario == MockRecognitionScenario.noFood
        ? mockEmptyResult
        : mockResult;
    if (fixture == null) return _response(request, state: 'unavailable');
    final wait = mockDelay;
    final completed = await Future.any<String>([
      Future<void>.delayed(wait).then((_) => 'completed'),
      Future<void>.delayed(timeout).then((_) => 'timeout'),
      if (cancellation != null)
        cancellation.whenCancelled.then((_) => 'cancelled'),
    ]);
    if (completed == 'cancelled') {
      return _response(request, state: 'cancelled', simulated: true);
    }
    if (completed == 'timeout') {
      return _response(
        request,
        state: 'error',
        simulated: true,
        errorCode: 'PROVIDER_TIMEOUT',
      );
    }
    if (cancellation?.isCancelled == true) {
      return _response(request, state: 'cancelled', simulated: true);
    }
    Map<String, dynamic> result;
    try {
      result = contract.draft(fixture, fromModel: true);
    } on FormatException {
      return _response(
        request,
        state: 'error',
        simulated: true,
        errorCode: 'RESULT_INVALID',
      );
    }
    final empty = (result['products'] as List).isEmpty;
    return _response(
      request,
      state: empty ? 'empty_food' : 'review',
      simulated: true,
      result: result,
      errorCode: empty ? 'NO_FOOD' : null,
    );
  }

  Map<String, dynamic> _response(
    Map<String, dynamic> request, {
    required String state,
    bool simulated = false,
    Map<String, dynamic>? result,
    String? errorCode,
  }) => contract.response({
    'schemaVersion': 'recognition-n0.2',
    'draftId': request['draftId'], 'requestId': request['requestId'],
    'draftRevision': request['draftRevision'],
    'assetIds': [for (final Map a in request['assets']) a['assetId']],
    'state': state,
    'simulated': simulated,
    'result': result,
    'errorCode':
        errorCode ?? (state == 'unavailable' ? 'PROVIDER_UNAVAILABLE' : null),
    'usage': null, // Mock execution is not token usage, latency or model cost.
  }, request);
}

class RecognitionHttpException implements Exception {
  const RecognitionHttpException(this.statusCode, this.code);
  final int statusCode;
  final String code;
}

class _Cancelled implements Exception {
  const _Cancelled();
}
