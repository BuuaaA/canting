import 'dart:convert';
import 'dart:io';

import 'package:canting/services/recognition_adapter.dart';
import 'package:canting/services/recognition_configuration.dart';
import 'package:canting/services/recognition_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release backend URL accepts only credential-free HTTPS', () {
    expect(
      RecognitionConfiguration.backendEndpoint('https://api.example.com'),
      Uri.parse('https://api.example.com'),
    );
    for (final value in [
      '',
      'http://api.example.com',
      'https://user:secret@api.example.com',
      'https://api.example.com?q=secret',
    ]) {
      expect(RecognitionConfiguration.backendEndpoint(value), isNull);
    }
  });

  test('multipart request binds image, OCR and response identity', () async {
    final image = File('${Directory.systemTemp.path}/canting-w4-test.jpg');
    await image.writeAsBytes([1, 2, 3]);
    final hash = sha256.convert(await image.readAsBytes()).toString();
    final payload = {
      'schemaVersion': 'recognition-n0.3',
      'draftId': '00000000-0000-4000-8000-000000000001',
      'requestId': '00000000-0000-4000-8000-000000000002',
      'draftRevision': 2,
      'assets': [
        {'imageSha256': hash},
      ],
      'ocrBlocks': [
        {'text': '米饭'},
      ],
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final served = server.first.then((request) async {
      expect(request.uri.path, '/v1/recognitions');
      expect(request.headers.value('X-Device-Id'), 'device-w4');
      final body = await utf8.decoder.bind(request).join();
      expect(body, contains('name="payload"'));
      expect(body, contains('"draftRevision":2'));
      expect(body, contains('米饭'));
      expect(body, contains('name="images"'));
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'schemaVersion': 'recognition-n0.3',
            'draftId': payload['draftId'],
            'requestId': payload['requestId'],
            'draftRevision': 2,
            'assetHashes': [hash],
            'state': 'review',
            'modelPolicyVersion': 'policy-w3',
            'promptVersion': 'recognition-prompt-n0.3',
            'result': {
              'schemaVersion': 'recognition-n0.3',
              'draftId': payload['draftId'],
              'requestId': payload['requestId'],
              'draftRevision': 2,
              'modelPolicyVersion': 'policy-w3',
              'promptVersion': 'recognition-prompt-n0.3',
              'products': [],
            },
          }),
        );
      await request.response.close();
    });
    final response = await RecognitionAdapter(RecognitionContract(const {}))
        .recognizeCloud(
          endpoint: Uri.parse('http://${server.address.host}:${server.port}'),
          deviceId: 'device-w4',
          payload: payload,
          image: image,
        );
    expect(response['state'], 'review');
    await served;
    await server.close();
    await image.delete();
  });
}
