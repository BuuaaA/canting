import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'recognition_contract.dart';

/// N2 configuration state for N3. Only non-secret fields are persisted.
class RecognitionConfiguration {
  RecognitionConfiguration(
    this.contract,
    this.preferences, [
    this._writeString,
  ]);

  static const storageKey = 'recognition_provider_configuration_v1';
  static const cloudEnabledKey = 'recognition_cloud_enabled_v1';
  static const imageConsentKey = 'recognition_image_consent_v1';
  static const consentVersion = 'cloud-recognition-v1';
  static Uri? backendEndpoint(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment
        ? uri
        : null;
  }
  final RecognitionContract contract;
  final SharedPreferences preferences;
  final Future<bool> Function(String key, String value)? _writeString;
  String? _temporaryCredential;

  bool get hasTemporaryCredential => _temporaryCredential != null;
  String get credentialStatus =>
      hasTemporaryCredential ? 'temporary_input' : 'not_configured';
  String get maskedCredential => hasTemporaryCredential ? '••••••' : '';
  bool get cloudEnabled => preferences.getBool(cloudEnabledKey) ?? false;
  bool get imageConsent => preferences.getBool(imageConsentKey) ?? false;
  Future<void> setCloudEnabled(bool value) =>
      preferences.setBool(cloudEnabledKey, value);
  Future<void> setImageConsent(bool value) =>
      preferences.setBool(imageConsentKey, value);

  void setTemporaryCredential(String value) {
    _temporaryCredential = value.isEmpty ? null : value;
  }

  void clearTemporaryCredential() => _temporaryCredential = null;

  Map<String, dynamic> load() {
    final text = preferences.getString(storageKey);
    if (text == null) return defaults();
    try {
      return contract.provider(jsonDecode(text));
    } on Object {
      return defaults();
    }
  }

  Future<Map<String, dynamic>> save(Map<String, dynamic> input) async {
    try {
      final checked = contract.provider(input);
      final stored = await (_writeString ?? preferences.setString)(
        storageKey,
        jsonEncode(checked),
      );
      if (!stored) {
        throw StateError('Unable to save recognition configuration');
      }
      return checked;
    } finally {
      clearTemporaryCredential();
    }
  }

  Future<void> clear() async {
    clearTemporaryCredential();
    await preferences.remove(storageKey);
  }

  static Map<String, dynamic> defaults() => {
    'mode': 'unconfigured',
    'endpoint': null,
    'model': null,
    'credentialRef': null,
    'delivery': 'undecided',
    'region': null,
    'thinking': false,
    'inputTokenLimit': 6000,
    'outputTokenLimit': 1200,
  };
}
