import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'next_meal_recommendation.dart';
import 'recognition_adapter.dart';

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
  });

  final Uri? endpoint;
  final bool enabled;
  final String credentialRef;
  final CredentialAccess? credentialAccess;

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
    this.timeout = const Duration(seconds: 20),
  });

  final FcNextMealConfiguration configuration;
  final HttpClient? client;
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

    final http = client ?? HttpClient();
    try {
      final endpoint = configuration.endpoint!.resolve('/recommend');
      final httpRequest = await http.postUrl(endpoint).timeout(timeout);
      httpRequest.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      httpRequest.add(
        utf8.encode(jsonEncode({'prompt': jsonEncode(request.toJson())})),
      );
      final response = await httpRequest.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NextMealRemoteException(
          _reasonForStatus(response.statusCode),
          response.statusCode,
        );
      }
      if (body.trim().isEmpty) {
        throw const NextMealRemoteException('invalid_json');
      }
      // Validate that the gateway returns JSON here; schema validation remains
      // in NextMealRecommendationService so the same rules cover all callers.
      jsonDecode(body);
      return body;
    } on TimeoutException {
      throw const NextMealRemoteException('timeout');
    } on SocketException {
      throw const NextMealRemoteException('network_error');
    } on FormatException {
      throw const NextMealRemoteException('invalid_json');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  static String _reasonForStatus(int status) {
    if (status == 401 || status == 403) return 'unauthorized';
    if (status == 429) return 'rate_limited';
    if (status >= 500) return 'server_error';
    return 'remote_http_error';
  }
}
