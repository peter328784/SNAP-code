import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/core/networking/pi_gateway_client.dart';
import 'package:snap_mobile/core/networking/pi_gateway_session.dart';

void main() {
  test('a WebSocket reconnect refetches the REST snapshot first', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    var snapshotCalls = 0;
    var vehicleCalls = 0;
    var socketConnections = 0;
    final requests = server.listen((request) async {
      if (request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        snapshotCalls += 1;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshot(snapshotCalls)));
        await request.response.close();
      } else if (request.uri.path ==
          '/v1/customers/demo-customer/vehicles') {
        vehicleCalls += 1;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_vehicles()));
        await request.response.close();
      } else if (request.uri.path == '/v1/events') {
        socketConnections += 1;
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(jsonEncode(<String, Object?>{
          'type': 'SNAPSHOT',
          'message': 'connected',
          'snapshot': _snapshot(snapshotCalls),
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final session = PiGatewaySession(
      client: PiGatewayClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
      reconnectDelays: const <Duration>[Duration(milliseconds: 20)],
    );

    await session.start();
    await _waitUntil(
      () => session.connectionState == GatewayConnectionState.connected,
    );
    final callsBeforeDisconnect = snapshotCalls;
    final vehicleCallsBeforeDisconnect = vehicleCalls;
    await sockets.first.close();
    await _waitUntil(() =>
        socketConnections >= 2 &&
        session.connectionState == GatewayConnectionState.connected);

    expect(snapshotCalls, greaterThan(callsBeforeDisconnect));
    expect(vehicleCalls, greaterThan(vehicleCallsBeforeDisconnect));
    expect(session.vehicles.single.vehicleNumber, '12가3456');

    session.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await requests.cancel();
    await server.close(force: true);
  });

  test('an older REST refresh cannot overwrite a newer WebSocket snapshot',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    var restRevision = 2;
    final requests = server.listen((request) async {
      if (request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshot(restRevision)));
        await request.response.close();
      } else if (request.uri.path ==
          '/v1/customers/demo-customer/vehicles') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_vehicles()));
        await request.response.close();
      } else if (request.uri.path == '/v1/events') {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(jsonEncode(<String, Object?>{
          'type': 'MOVING_TO_SLOT',
          'message': 'newer event',
          'snapshot': _snapshot(3),
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final session = PiGatewaySession(
      client: PiGatewayClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
    );

    await session.start();
    await _waitUntil(() => session.snapshot?.updatedAt.second == 3);
    restRevision = 1;

    await session.refresh();

    expect(session.snapshot?.updatedAt.second, 3);

    session.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await requests.cancel();
    await server.close(force: true);
  });

  test('a failed refresh from an old generation cannot poison reconnect state',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final releaseStaleRefresh = Completer<void>();
    var snapshotCalls = 0;
    final requests = server.listen((request) async {
      if (request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        snapshotCalls += 1;
        request.response.headers.contentType = ContentType.json;
        if (snapshotCalls == 2) {
          await releaseStaleRefresh.future;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write(jsonEncode(<String, Object?>{
            'detail': 'stale failure',
          }));
        } else {
          request.response.write(jsonEncode(_snapshot(snapshotCalls)));
        }
        await request.response.close();
      } else if (request.uri.path ==
          '/v1/customers/demo-customer/vehicles') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_vehicles()));
        await request.response.close();
      } else if (request.uri.path == '/v1/events') {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(jsonEncode(<String, Object?>{
          'type': 'SNAPSHOT',
          'message': 'connected',
          'snapshot': _snapshot(snapshotCalls),
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final session = PiGatewaySession(
      client: PiGatewayClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
    );
    addTearDown(() async {
      if (!releaseStaleRefresh.isCompleted) {
        releaseStaleRefresh.complete();
      }
      session.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await requests.cancel();
      await server.close(force: true);
    });

    await session.start();
    await _waitUntil(
      () => session.connectionState == GatewayConnectionState.connected,
    );
    final staleRefresh = session.refresh();
    await _waitUntil(() => snapshotCalls == 2);

    await session.reconnectNow();
    releaseStaleRefresh.complete();
    await staleRefresh;

    expect(session.connectionState, GatewayConnectionState.connected);
    expect(session.lastError, isNull);
  });

  test('a WebSocket snapshot refreshes the customer vehicle list', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    var vehicleState = 'READY_TO_PARK';
    var revision = 1;
    final requests = server.listen((request) async {
      if (request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_snapshot(revision)));
        await request.response.close();
      } else if (request.uri.path ==
          '/v1/customers/demo-customer/vehicles') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_vehicles(state: vehicleState)));
        await request.response.close();
      } else if (request.uri.path == '/v1/events') {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    final session = PiGatewaySession(
      client: PiGatewayClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
    );

    await session.start();
    await _waitUntil(
      () => session.connectionState == GatewayConnectionState.connected,
    );
    expect(session.vehicles.single.state.canRequestParking, isTrue);

    vehicleState = 'PARKED';
    revision = 2;
    sockets.single.add(jsonEncode(<String, Object?>{
      'type': 'PARKED',
      'message': 'vehicle updated',
      'snapshot': _snapshot(revision),
    }));
    await _waitUntil(
      () => session.vehicles.single.state.canRequestRetrieval,
    );

    session.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await requests.cancel();
    await server.close(force: true);
  });

  test('rejects a second command while the first POST is pending', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final releaseResponse = Completer<void>();
    var parkingPosts = 0;
    final requests = server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/v1/parking-requests') {
        parkingPosts += 1;
        await utf8.decoder.bind(request).join();
        await releaseResponse.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, Object?>{
          'requestId': 'REQ-ONE',
          'snapshot': _snapshot(1),
        }));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/customers/demo-customer/vehicles') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_vehicles()));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final session = PiGatewaySession(
      client: PiGatewayClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
    );

    final first = session.requestParking(
      vehicleId: 'VEH-1',
      expectedMinutes: 120,
    );
    await _waitUntil(() => parkingPosts == 1);
    await expectLater(
      session.requestParking(
        vehicleId: 'VEH-1',
        expectedMinutes: 120,
      ),
      throwsA(isA<DuplicateSubmissionException>()),
    );
    releaseResponse.complete();
    await first;

    expect(parkingPosts, 1);

    session.dispose();
    await requests.cancel();
    await server.close(force: true);
  });

  test(
    'a failed foreground refresh enters managed reconnect without throwing',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      var failSnapshots = false;
      final requests = server.listen((request) async {
        if (request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
          request.response.headers.contentType = ContentType.json;
          if (failSnapshots) {
            request.response.statusCode = HttpStatus.serviceUnavailable;
            request.response.write(jsonEncode(<String, Object?>{
              'detail': 'temporarily unavailable',
            }));
          } else {
            request.response.write(jsonEncode(_snapshot(1)));
          }
          await request.response.close();
        } else if (request.uri.path ==
            '/v1/customers/demo-customer/vehicles') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(_vehicles()));
          await request.response.close();
        } else if (request.uri.path == '/v1/events') {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.add(jsonEncode(<String, Object?>{
            'type': 'SNAPSHOT',
            'message': 'connected',
            'snapshot': _snapshot(1),
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
      final session = PiGatewaySession(
        client: PiGatewayClient(
          baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
        ),
        reconnectDelays: const <Duration>[Duration(seconds: 30)],
      );

      await session.start();
      await _waitUntil(
        () => session.connectionState == GatewayConnectionState.connected,
      );
      failSnapshots = true;

      await session.resume();

      expect(session.connectionState, GatewayConnectionState.reconnecting);
      expect(session.lastError, contains('temporarily unavailable'));

      session.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await requests.cancel();
      await server.close(force: true);
    },
  );
}

Map<String, Object?> _snapshot(int revision) => <String, Object?>{
      'lotId': 'demo-01',
      'updatedAt': '2026-08-25T12:00:0${revision.clamp(0, 9)}Z',
      'slots': <Object?>[
        <String, Object?>{'id': '1', 'state': 'AVAILABLE'},
      ],
      'robot': <String, Object?>{
        'state': '대기 중',
        'batteryPct': 86,
        'positionPct': 18,
      },
      'job': <String, Object?>{'state': 'IDLE', 'message': 'ready'},
    };

Map<String, Object?> _vehicles({String state = 'READY_TO_PARK'}) =>
    <String, Object?>{
      'customerId': 'demo-customer',
      'vehicles': <Object?>[
        <String, Object?>{
          'vehicleId': 'VEH-1',
          'vehicleNumber': '12가3456',
          'state': state,
          if (state == 'PARKED') 'slotId': '4',
        },
      ],
    };

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('조건을 기다리는 중 시간이 초과됐습니다.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
