import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/core/networking/pi_gateway_client.dart';

Future<void> main(List<String> arguments) async {
  final baseUrl = _argument(arguments, '--base-url') ?? 'http://127.0.0.1:8101';
  final lotId = _argument(arguments, '--lot-id') ?? 'demo-01';
  final customerId =
      _argument(arguments, '--customer-id') ?? 'demo-customer';
  final client = PiGatewayClient(baseUri: Uri.parse(baseUrl));
  WebSocket? socket;

  try {
    final health = await client.getHealth();
    if (!health.isHealthy) {
      throw StateError('health.status=${health.status}');
    }
    stdout.writeln('[PASS] GET /health (${health.mode})');

    final snapshot = await client.fetchSnapshot(lotId: lotId);
    if (snapshot.lotId != lotId || snapshot.slots.isEmpty) {
      throw StateError('Snapshot 계약이 예상과 다릅니다.');
    }
    stdout.writeln('[PASS] GET snapshot (${snapshot.slots.length} slots)');

    final vehicles = await client.fetchVehicles(customerId: customerId);
    stdout.writeln('[PASS] GET customer vehicles (${vehicles.length} vehicles)');

    socket = await WebSocket.connect(client.eventsUri.toString())
        .timeout(client.requestTimeout);
    final rawEvent = await socket.first.timeout(client.requestTimeout);
    final text = rawEvent is String
        ? rawEvent
        : rawEvent is List<int>
            ? utf8.decode(rawEvent)
            : throw StateError('지원하지 않는 WebSocket frame입니다.');
    final event = GatewayEvent.fromPayload(
      jsonDecode(text),
      fallback: snapshot,
      strict: true,
      expectedLotId: lotId,
    );
    if (event.type != 'SNAPSHOT' || event.snapshot.lotId != lotId) {
      throw StateError('첫 WebSocket SNAPSHOT 이벤트가 올바르지 않습니다.');
    }
    stdout.writeln('[PASS] WS /v1/events (${event.type})');
    stdout.writeln('Gateway 읽기 통신 검증 완료: $baseUrl');
  } catch (error, stackTrace) {
    stderr.writeln('[FAIL] $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await socket?.close();
    client.close();
  }
}

String? _argument(List<String> arguments, String name) {
  final prefix = '$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }
  return null;
}
