import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'next_meal_recommendation.dart';
import 'recognition_adapter.dart';

typedef FcNextMealTransport = Future<FcNextMealResponse> Function(
  Uri endpoint,
  Map<String, String> headers,
  String body,
);

class FcNextMealHttpDiagnostic {
  const FcNextMealHttpDiagnostic({
    required this.method,
    required this.host,
    required this.path,
    required this.statusCode,
    this.callbackLength,
    this.headerLength,
    this.credentialConsistent,
    this.hasLeadingBearer,
    this.hasQuotes,
    this.hasEdgeWhitespace,
    this.hasPlusSlashPadding,
    this.responseLayer,
    this.requestId,
    this.errorCode,
    this.contentType,
    this.responseLength,
    this.errorType,
    this.errorMessage,
  });

  final String method;
  final String host;
  final String path;
  final int statusCode;
  final int? callbackLength;
  final int? headerLength;
  final bool? credentialConsistent;
  final bool? hasLeadingBearer;
  final bool? hasQuotes;
  final bool? hasEdgeWhitespace;
  final bool? hasPlusSlashPadding;
  final String? responseLayer;
  final String? requestId;
  final String? errorCode;
  final String? contentType;
  final int? responseLength;
  final String? errorType;
  final String? errorMessage;
}

typedef FcNextMealHttpObserver = void Function(FcNextMealHttpDiagnostic event);

class FcNextMealResponse {
  const FcNextMealResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// Runtime-only configuration for the optional FC gateway.
///
/// [enabled] remains false for production until a formally approved secure
/// credential provider is supplied. No token is persisted or logged here.
class FcNextMealConfiguration {
  const FcNextMealConfiguration({
    required this.endpoint,
    required this.enabled,
    this.credentialRef = 'bailian-recommendation-fc',
    this.credentialAccess,
    this.transport,
    this.httpObserver,
  });

  final Uri? endpoint;
  final bool enabled;
  final String credentialRef;
  final CredentialAccess? credentialAccess;
  final FcNextMealTransport? transport;
  final FcNextMealHttpObserver? httpObserver;

  bool get isUsable =>
      enabled &&
      endpoint != null &&
      endpoint!.scheme == 'https' &&
      endpoint!.host.isNotEmpty &&
      endpoint!.userInfo.isEmpty &&
      !endpoint!.hasQuery &&
      !endpoint!.hasFragment &&
      credentialAccess != null;
}

/// Minimal POST /recommend adapter for the user-managed FC proxy.
/// The request body contains only the serialized local summary prompt.
class FcNextMealRemote {
  FcNextMealRemote({
    required this.configuration,
    this.client,
    this.transport,
    this.timeout = nextMealCallBudget,
  });

  final FcNextMealConfiguration configuration;
  final HttpClient? client;
  final FcNextMealTransport? transport;
  final Duration timeout;

  Future<String> call(NextMealRequest request) async {
    return callWithBudget(request, timeout);
  }

  /// Executes with a caller-owned remaining budget. This is used by AppState
  /// so a retry cannot silently restart a fresh adapter timeout window.
  Future<String> callWithBudget(
    NextMealRequest request,
    Duration budget,
  ) async {
    final stopwatch = Stopwatch()..start();
    Duration remaining() {
      final left = budget - stopwatch.elapsed;
      return left.isNegative ? Duration.zero : left;
    }

    if (!configuration.isUsable) {
      throw const NextMealRemoteException('unconfigured');
    }
    String? callbackToken;
    try {
      await configuration
          .credentialAccess!(configuration.credentialRef, (secret) async {
            callbackToken = secret;
          })
          .timeout(remaining());
    } on TimeoutException {
      throw const NextMealRemoteException('timeout');
    }
    if (remaining() <= Duration.zero) {
      throw const NextMealRemoteException('timeout');
    }
    if (callbackToken == null || callbackToken!.isEmpty) {
      throw const NextMealRemoteException('unauthorized', 401);
    }

    final headerToken = callbackToken!;
    final endpoint = configuration.endpoint!.resolve('/recommend');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $headerToken',
    };
    final requestBody = jsonEncode({'prompt': jsonEncode(request.toJson())});
    final activeTransport = transport ?? configuration.transport;
    if (activeTransport != null) {
      final response = await activeTransport(
        endpoint,
        headers,
        requestBody,
      ).timeout(remaining());
      configuration.httpObserver?.call(
        FcNextMealHttpDiagnostic(
          method: 'POST',
          host: endpoint.host,
          path: endpoint.path,
          statusCode: response.statusCode,
          callbackLength: callbackToken?.length,
          headerLength: headerToken.length,
          credentialConsistent: callbackToken == headerToken,
          hasLeadingBearer: headerToken.startsWith('Bearer '),
          hasQuotes: headerToken.contains('"') || headerToken.contains("'"),
          hasEdgeWhitespace: headerToken.trim() != headerToken,
          hasPlusSlashPadding:
              headerToken.contains('+') &&
              headerToken.contains('/') &&
              headerToken.endsWith('='),
          responseLayer: 'application_or_unknown',
        ),
      );
      _throwForStatus(response.statusCode);
      if (response.body.trim().isEmpty) {
        throw const NextMealRemoteException('invalid_json');
      }
      jsonDecode(response.body);
      return response.body;
    }

