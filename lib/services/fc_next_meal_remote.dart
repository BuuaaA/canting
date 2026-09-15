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
  });

  final Uri? endpoint;
  final bool enabled;
  final String credentialRef;
  final CredentialAccess? credentialAccess;
  final FcNextMealTransport? transport;

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
    if (!configuration.isUsable) {
      throw const NextMealRemoteException('unconfigured');
    }
    String? token;
    await configuration.credentialAccess!(configuration.credentialRef, (
      secret,
    ) async {
      token = secret;
    });
    if (token == null || token!.isEmpty) {
      throw const NextMealRemoteException('unauthorized', 401);
    }

    final endpoint = configuration.endpoint!.resolve('/recommend');
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: 'Bearer $token',
    };
    final requestBody = jsonEncode({'prompt': jsonEncode(request.toJson())});
    final activeTransport = transport ?? configuration.transport;
    if (activeTransport != null) {
      final response = await activeTransport(
        endpoint,
        headers,
        requestBody,
      ).timeout(timeout);
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
      httpRequest = await http.postUrl(endpoint).timeout(timeout);
      httpRequest.headers
        ..set(
          HttpHeaders.contentTypeHeader,
          headers[HttpHeaders.contentTypeHeader]!,
        )
        ..set(
          HttpHeaders.authorizationHeader,
          headers[HttpHeaders.authorizationHeader]!,
        );
      httpRequest.add(utf8.encode(requestBody));
      final response = await httpRequest.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
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
}
