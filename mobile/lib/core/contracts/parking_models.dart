enum SlotState {
  available,
  reserved,
  occupied,
  unavailable,
  unknown;

  factory SlotState.fromWire(Object? value) {
    return switch (_wire(value)) {
      'AVAILABLE' => SlotState.available,
      'RESERVED' => SlotState.reserved,
      'OCCUPIED' => SlotState.occupied,
      'UNAVAILABLE' || 'BLOCKED' => SlotState.unavailable,
      _ => SlotState.unknown,
    };
  }

  String get wireName => name.toUpperCase();
}

enum JobState {
  idle,
  requested,
  running,
  vehicleDetected,
  movingToVehicle,
  lifting,
  movingToSlot,
  parked,
  retrieving,
  returning,
  failed,
  emergencyStop,
  unknown;

  factory JobState.fromWire(Object? value) {
    return switch (_wire(value)) {
      'IDLE' => JobState.idle,
      'REQUESTED' => JobState.requested,
      'RUNNING' => JobState.running,
      'VEHICLE_DETECTED' => JobState.vehicleDetected,
      'MOVING_TO_VEHICLE' => JobState.movingToVehicle,
      'LIFTING' => JobState.lifting,
      'MOVING_TO_SLOT' => JobState.movingToSlot,
      'PARKED' => JobState.parked,
      'RETRIEVING' => JobState.retrieving,
      'RETURNING' || 'RETURNING_TO_STANDBY' => JobState.returning,
      'FAILED' || 'ERROR' => JobState.failed,
      'EMERGENCY_STOP' => JobState.emergencyStop,
      _ => JobState.unknown,
    };
  }

  String get wireName {
    return switch (this) {
      JobState.vehicleDetected => 'VEHICLE_DETECTED',
      JobState.movingToVehicle => 'MOVING_TO_VEHICLE',
      JobState.movingToSlot => 'MOVING_TO_SLOT',
      JobState.emergencyStop => 'EMERGENCY_STOP',
      _ => name.toUpperCase(),
    };
  }

  bool get isTerminal =>
      this == JobState.idle ||
      this == JobState.parked ||
      this == JobState.failed ||
      this == JobState.emergencyStop;
}

enum VehicleState {
  readyToPark,
  parkingRequested,
  parkingInProgress,
  parked,
  retrievalRequested,
  retrieving,
  retrieved,
  error,
  unknown;

  factory VehicleState.fromWire(Object? value) {
    return switch (_wire(value)) {
      'READY' || 'READY_TO_PARK' => VehicleState.readyToPark,
      'PARKING_REQUESTED' => VehicleState.parkingRequested,
      'PARKING_IN_PROGRESS' => VehicleState.parkingInProgress,
      'PARKED' => VehicleState.parked,
      'RETRIEVAL_REQUESTED' => VehicleState.retrievalRequested,
      'RETRIEVING' => VehicleState.retrieving,
      'RETRIEVED' => VehicleState.retrieved,
      'ERROR' || 'FAILED' => VehicleState.error,
      _ => VehicleState.unknown,
    };
  }

  String get wireName {
    return switch (this) {
      VehicleState.readyToPark => 'READY_TO_PARK',
      VehicleState.parkingRequested => 'PARKING_REQUESTED',
      VehicleState.parkingInProgress => 'PARKING_IN_PROGRESS',
      VehicleState.parked => 'PARKED',
      VehicleState.retrievalRequested => 'RETRIEVAL_REQUESTED',
      VehicleState.retrieving => 'RETRIEVING',
      VehicleState.retrieved => 'RETRIEVED',
      VehicleState.error => 'ERROR',
      VehicleState.unknown => 'UNKNOWN',
    };
  }

  bool get canRequestParking =>
      this == VehicleState.readyToPark || this == VehicleState.retrieved;

  bool get canRequestRetrieval => this == VehicleState.parked;
}

class CustomerVehicle {
  const CustomerVehicle({
    required this.id,
    required this.vehicleNumber,
    required this.state,
    this.slotId,
    this.expectedMinutes,
    this.updatedAt,
  });

  factory CustomerVehicle.fromPayload(Object? payload) {
    final envelope = asStringMap(payload);
    final nested = envelope['vehicle'] ?? envelope['data'];
    return CustomerVehicle.fromJson(
      nested is Map<Object?, Object?> ? asStringMap(nested) : envelope,
    );
  }

