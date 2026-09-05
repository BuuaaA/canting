import 'dart:io';

/// Test output only. Frozen P2/P3/P4 evidence remains read-only input.
String evidencePath(String name) {
  final directory = Directory(
    Platform.environment['CANTING_TEST_EVIDENCE_DIR'] ??
        'build/test-evidence/latest',
  );
  final path = directory.absolute.path.replaceAll('\\', '/');
  if (RegExp(r'dev-docs/p[234]-evidence(?:/|$)').hasMatch(path)) {
    throw StateError('Refusing to overwrite frozen evidence: $path');
  }
  directory.createSync(recursive: true);
  return '${directory.path}/$name';
}
