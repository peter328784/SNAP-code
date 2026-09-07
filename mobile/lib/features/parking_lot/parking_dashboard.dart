// DropdownButtonFormField.value remains necessary for Flutter 3.19 support.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/contracts/parking_models.dart';
import '../../core/networking/pi_gateway_client.dart';
import '../../core/networking/pi_gateway_session.dart';

class ParkingDashboard extends StatefulWidget {
  const ParkingDashboard({
    required this.gatewayBaseUri,
    required this.lotId,
    required this.customerId,
    super.key,
  });

  final Uri gatewayBaseUri;
  final String lotId;
  final String customerId;

  @override
  State<ParkingDashboard> createState() => _ParkingDashboardState();
}

class _ParkingDashboardState extends State<ParkingDashboard>
    with WidgetsBindingObserver {
  late final PiGatewaySession _session;
  final Map<String, int> _expectedMinutes = <String, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = PiGatewaySession(
      client: PiGatewayClient(baseUri: widget.gatewayBaseUri),
      lotId: widget.lotId,
      customerId: widget.customerId,
    )..addListener(_onSessionChanged);
    unawaited(_session.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_session.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _session.snapshot;
    final isConnected =
        _session.connectionState == GatewayConnectionState.connected;
    final hasActiveJob = snapshot != null && _isActiveJob(snapshot.job.state);
    final canRunCommand =
        isConnected && !_session.isSubmitting && !hasActiveJob;
    final isFull = snapshot != null &&
        snapshot.slots.isNotEmpty &&
        snapshot.slots.every((slot) => slot.state != SlotState.available);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('S.N.A.P'),
            Text('Smart Navigation for Automated Parking',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '최신 현황 조회',
            onPressed:
                _session.isSubmitting ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Gateway 다시 연결',
            onPressed: () => unawaited(_session.reconnectNow()),
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (_session.isSubmitting ||
                _session.connectionState == GatewayConnectionState.connecting)
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _ConnectionCard(
              state: _session.connectionState,
              endpoint: widget.gatewayBaseUri,
              error: _session.lastError,
            ),
            const SizedBox(height: 16),
            if (snapshot == null)
              _EmptyState(
                isConnecting: _session.connectionState !=
                    GatewayConnectionState.disconnected,
                onRetry: () => unawaited(_session.reconnectNow()),
              )
            else ...<Widget>[
              _Overview(snapshot: snapshot),
              const SizedBox(height: 16),
              Text('내 차량', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (hasActiveJob)
                const _NoticeCard(
                  icon: Icons.smart_toy_outlined,
                  message: '현재 로봇이 작업 중입니다. 완료되면 다음 요청을 보낼 수 있습니다.',
                )
              else if (isFull)
                const _NoticeCard(
                  icon: Icons.block,
                  message: '현재 주차장이 만차입니다.',
                  isError: true,
                ),
              if (hasActiveJob || isFull) const SizedBox(height: 10),
              _VehicleList(
                vehicles: _session.vehicles,
                selectedMinutes: _expectedMinutes,
                canRunCommand: canRunCommand,
                isFull: isFull,
                isSubmitting: _session.isSubmitting,
                onExpectedMinutesChanged: (vehicle, minutes) {
                  setState(() => _expectedMinutes[vehicle.id] = minutes);
                },
                onParking: (vehicle) => unawaited(_requestParking(vehicle)),
                onRetrieval: (vehicle) => unawaited(_requestRetrieval(vehicle)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _session.isSubmitting
                    ? null
                    : () => unawaited(_registerVehicle()),
                icon: const Icon(Icons.add),
                label: const Text('다른 차량 등록하기'),
              ),
              const SizedBox(height: 16),
              _RobotAndJob(snapshot: snapshot),
              const SizedBox(height: 16),
              Text('주차장 현황', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              _SlotGrid(slots: snapshot.slots),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      await _session.refresh();
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _requestParking(CustomerVehicle vehicle) async {
    try {
      await _session.requestParking(
        vehicleId: vehicle.id,
        expectedMinutes:
            _expectedMinutes[vehicle.id] ?? vehicle.expectedMinutes ?? 60,
      );
      _showMessage('${vehicle.vehicleNumber} 입차 요청을 접수했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _requestRetrieval(CustomerVehicle vehicle) async {
    try {
      await _session.requestRetrieval(vehicleId: vehicle.id);
      _showMessage('${vehicle.vehicleNumber} 출차 요청을 접수했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _registerVehicle() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('다른 차량 등록하기'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: '차량 번호',
            hintText: '예: 12가3456',
            counterText: '',
          ),
          onSubmitted: (submitted) => Navigator.of(context).pop(submitted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) {
      return;
    }
    final vehicleNumber = value.trim().toUpperCase();
    if (vehicleNumber.isEmpty || vehicleNumber.length > 32) {
      _showMessage('차량 번호를 1~32자로 입력해 주세요.', isError: true);
      return;
    }
    try {
      final vehicle = await _session.registerVehicle(
        vehicleNumber: vehicleNumber,
      );
      _expectedMinutes.putIfAbsent(vehicle.id, () => 60);
      _showMessage('$vehicleNumber 차량을 등록했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  bool _isActiveJob(JobState state) {
    return switch (state) {
      JobState.requested ||
      JobState.running ||
      JobState.vehicleDetected ||
      JobState.movingToVehicle ||
      JobState.lifting ||
      JobState.movingToSlot ||
      JobState.retrieving ||
      JobState.returning =>
        true,
      _ => false,
    };
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      color: color.withAlpha(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _VehicleList extends StatelessWidget {
  const _VehicleList({
    required this.vehicles,
    required this.selectedMinutes,
    required this.canRunCommand,
    required this.isFull,
    required this.isSubmitting,
    required this.onExpectedMinutesChanged,
    required this.onParking,
    required this.onRetrieval,
  });

  final List<CustomerVehicle> vehicles;
  final Map<String, int> selectedMinutes;
  final bool canRunCommand;
  final bool isFull;
  final bool isSubmitting;
  final void Function(CustomerVehicle vehicle, int minutes)
      onExpectedMinutesChanged;
  final ValueChanged<CustomerVehicle> onParking;
  final ValueChanged<CustomerVehicle> onRetrieval;

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              Icon(Icons.directions_car_outlined, size: 40),
              SizedBox(height: 10),
              Text('등록된 차량이 없습니다.'),
              SizedBox(height: 4),
              Text('아래 버튼에서 첫 차량 번호를 등록해 주세요.'),
            ],
          ),
        ),
      );
    }

    return Column(
      children: vehicles
          .map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VehicleCard(
                vehicle: vehicle,
                expectedMinutes: selectedMinutes[vehicle.id] ??
                    vehicle.expectedMinutes ??
                    60,
                canRunCommand: canRunCommand,
                isFull: isFull,
                isSubmitting: isSubmitting,
                onExpectedMinutesChanged: (minutes) =>
                    onExpectedMinutesChanged(vehicle, minutes),
                onParking: () => onParking(vehicle),
                onRetrieval: () => onRetrieval(vehicle),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.expectedMinutes,
    required this.canRunCommand,
    required this.isFull,
    required this.isSubmitting,
    required this.onExpectedMinutesChanged,
    required this.onParking,
    required this.onRetrieval,
  });

  final CustomerVehicle vehicle;
  final int expectedMinutes;
  final bool canRunCommand;
  final bool isFull;
  final bool isSubmitting;
  final ValueChanged<int> onExpectedMinutesChanged;
  final VoidCallback onParking;
  final VoidCallback onRetrieval;

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(vehicle.state);
    final selectedMinutes =
        const <int>[60, 120, 180, 240].contains(expectedMinutes)
            ? expectedMinutes
            : 60;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.directions_car),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vehicle.vehicleNumber,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  side: BorderSide(color: stateColor),
                  label: Text(
                    _stateLabel(vehicle.state),
                    style: TextStyle(color: stateColor),
                  ),
                ),
              ],
            ),
            if (vehicle.slotId != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '배정 주차면: ${vehicle.slotId}번',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (!vehicle.state.canRequestParking &&
                vehicle.expectedMinutes != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '예상 주차 시간: ${_durationLabel(vehicle.expectedMinutes!)}',
              ),
            ],
            if (vehicle.state.canRequestParking) ...<Widget>[
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: selectedMinutes,
                decoration: const InputDecoration(labelText: '예상 주차 시간'),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem(value: 60, child: Text('1시간')),
                  DropdownMenuItem(value: 120, child: Text('2시간')),
                  DropdownMenuItem(value: 180, child: Text('3시간')),
                  DropdownMenuItem(value: 240, child: Text('4시간 이상')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onExpectedMinutesChanged(value);
                  }
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canRunCommand && !isFull ? onParking : null,
                icon: const Icon(Icons.local_parking),
                label: Text(isSubmitting ? '요청 처리 중…' : '입차 요청'),
              ),
            ] else if (vehicle.state.canRequestRetrieval) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canRunCommand ? onRetrieval : null,
                icon: const Icon(Icons.exit_to_app),
                label: Text(isSubmitting ? '요청 처리 중…' : '원터치 출차 요청'),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 10),
              Text(_stateDescription(vehicle.state)),
            ],
          ],
        ),
      ),
    );
  }

  static Color _stateColor(VehicleState state) {
    return switch (state) {
      VehicleState.readyToPark || VehicleState.retrieved => Colors.teal,
      VehicleState.parked => Colors.blue,
      VehicleState.parkingRequested ||
      VehicleState.parkingInProgress ||
      VehicleState.retrievalRequested ||
      VehicleState.retrieving =>
        Colors.orange,
      VehicleState.error || VehicleState.unknown => Colors.red,
    };
  }

  static String _stateLabel(VehicleState state) {
    return switch (state) {
      VehicleState.readyToPark => '입차 준비',
      VehicleState.parkingRequested => '입차 대기',
      VehicleState.parkingInProgress => '입차 중',
      VehicleState.parked => '주차 중',
      VehicleState.retrievalRequested => '출차 대기',
      VehicleState.retrieving => '출차 중',
      VehicleState.retrieved => '출차 완료',
      VehicleState.error => '확인 필요',
      VehicleState.unknown => '상태 확인 중',
    };
  }

  static String _stateDescription(VehicleState state) {
    return switch (state) {
      VehicleState.parkingRequested => '입차 요청이 접수되었습니다.',
      VehicleState.parkingInProgress => '로봇이 차량을 주차하고 있습니다.',
      VehicleState.retrievalRequested => '출차 요청이 접수되었습니다.',
      VehicleState.retrieving => '로봇이 차량을 출구로 이동하고 있습니다.',
      VehicleState.error => '관리자 확인이 필요합니다.',
      VehicleState.unknown => '차량 상태를 확인하고 있습니다.',
      _ => '',
    };
  }

  static String _durationLabel(int minutes) {
    return switch (minutes) {
      60 => '1시간',
      120 => '2시간',
      180 => '3시간',
      240 => '4시간 이상',
      _ => '$minutes분',
    };
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.endpoint,
    required this.error,
  });

  final GatewayConnectionState state;
  final Uri endpoint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      GatewayConnectionState.connected => Colors.green,
      GatewayConnectionState.connecting ||
      GatewayConnectionState.reconnecting =>
        Colors.orange,
      GatewayConnectionState.disconnected => Colors.red,
    };
    final label = switch (state) {
      GatewayConnectionState.connected => 'Gateway 연결됨',
      GatewayConnectionState.connecting => 'Gateway 연결 중',
      GatewayConnectionState.reconnecting => '재연결 및 현황 동기화 중',
      GatewayConnectionState.disconnected => 'Gateway 연결 끊김',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(endpoint.toString(),
                style: Theme.of(context).textTheme.bodySmall),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.snapshot});

  final ParkingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final available = snapshot.slots
        .where((slot) => slot.state == SlotState.available)
        .length;
    final occupied =
        snapshot.slots.where((slot) => slot.state == SlotState.occupied).length;
    final reserved =
        snapshot.slots.where((slot) => slot.state == SlotState.reserved).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(snapshot.lotId,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(_formatTime(snapshot.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(child: _Metric(label: '빈자리', value: '$available')),
                Expanded(child: _Metric(label: '주차', value: '$occupied')),
                Expanded(child: _Metric(label: '예약', value: '$reserved')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.slots});

  final List<ParkingSlot> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Gateway가 주차면 정보를 보내지 않았습니다.'),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 3 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: slots
              .map((slot) =>
                  SizedBox(width: width, child: _SlotCard(slot: slot)))
              .toList(growable: false),
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});

  final ParkingSlot slot;

  @override
  Widget build(BuildContext context) {
    final color = switch (slot.state) {
      SlotState.available => Colors.green,
      SlotState.reserved => Colors.orange,
      SlotState.occupied => Colors.blueGrey,
      SlotState.unavailable || SlotState.unknown => Colors.red,
    };
    final label = switch (slot.state) {
      SlotState.available => '이용 가능',
      SlotState.reserved => '예약',
      SlotState.occupied => '주차 중',
      SlotState.unavailable => '이용 불가',
      SlotState.unknown => '상태 미확인',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('${slot.id}번',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Icon(Icons.local_parking, color: color),
              ],
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _RobotAndJob extends StatelessWidget {
  const _RobotAndJob({required this.snapshot});

  final ParkingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('주차 로봇', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(_jobLabel(snapshot.job.state)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(_robotLabel(snapshot.robot.state))),
                if (_isMoving(snapshot.job.state))
                  Chip(label: Text('이동 진행 ${snapshot.robot.positionPct}%')),
                if (snapshot.job.targetSlot != null)
                  Chip(label: Text('배정 주차면 ${snapshot.job.targetSlot}번')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isMoving(JobState state) {
    return switch (state) {
      JobState.running ||
      JobState.movingToVehicle ||
      JobState.movingToSlot ||
      JobState.retrieving ||
      JobState.returning =>
        true,
      _ => false,
    };
  }

  String _jobLabel(JobState state) {
    return switch (state) {
      JobState.idle => '대기 위치에서 다음 요청을 기다리고 있습니다.',
      JobState.running => '로봇 작업을 진행하고 있습니다.',
      JobState.requested ||
      JobState.vehicleDetected ||
      JobState.movingToVehicle ||
      JobState.lifting ||
      JobState.movingToSlot =>
        '입차 작업을 진행하고 있습니다.',
      JobState.parked || JobState.returning => '작업을 마치고 대기 위치로 복귀 중입니다.',
      JobState.retrieving => '출차 작업을 진행하고 있습니다.',
      JobState.failed || JobState.emergencyStop => '안전 확인이 필요합니다.',
      JobState.unknown => '로봇 상태를 확인하고 있습니다.',
    };
  }

  String _robotLabel(String rawState) {
    return switch (rawState.trim().toUpperCase()) {
      'READY' || 'IDLE' || 'DONE' || 'IDLE_AT_STANDBY' => '대기 위치',
      'MOVING_TO_ENTRY' => '입구로 이동 중',
      'TRACING' ||
      'MOVING' ||
      'MOVING_TO_SLOT' ||
      'CARRYING_TO_SLOT' =>
        '주차장 통로 이동 중',
      'APPROACHING' ||
      'MOVING_TO_VEHICLE' ||
      'MOVING_TO_PARKED_VEHICLE' =>
        '차량으로 이동 중',
      'GRIPPING' || 'LIFTING' || 'ACQUIRING_VEHICLE' => '차량 준비 중',
      'CARRYING_TO_EXIT' => '출구로 이동 중',
      'REVERSING' || 'RETURNING' || 'RETURNING_TO_STANDBY' => '대기 위치 복귀 중',
      'OFFLINE' => '로봇 연결 확인 필요',
      'FAULT' => '로봇 안전 확인 필요',
      _ => rawState,
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isConnecting, required this.onRetry});

  final bool isConnecting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(isConnecting ? Icons.sync : Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(isConnecting ? '주차장 현황을 불러오는 중입니다.' : '현황을 불러오지 못했습니다.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 연결')),
          ],
        ),
      ),
    );
  }
}