    final http = client ?? HttpClient();
    HttpClientRequest? httpRequest;
    try {
      httpRequest = await http.postUrl(endpoint).timeout(remaining());
      httpRequest.headers
        ..set(
          HttpHeaders.contentTypeHeader,
          headers[HttpHeaders.contentTypeHeader]!,
        )
        ..set(
          HttpHeaders.authorizationHeader,
          headers[HttpHeaders.authorizationHeader]!,
        );
      final encodedBody = utf8.encode(requestBody);
      httpRequest.contentLength = encodedBody.length;
      httpRequest.add(encodedBody);
      final response = await httpRequest.close().timeout(remaining());
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(remaining());
      configuration.httpObserver?.call(
        FcNextMealHttpDiagnostic(
          method: 'POST',
          host: endpoint.host,
          path: endpoint.path,
          statusCode: response.statusCode,
          callbackLength: callbackToken?.length,
          headerLength: headerToken.length,
          credentialConsistent: callbackToken == headerToken,
          hasLeadingBearer: headerToken.startsWith('Bearer '),
          hasQuotes: headerToken.contains('"') || headerToken.contains("'"),
          hasEdgeWhitespace: headerToken.trim() != headerToken,
          hasPlusSlashPadding:
              headerToken.contains('+') &&
              headerToken.contains('/') &&
              headerToken.endsWith('='),
          responseLayer: _responseLayer(response.headers),
          requestId: _requestId(response.headers),
          errorCode: _safeErrorCode(body),
          contentType: response.headers.contentType?.mimeType,
          responseLength: utf8.encode(body).length,
          errorType: _safeErrorType(body),
          errorMessage: _safeErrorMessage(body),
        ),
      );
      _throwForStatus(response.statusCode);
      if (body.trim().isEmpty) {
        throw const NextMealRemoteException('invalid_json');
      }
      // Validate that the gateway returns JSON here; schema validation remains
      // in NextMealRecommendationService so the same rules cover all callers.
      jsonDecode(body);
      return body;
    } on TimeoutException {
      httpRequest?.abort();
      throw const NextMealRemoteException('timeout');
    } on SocketException {
      throw const NextMealRemoteException('network_error');
    } on FormatException {
      // Preserve FormatException so NextMealRecommendationService can apply
      // its single bounded retry consistently for every remote transport.
      rethrow;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  static void _throwForStatus(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw NextMealRemoteException(_reasonForStatus(statusCode), statusCode);
    }
  }

  static String _reasonForStatus(int status) {
    if (status == 401 || status == 403) return 'unauthorized';
    if (status == 429) return 'rate_limited';
    if (status >= 500) return 'server_error';
    return 'remote_http_error';
  }

