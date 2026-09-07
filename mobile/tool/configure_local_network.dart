import 'dart:io';

const _beginMarker = '<!-- SNAP_DEV_NETWORK_BEGIN -->';
const _endMarker = '<!-- SNAP_DEV_NETWORK_END -->';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !<String>{
        '--prepare-platform-network',
        '--allow-insecure-local-http',
        '--remove-insecure-local-http',
      }.contains(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tool/configure_local_network.dart '
      '[--prepare-platform-network|--allow-insecure-local-http|'
      '--remove-insecure-local-http]',
    );
    exitCode = 2;
    return;
  }

  final root = _projectRoot();
  final androidMainManifest =
      File('${root.path}/android/app/src/main/AndroidManifest.xml');
  final androidManifest =
      File('${root.path}/android/app/src/debug/AndroidManifest.xml');
  final iosInfoPlist = File('${root.path}/ios/Runner/Info.plist');
  if (!androidMainManifest.existsSync() ||
      !androidManifest.existsSync() ||
      !iosInfoPlist.existsSync()) {
    stderr.writeln(
      '생성된 android/ios 러너가 필요합니다. 먼저 '
      'sh tool/bootstrap_platforms.sh 를 실행하세요.',
    );
    exitCode = 1;
    return;
  }

  _ensureAndroidInternetPermission(androidMainManifest);
  _ensureIosLocalNetworkDescription(iosInfoPlist);

  if (arguments.single == '--allow-insecure-local-http') {
    _enableAndroidDebugCleartext(androidManifest);
    _enableIosDevelopmentHttp(iosInfoPlist);
    stdout.writeln('개발용 HTTP/ws 허용 설정을 적용했습니다.');
    stdout.writeln('릴리스 전 반드시 --remove-insecure-local-http를 실행하세요.');
  } else if (arguments.single == '--remove-insecure-local-http') {
    _removeMarkedBlock(androidManifest);
    _removeMarkedBlock(iosInfoPlist);
    stdout.writeln('개발용 HTTP/ws 허용 설정을 제거했습니다.');
  } else {
    stdout.writeln('Android 인터넷 권한과 iOS 로컬 네트워크 설명을 적용했습니다.');
  }
}

Directory _projectRoot() {
  final current = Directory.current.absolute;
  if (File('${current.path}/pubspec.yaml').existsSync()) {
    return current;
  }
  return File.fromUri(Platform.script).parent.parent.absolute;
}

void _ensureAndroidInternetPermission(File manifest) {
  var contents = manifest.readAsStringSync();
  if (contents.contains('android.permission.INTERNET')) {
    return;
  }
  final manifestTag = RegExp(r'<manifest\b[^>]*>').firstMatch(contents);
  if (manifestTag == null) {
    throw const FormatException('AndroidManifest.xml의 <manifest>를 찾지 못했습니다.');
  }
  const permission =
      '\n    <uses-permission android:name="android.permission.INTERNET" />';
  contents = contents.replaceRange(
    manifestTag.end,
    manifestTag.end,
    permission,
  );
  manifest.writeAsStringSync(contents);
}

void _ensureIosLocalNetworkDescription(File infoPlist) {
  var contents = infoPlist.readAsStringSync();
  if (contents.contains('<key>NSLocalNetworkUsageDescription</key>')) {
    return;
  }
  final insertionPoint = contents.lastIndexOf('</dict>');
  if (insertionPoint < 0) {
    throw const FormatException('Info.plist의 루트 </dict>를 찾지 못했습니다.');
  }
  const block = '''
\t<key>NSLocalNetworkUsageDescription</key>
\t<string>S.N.A.P Raspberry Pi Gateway에 연결합니다.</string>
''';
  contents = contents.replaceRange(insertionPoint, insertionPoint, block);
  infoPlist.writeAsStringSync(contents);
}

void _enableAndroidDebugCleartext(File manifest) {
  var contents = manifest.readAsStringSync();
  if (contents.contains(_beginMarker)) {
    return;
  }
  final insertionPoint = contents.lastIndexOf('</manifest>');
  if (insertionPoint < 0) {
    throw const FormatException('AndroidManifest.xml의 </manifest>를 찾지 못했습니다.');
  }
  const block = '''
    $_beginMarker
    <application android:usesCleartextTraffic="true" />
    $_endMarker
''';
  contents = contents.replaceRange(insertionPoint, insertionPoint, block);
  manifest.writeAsStringSync(contents);
}

void _enableIosDevelopmentHttp(File infoPlist) {
  var contents = infoPlist.readAsStringSync();
  if (contents.contains(_beginMarker)) {
    return;
  }
  if (contents.contains('<key>NSAppTransportSecurity</key>')) {
    throw const FormatException(
      'Info.plist에 기존 NSAppTransportSecurity가 있습니다. 중복 없이 수동 병합해 주세요.',
    );
  }
  final insertionPoint = contents.lastIndexOf('</dict>');
  if (insertionPoint < 0) {
    throw const FormatException('Info.plist의 루트 </dict>를 찾지 못했습니다.');
  }
  const block = '''
	$_beginMarker
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	$_endMarker
''';
  contents = contents.replaceRange(insertionPoint, insertionPoint, block);
  infoPlist.writeAsStringSync(contents);
}

void _removeMarkedBlock(File file) {
  final contents = file.readAsStringSync();
  final pattern = RegExp(
    '${RegExp.escape(_beginMarker)}.*?${RegExp.escape(_endMarker)}\\n?',
    dotAll: true,
  );
  file.writeAsStringSync(contents.replaceAll(pattern, ''));
}
