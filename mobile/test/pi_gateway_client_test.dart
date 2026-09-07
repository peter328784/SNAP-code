import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/core/networking/pi_gateway_client.dart';

void main() {
  test('rejects a Gateway base URI with a query or fragment', () {
    for (final uri in <Uri>[
      Uri.parse('http://127.0.0.1:8101?token=secret'),
      Uri.parse('http://127.0.0.1:8101#status'),
    ]) {
      expect(
        () => PiGatewayClient(baseUri: uri),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('query 또는 fragment'),
          ),
        ),
      );
    }
  });

  late HttpServer server;
  late PiGatewayClient client;
  late StreamSubscription<HttpRequest> requests;
  Map<String, Object?>? receivedParkingBody;
  Map<String, Object?>? receivedRetrievalBody;
  Map<String, Object?>? receivedRegistrationBody;
  var responseLotId = 'demo-01';
  var malformedSnapshot = false;
  var emptyRequestId = false;

  setUp(() async {
    receivedParkingBody = null;
    receivedRetrievalBody = null;
    receivedRegistrationBody = null;
    responseLotId = 'demo-01';
    malformedSnapshot = false;
    emptyRequestId = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = PiGatewayClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );
    requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        final snapshot = _snapshot('IDLE', lotId: responseLotId);
        if (malformedSnapshot) {
          snapshot.remove('robot');
        }
        request.response.write(jsonEncode(snapshot));
      } else if (request.method == 'GET' &&
          request.uri.path == '/v1/customers/customer-one/vehicles') {
        request.response.write(jsonEncode(<String, Object?>{
          'customerId': 'customer-one',
          'vehicles': <Object?>[
            _vehicle('VEH-1', '12가3456', 'READY_TO_PARK'),
            _vehicle('VEH-2', '34나5678', 'PARKED', slotId: '4'),
          ],
        }));
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/customers/customer-one/vehicles') {
        receivedRegistrationBody = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<Object?, Object?>,
        );
        request.response.write(jsonEncode(<String, Object?>{
          'vehicle': _vehicle('VEH-3', '56다7890', 'READY_TO_PARK'),
        }));
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/parking-requests') {
        receivedParkingBody = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<Object?, Object?>,
        );
        request.response.write(jsonEncode(<String, Object?>{
          'requestId': emptyRequestId ? '' : 'REQ-TEST',
          'snapshot': _snapshot('REQUESTED', lotId: responseLotId),
        }));
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/retrieval-requests') {
        receivedRetrievalBody = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<Object?, Object?>,
        );
        request.response.write(jsonEncode(<String, Object?>{
          'requestId': 'REQ-OUT',
          'snapshot': _snapshot('RETRIEVING', lotId: responseLotId),
        }));
      } else if (request.uri.path == '/fail') {
        request.response.statusCode = HttpStatus.conflict;
        request.response.write(jsonEncode(<String, Object?>{'detail': 'busy'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    client.close();
    await requests.cancel();
    await server.close(force: true);
  });

  test('fetches the configured parking lot snapshot', () async {
    final snapshot = await client.fetchSnapshot();

    expect(snapshot.lotId, 'demo-01');
    expect(snapshot.slots.single.id, '1');
  });

  test('fetches only the configured customer vehicles', () async {
    final vehicles = await client.fetchVehicles(customerId: 'customer-one');

    expect(vehicles, hasLength(2));
    expect(vehicles.first.vehicleNumber, '12가3456');
    expect(vehicles.last.slotId, '4');
  });

  test('registers a vehicle number for the configured customer', () async {
    final vehicle = await client.registerVehicle(
      customerId: 'customer-one',
      vehicleNumber: '56다7890',
    );

    expect(receivedRegistrationBody, <String, Object?>{
      'vehicleNumber': '56다7890',
    });
    expect(vehicle.id, 'VEH-3');
  });

  test('sends customer and vehicle ids in the parking request', () async {
    final result = await client.requestParking(
      customerId: 'customer-one',
      vehicleId: 'VEH-1',
      expectedMinutes: 120,
    );

    expect(receivedParkingBody, <String, Object?>{
      'customerId': 'customer-one',
      'vehicleId': 'VEH-1',
      'expectedMinutes': 120,
    });
    expect(result.requestId, 'REQ-TEST');
    expect(result.snapshot?.job.state.wireName, 'REQUESTED');
  });

  test('sends customer and vehicle ids in the retrieval request', () async {
    final result = await client.requestRetrieval(
      customerId: 'customer-one',
      vehicleId: 'VEH-2',
    );

    expect(receivedRetrievalBody, <String, Object?>{
      'customerId': 'customer-one',
      'vehicleId': 'VEH-2',
    });
    expect(result.requestId, 'REQ-OUT');
  });

  test('rejects a malformed REST snapshot', () async {
    malformedSnapshot = true;

    await expectLater(
      client.fetchSnapshot(),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('robot'),
        ),
      ),
    );
  });

  test('rejects a snapshot for a different parking lot', () async {
    responseLotId = 'other-lot';

    await expectLater(
      client.fetchSnapshot(),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('lotId'),
        ),
      ),
    );
  });

  test('rejects a command response without a requestId', () async {
    emptyRequestId = true;

    await expectLater(
      client.requestParking(
        customerId: 'customer-one',
        vehicleId: 'VEH-1',
        expectedMinutes: 120,
      ),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('requestId'),
        ),
      ),
    );
  });
}

Map<String, Object?> _snapshot(
  String jobState, {
  String lotId = 'demo-01',
}) =>
    <String, Object?>{
      'lotId': lotId,
      'updatedAt': '2026-08-25T12:00:00Z',
      'slots': <Object?>[
        <String, Object?>{'id': '1', 'state': 'AVAILABLE'},
      ],
      'robot': <String, Object?>{
        'state': '대기 중',
        'batteryPct': 86,
        'positionPct': 18,
      },
      'job': <String, Object?>{'state': jobState, 'message': jobState},
    };

Map<String, Object?> _vehicle(
  String id,
  String vehicleNumber,
  String state, {
  String? slotId,
}) =>
    <String, Object?>{
      'vehicleId': id,
      'vehicleNumber': vehicleNumber,
      'state': state,
      if (slotId != null) 'slotId': slotId,
    };