  factory CustomerVehicle.fromJson(Map<String, Object?> json) {
    final id = _nullableString(
      json['id'] ?? json['vehicleId'] ?? json['vehicle_id'],
    );
    if (id == null) {
      throw const FormatException('차량 정보에 id가 없습니다.');
    }
    final vehicleNumber = _nullableString(
      json['vehicleNumber'] ?? json['vehicle_number'],
    );
    if (vehicleNumber == null) {
      throw const FormatException('차량 정보에 vehicleNumber가 없습니다.');
    }
    final stateValue = json['state'] ?? json['status'];
    if (stateValue == null || stateValue.toString().trim().isEmpty) {
      throw const FormatException('차량 정보에 state가 없습니다.');
    }

    return CustomerVehicle(
      id: id,
      vehicleNumber: vehicleNumber,
      state: VehicleState.fromWire(stateValue),
      slotId: _nullableString(json['slotId'] ?? json['slot_id']),
      expectedMinutes: _nullableInt(
        json['expectedMinutes'] ?? json['expected_minutes'],
      ),
      updatedAt: DateTime.tryParse(
        (json['updatedAt'] ?? json['updated_at'] ?? '').toString(),
      )?.toUtc(),
    );
  }

  final String id;
  final String vehicleNumber;
  final VehicleState state;
  final String? slotId;
  final int? expectedMinutes;
  final DateTime? updatedAt;

  String get vehicleId => id;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'vehicleNumber': vehicleNumber,
        'state': state.wireName,
        if (slotId != null) 'slotId': slotId,
        if (expectedMinutes != null) 'expectedMinutes': expectedMinutes,
        if (updatedAt != null)
          'updatedAt': updatedAt!.toUtc().toIso8601String(),
      };
}

class ParkingSlot {
  const ParkingSlot({required this.id, required this.state, this.vehicleId});

  factory ParkingSlot.fromJson(Map<String, Object?> json) {
    final vehicleId = json['vehicleId'] ?? json['vehicle_id'];
    return ParkingSlot(
      id: (json['id'] ?? json['slotId'] ?? json['slot_id'] ?? '').toString(),
      state: SlotState.fromWire(json['state'] ?? json['status']),
      vehicleId: vehicleId == null || vehicleId.toString().isEmpty
          ? null
          : vehicleId.toString(),
    );
  }

  final String id;
  final SlotState state;
  final String? vehicleId;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'state': state.wireName,
        if (vehicleId != null) 'vehicleId': vehicleId,
      };
}

class RobotSnapshot {
  const RobotSnapshot({
    required this.state,
    required this.batteryPct,
    required this.positionPct,
  });

  factory RobotSnapshot.fromJson(
    Map<String, Object?> json, {
    RobotSnapshot? fallback,
  }) {
    return RobotSnapshot(
      state: (json['state'] ?? json['status'] ?? fallback?.state ?? '상태 미확인')
          .toString(),
      batteryPct: _boundedInt(
        json['batteryPct'] ?? json['battery_pct'] ?? json['battery'],
        fallback?.batteryPct ?? 0,
        0,
        100,
      ),
      positionPct: _boundedInt(
        json['positionPct'] ?? json['position_pct'] ?? json['position'],
        fallback?.positionPct ?? 0,
        0,
        100,
      ),
    );
  }

  final String state;
  final int batteryPct;
  final int positionPct;

  Map<String, Object?> toJson() => <String, Object?>{
        'state': state,
        'batteryPct': batteryPct,
        'positionPct': positionPct,
      };
}

class JobSnapshot {
  const JobSnapshot({
    required this.state,
    required this.message,
    this.id,
    this.vehicleId,
    this.targetSlot,
    this.reasonCode,
    this.reason,
  });

  factory JobSnapshot.fromJson(
    Map<String, Object?> json, {
    JobSnapshot? fallback,
  }) {
    final rawState = json['state'] ?? json['status'];
    return JobSnapshot(
      id: _nullableString(json['id']) ?? fallback?.id,
      state: rawState == null
          ? fallback?.state ?? JobState.unknown
          : JobState.fromWire(rawState),
      vehicleId: _nullableString(json['vehicleId'] ?? json['vehicle_id']) ??
          fallback?.vehicleId,
      targetSlot: _nullableString(json['targetSlot'] ?? json['target_slot']) ??
          fallback?.targetSlot,
      reasonCode: _nullableString(json['reasonCode'] ?? json['reason_code']) ??
          fallback?.reasonCode,
      reason: _nullableString(json['reason']) ?? fallback?.reason,
      message: (json['message'] ?? fallback?.message ?? '작업 정보가 없습니다.')
          .toString(),
    );
  }

