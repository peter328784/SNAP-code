import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';

void main() {
  const snapshotJson = <String, Object?>{
    'lotId': 'demo-01',
    'updatedAt': '2026-08-25T12:00:00Z',
    'slots': <Object?>[
      <String, Object?>{'id': '1', 'state': 'AVAILABLE'},
      <String, Object?>{
        'id': '2',
        'state': 'OCCUPIED',
        'vehicleId': 'SNAP-88',
      },
    ],
    'robot': <String, Object?>{
      'state': '대기 중',
      'batteryPct': 86,
      'positionPct': 18,
    },
    'job': <String, Object?>{
      'id': 'REQ-1',
      'state': 'MOVING_TO_SLOT',
      'vehicleId': 'SNAP-01',
      'targetSlot': '1',
      'reasonCode': 'AUTO_BALANCED',
      'message': '이동 중',
    },
  };

  test('parses a direct REST snapshot', () {
    final snapshot = ParkingSnapshot.fromPayload(snapshotJson);

    expect(snapshot.lotId, 'demo-01');
    expect(snapshot.slots, hasLength(2));
    expect(snapshot.slots[1].vehicleId, 'SNAP-88');
    expect(snapshot.job.state, JobState.movingToSlot);
    expect(snapshot.robot.batteryPct, 86);
  });

  test('parses the snapshot nested in a POST response', () {
    final result = GatewayCommandResult.fromPayload(<String, Object?>{
      'requestId': 'REQ-1234',
      'snapshot': snapshotJson,
    });

    expect(result.requestId, 'REQ-1234');
    expect(result.snapshot?.job.targetSlot, '1');
  });

  test('parses a WebSocket event envelope', () {
    final event = GatewayEvent.fromPayload(<String, Object?>{
      'type': 'MOVING_TO_SLOT',
      'message': '실시간 상태',
      'snapshot': snapshotJson,
    });

    expect(event.type, 'MOVING_TO_SLOT');
    expect(event.snapshot.job.vehicleId, 'SNAP-01');
  });

  test('accepts snake_case aliases and preserves unknown safety states', () {
    final snapshot = ParkingSnapshot.fromPayload(<String, Object?>{
      'lot_id': 'demo-01',
      'updated_at': '2026-08-25T12:00:00Z',
      'slots': <Object?>[
        <String, Object?>{'slot_id': 3, 'status': 'SENSOR_MISSING'},
      ],
      'robot': <String, Object?>{
        'battery_pct': 90,
        'position_pct': 20,
      },
      'activeJob': <String, Object?>{
        'state': 'EMERGENCY_STOP',
        'target_slot': 3,
      },
    });

    expect(snapshot.slots.single.state, SlotState.unknown);
    expect(snapshot.slots.single.id, '3');
    expect(snapshot.job.state, JobState.emergencyStop);
  });

  test('parses a customer vehicle without exposing its internal id as number', () {
    final vehicle = CustomerVehicle.fromPayload(<String, Object?>{
      'vehicle': <String, Object?>{
        'id': 'VEH-1234',
        'vehicleNumber': '12가3456',
        'state': 'PARKED',
        'slotId': '5',
        'expectedMinutes': 240,
      },
    });

    expect(vehicle.id, 'VEH-1234');
    expect(vehicle.vehicleId, 'VEH-1234');
    expect(vehicle.vehicleNumber, '12가3456');
    expect(vehicle.state, VehicleState.parked);
    expect(vehicle.slotId, '5');
    expect(vehicle.expectedMinutes, 240);
    expect(vehicle.state.canRequestRetrieval, isTrue);
  });

  test('accepts the Gateway vehicleId and READY_TO_PARK aliases', () {
    final vehicle = CustomerVehicle.fromJson(<String, Object?>{
      'vehicleId': 'VEH-ALIAS',
      'vehicle_number': '34나5678',
      'status': 'READY_TO_PARK',
    });

    expect(vehicle.id, 'VEH-ALIAS');
    expect(vehicle.state.canRequestParking, isTrue);
  });

  test('parses customer vehicle updatedAt aliases as UTC', () {
    for (final field in <String>['updatedAt', 'updated_at']) {
      final vehicle = CustomerVehicle.fromJson(<String, Object?>{
        'vehicleId': 'VEH-TIME',
        'vehicleNumber': '12가3456',
        'state': 'PARKED',
        field: '2026-08-25T21:18:00+09:00',
      });

      expect(vehicle.updatedAt, DateTime.utc(2026, 8, 25, 12, 18));
      expect(vehicle.updatedAt?.isUtc, isTrue);
      expect(
        DateTime.parse(vehicle.toJson()['updatedAt']! as String),
        DateTime.utc(2026, 8, 25, 12, 18),
      );
    }
  });

  test('keeps invalid or absent customer vehicle updatedAt nullable', () {
    final base = <String, Object?>{
      'vehicleId': 'VEH-TIME',
      'vehicleNumber': '12가3456',
      'state': 'PARKED',
    };

    final vehicleWithoutTime = CustomerVehicle.fromJson(base);
    expect(vehicleWithoutTime.updatedAt, isNull);
    expect(vehicleWithoutTime.toJson(), isNot(contains('updatedAt')));
    expect(
      CustomerVehicle.fromJson(<String, Object?>{
        ...base,
        'updatedAt': 'not-a-date',
      }).updatedAt,
      isNull,
    );
  });

  test('recognizes active Gateway job states used to disable commands', () {
    expect(JobState.fromWire('RUNNING'), JobState.running);
    expect(
      JobState.fromWire('RETURNING_TO_STANDBY'),
      JobState.returning,
    );
    expect(JobState.running.isTerminal, isFalse);
    expect(JobState.returning.isTerminal, isFalse);
  });
}