  static String? _requestId(HttpHeaders headers) {
    for (final name in [
      'x-fc-request-id',
      'x-request-id',
      'x-serverless-request-id',
      'x-fc-trace-id',
    ]) {
      final value = headers.value(name);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String _responseLayer(HttpHeaders headers) {
    final server = headers.value('server')?.toLowerCase() ?? '';
    if (server.contains('werkzeug') ||
        server.contains('gunicorn') ||
        server.contains('uvicorn') ||
        server.contains('flask')) {
      return 'flask_application';
    }
    if (headers.value('x-fc-status') != null ||
        server.contains('aliyun') ||
        server.contains('functioncompute') ||
        server.contains('serverless')) {
      return 'fc_platform';
    }
    return 'unknown';
  }

  static String? _safeErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final value =
          decoded['code'] ??
          decoded['errorCode'] ??
          decoded['error_code'] ??
          decoded['error'];
      const allowed = {
        'AUTH_REQUIRED',
        'UNAUTHORIZED',
        'INVALID_TOKEN',
        'BAD_REQUEST',
        'INVALID_REQUEST',
        'METHOD_NOT_ALLOWED',
        'NOT_FOUND',
        'PROVIDER_AUTH_FAILED',
      };
      if (value is String && allowed.contains(value)) return value;
      final text = decoded.values
          .whereType<String>()
          .map((value) => value.toLowerCase().replaceAll('_', ' '))
          .join(' ');
      if (text.contains('unauthorized') || text.contains('invalid token')) {
        return 'UNAUTHORIZED';
      }
      if (text.contains('method not allowed')) return 'METHOD_NOT_ALLOWED';
      if (text.contains('not found')) return 'NOT_FOUND';
      if (text == 'prompt too long') return 'PROMPT_TOO_LONG';
      if (text == 'upstream unavailable') return 'UPSTREAM_UNAVAILABLE';
      if (text == 'provider unavailable') return 'PROVIDER_UNAVAILABLE';
      if (text.contains('bad request') ||
          text.contains('invalid request') ||
          text.contains('invalid input') ||
          text.contains('invalid payload') ||
          text.contains('missing prompt') ||
          text.contains('missing field') ||
          text.contains('required field') ||
          text.contains('invalid json') ||
          text.contains('schema')) {
        return 'BAD_REQUEST';
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  static String _safeErrorType(String body) {
    final code = _safeErrorCode(body);
    if (code == 'AUTH_REQUIRED' ||
        code == 'UNAUTHORIZED' ||
        code == 'INVALID_TOKEN' ||
        code == 'PROVIDER_AUTH_FAILED') {
      return 'auth_error';
    }
    if (code == 'BAD_REQUEST' ||
        code == 'INVALID_REQUEST' ||
        code == 'PROMPT_TOO_LONG') {
      return 'validation_error';
    }
    if (code == 'METHOD_NOT_ALLOWED') return 'method_error';
    if (code == 'PROVIDER_UNAVAILABLE' || code == 'UPSTREAM_UNAVAILABLE') {
      return 'provider_error';
    }
    if (code == 'NOT_FOUND') return 'not_found';
    if (body.trim().isEmpty) return 'empty_error';
    if (body.trimLeft().startsWith('<')) return 'html_error_page';
    return 'json_error';
  }

  static String _safeErrorMessage(String body) {
    final code = _safeErrorCode(body);
    const messages = {
      'AUTH_REQUIRED': 'authentication required',
      'UNAUTHORIZED': 'unauthorized',
      'INVALID_TOKEN': 'invalid token',
      'PROVIDER_AUTH_FAILED': 'provider authentication failed',
      'BAD_REQUEST': 'bad request',
      'INVALID_REQUEST': 'invalid request',
      'METHOD_NOT_ALLOWED': 'method not allowed',
      'NOT_FOUND': 'not found',
      'PROMPT_TOO_LONG': 'prompt too long',
      'UPSTREAM_UNAVAILABLE': 'upstream unavailable',
      'PROVIDER_UNAVAILABLE': 'provider unavailable',
    };
    final mapped = messages[code];
    if (mapped != null) return mapped;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = decoded.values
            .whereType<String>()
            .map((value) => value.toLowerCase())
            .join(' ');
        if (text.contains('invalid payload')) return 'invalid request payload';
        if (text.contains('invalid json')) return 'invalid JSON request';
        if (text.contains('missing prompt') ||
            text.contains('missing field') ||
            text.contains('required field')) {
          return 'required request field missing';
        }
        if (text.contains('schema')) return 'request schema rejected';
        if (text.contains('content-type')) return 'content type rejected';
        if (text.contains('parameter')) return 'request parameter rejected';
      }
    } on FormatException {
      // Fall through to the generic safe classification.
    }
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<')) {
      final title = RegExp(
        r'<title[^>]*>\s*(.*?)\s*</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(trimmed)?.group(1);
      final normalized = title?.replaceAll(RegExp(r'\s+'), ' ').trim();
      const htmlTitles = {
        'bad request': 'bad request',
        'unauthorized': 'unauthorized',
        'forbidden': 'forbidden',
        'not found': 'not found',
        'method not allowed': 'method not allowed',
        'internal server error': 'internal server error',
      };
      return htmlTitles[normalized?.toLowerCase()] ?? 'html error page';
    }
    return body.trim().isEmpty ? 'empty response' : 'json error response';
  }
}