  final String? id;
  final JobState state;
  final String? vehicleId;
  final String? targetSlot;
  final String? reasonCode;
  final String? reason;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        'state': state.wireName,
        if (vehicleId != null) 'vehicleId': vehicleId,
        if (targetSlot != null) 'targetSlot': targetSlot,
        if (reasonCode != null) 'reasonCode': reasonCode,
        if (reason != null) 'reason': reason,
        'message': message,
      };
}

class ParkingSnapshot {
  const ParkingSnapshot({
    required this.lotId,
    required this.updatedAt,
    required this.slots,
    required this.robot,
    required this.job,
  });

  factory ParkingSnapshot.fromPayload(
    Object? payload, {
    ParkingSnapshot? fallback,
    bool strict = false,
    String? expectedLotId,
  }) {
    if (strict && payload is! Map<Object?, Object?>) {
      throw const FormatException('Snapshot은 JSON object여야 합니다.');
    }
    final envelope = asStringMap(payload);
    final nested = envelope['snapshot'] ?? envelope['data'];
    if (strict && nested != null && nested is! Map<Object?, Object?>) {
      throw const FormatException('snapshot 필드는 JSON object여야 합니다.');
    }
    final json = nested is Map<Object?, Object?> ? asStringMap(nested) : envelope;
    if (strict) {
      _validateSnapshotJson(json, expectedLotId: expectedLotId);
    }
    final slotValues = json['slots'];
    final slots = slotValues is List<Object?>
        ? slotValues
            .map(asStringMap)
            .map(ParkingSlot.fromJson)
            .where((slot) => slot.id.isNotEmpty)
            .toList(growable: false)
        : fallback?.slots ?? const <ParkingSlot>[];
    final robotJson = asStringMap(json['robot']);
    final jobJson = asStringMap(json['job'] ?? json['activeJob']);

    return ParkingSnapshot(
      lotId: (json['lotId'] ??
              json['parkingLotId'] ??
              json['lot_id'] ??
              fallback?.lotId ??
              'demo-01')
          .toString(),
      updatedAt: _dateTime(
        json['updatedAt'] ?? json['updated_at'] ?? json['timestamp'],
        fallback?.updatedAt,
      ),
      slots: slots,
      robot: RobotSnapshot.fromJson(robotJson, fallback: fallback?.robot),
      job: JobSnapshot.fromJson(jobJson, fallback: fallback?.job),
    );
  }

  final String lotId;
  final DateTime updatedAt;
  final List<ParkingSlot> slots;
  final RobotSnapshot robot;
  final JobSnapshot job;

  Map<String, Object?> toJson() => <String, Object?>{
        'lotId': lotId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'slots': slots.map((slot) => slot.toJson()).toList(growable: false),
        'robot': robot.toJson(),
        'job': job.toJson(),
      };
}

class GatewayHealth {
  const GatewayHealth({required this.status, required this.mode});

  factory GatewayHealth.fromPayload(Object? payload) {
    final json = asStringMap(payload);
    return GatewayHealth(
      status: (json['status'] ?? '').toString(),
      mode: (json['mode'] ?? '').toString(),
    );
  }

  final String status;
  final String mode;

  bool get isHealthy => status.toLowerCase() == 'ok';
}

class GatewayCommandResult {
  const GatewayCommandResult({required this.requestId, this.snapshot});

  factory GatewayCommandResult.fromPayload(
    Object? payload, {
    ParkingSnapshot? fallback,
    bool strict = false,
    String? expectedLotId,
  }) {
    if (strict && payload is! Map<Object?, Object?>) {
      throw const FormatException('명령 응답은 JSON object여야 합니다.');
    }
    final json = asStringMap(payload);
    final snapshotPayload = json['snapshot'];
    final requestId =
        (json['requestId'] ?? json['request_id'] ?? '').toString().trim();
    if (strict && requestId.isEmpty) {
      throw const FormatException('명령 응답에 requestId가 없습니다.');
    }
    if (strict && snapshotPayload is! Map<Object?, Object?>) {
      throw const FormatException('명령 응답에 snapshot object가 없습니다.');
    }
    return GatewayCommandResult(
      requestId: requestId,
      snapshot: snapshotPayload is Map<Object?, Object?>
          ? ParkingSnapshot.fromPayload(
              snapshotPayload,
              fallback: fallback,
              strict: strict,
              expectedLotId: expectedLotId,
            )
          : null,
    );
  }

  final String requestId;
  final ParkingSnapshot? snapshot;
}

class GatewayEvent {
  const GatewayEvent({
    required this.type,
    required this.message,
    required this.snapshot,
  });

  factory GatewayEvent.fromPayload(
    Object? payload, {
    ParkingSnapshot? fallback,
    bool strict = false,
    String? expectedLotId,
  }) {
    if (strict && payload is! Map<Object?, Object?>) {
      throw const FormatException('이벤트는 JSON object여야 합니다.');
    }
    final json = asStringMap(payload);
    final type = (json['type'] ?? '').toString().trim();
    if (strict && type.isEmpty) {
      throw const FormatException('이벤트에 type이 없습니다.');
    }
    if (strict && json['snapshot'] is! Map<Object?, Object?>) {
      throw const FormatException('이벤트에 snapshot object가 없습니다.');
    }
    return GatewayEvent(
      type: type.isEmpty ? 'UNKNOWN' : type,
      message: (json['message'] ?? '').toString(),
      snapshot: ParkingSnapshot.fromPayload(
        json,
        fallback: fallback,
        strict: strict,
        expectedLotId: expectedLotId,
      ),
    );
  }

  final String type;
  final String message;
  final ParkingSnapshot snapshot;
}

Map<String, Object?> asStringMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

void _validateSnapshotJson(
  Map<String, Object?> json, {
  String? expectedLotId,
}) {
  final lotId = _requiredString(
    json['lotId'] ?? json['parkingLotId'] ?? json['lot_id'],
    'lotId',
  );
  if (expectedLotId != null && lotId != expectedLotId) {
    throw FormatException(
      'Snapshot lotId가 다릅니다: expected=$expectedLotId actual=$lotId',
    );
  }

  final updatedAt = _requiredString(
    json['updatedAt'] ?? json['updated_at'] ?? json['timestamp'],
    'updatedAt',
  );
  if (DateTime.tryParse(updatedAt) == null) {
    throw const FormatException('Snapshot updatedAt이 올바른 ISO-8601 시간이 아닙니다.');
  }

  final rawSlots = json['slots'];
  if (rawSlots is! List<Object?>) {
    throw const FormatException('Snapshot slots는 배열이어야 합니다.');
  }
  for (final rawSlot in rawSlots) {
    if (rawSlot is! Map<Object?, Object?>) {
      throw const FormatException('각 slot은 JSON object여야 합니다.');
    }
    final slot = asStringMap(rawSlot);
    _requiredString(slot['id'] ?? slot['slotId'] ?? slot['slot_id'], 'slot.id');
    _requiredString(slot['state'] ?? slot['status'], 'slot.state');
  }

  final rawRobot = json['robot'];
  if (rawRobot is! Map<Object?, Object?>) {
    throw const FormatException('Snapshot robot은 JSON object여야 합니다.');
  }
  final robot = asStringMap(rawRobot);
  _requiredString(robot['state'] ?? robot['status'], 'robot.state');
  _requiredPercentage(
    robot['batteryPct'] ?? robot['battery_pct'] ?? robot['battery'],
    'robot.batteryPct',
  );
  _requiredPercentage(
    robot['positionPct'] ?? robot['position_pct'] ?? robot['position'],
    'robot.positionPct',
  );

  final rawJob = json['job'] ?? json['activeJob'];
  if (rawJob is! Map<Object?, Object?>) {
    throw const FormatException('Snapshot job은 JSON object여야 합니다.');
  }
  final job = asStringMap(rawJob);
  _requiredString(job['state'] ?? job['status'], 'job.state');
  _requiredString(job['message'], 'job.message');
}

String _requiredString(Object? value, String field) {
  final parsed = value?.toString().trim() ?? '';
  if (parsed.isEmpty) {
    throw FormatException('Snapshot $field 값이 없습니다.');
  }
  return parsed;
}

void _requiredPercentage(Object? value, String field) {
  final parsed = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
    throw FormatException('Snapshot $field 값은 0~100 숫자여야 합니다.');
  }
}

String _wire(Object? value) => value?.toString().trim().toUpperCase() ?? '';

String? _nullableString(Object? value) {
  final string = value?.toString().trim();
  return string == null || string.isEmpty ? null : string;
}

int _boundedInt(Object? value, int fallback, int minimum, int maximum) {
  final parsed = value is num
      ? value.isFinite
          ? value.round()
          : null
      : int.tryParse(value?.toString() ?? '');
  return (parsed ?? fallback).clamp(minimum, maximum).toInt();
}

int? _nullableInt(Object? value) {
  if (value is num) {
    return value.isFinite ? value.round() : null;
  }
  return int.tryParse(value?.toString() ?? '');
}

DateTime _dateTime(Object? value, DateTime? fallback) {
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
      fallback ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
