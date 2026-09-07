// withOpacity and DropdownButtonFormField.value preserve Flutter 3.19 support.
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/snap_theme.dart';
import '../../core/contracts/parking_models.dart';
import '../../core/networking/pi_gateway_session.dart';

enum ParkingTab { home, vehicles, activity, settings }

abstract final class SnapAssets {
  static const robotHero = 'assets/images/robot-hero.png';
  static const carHero = 'assets/images/car-hero.png';
  static const robotTop = 'assets/images/robot-top.png';
  static const carTop = 'assets/images/car-top.png';
}

class ParkingSelectionPage extends StatelessWidget {
  const ParkingSelectionPage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicles,
    required this.selectedVehicle,
    required this.expectedMinutes,
    required this.isSubmitting,
    required this.isFull,
    required this.onRefresh,
    required this.onVehicleSelected,
    required this.onExpectedMinutesChanged,
    required this.onParking,
    required this.onRegisterVehicle,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final List<CustomerVehicle> vehicles;
  final CustomerVehicle? selectedVehicle;
  final int expectedMinutes;
  final bool isSubmitting;
  final bool isFull;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onVehicleSelected;
  final ValueChanged<int> onExpectedMinutesChanged;
  final VoidCallback onParking;
  final VoidCallback onRegisterVehicle;

  @override
  Widget build(BuildContext context) {
    final available = snapshot.slots
        .where((slot) => slot.state == SlotState.available)
        .length;
    final canRequest = connectionState == GatewayConnectionState.connected &&
        !isSubmitting &&
        !isFull &&
        selectedVehicle?.state.canRequestParking == true;

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '주차하기',
          subtitle: 'S.N.A.P  ·  ${snapshot.lotId}',
          connectionState: connectionState,
          centered: true,
        ),
        const SizedBox(height: 22),
        if (vehicles.isEmpty)
          _EmptyVehiclePanel(onRegisterVehicle: onRegisterVehicle)
        else ...<Widget>[
          _VehiclePicker(
            vehicles: vehicles,
            selectedVehicle: selectedVehicle,
            onChanged: onVehicleSelected,
          ),
          const SizedBox(height: 16),
          SnapSurface(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '$available자리',
                        style: const TextStyle(
                          color: SnapColors.electricBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const TextSpan(text: ' 이용 가능'),
                    ],
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 5),
                Text(
                  '주차면 현황',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                ParkingLotDiagram(
                  slots: snapshot.slots,
                  targetSlot: _isActiveJobState(snapshot.job.state)
                      ? snapshot.job.targetSlot
                      : null,
                  robotProgress: snapshot.robot.positionPct,
                  compact: true,
                ),
                const SizedBox(height: 20),
                Text(
                  '예상 주차 시간',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                DurationSelector(
                  value: expectedMinutes,
                  enabled: !isSubmitting,
                  onChanged: onExpectedMinutesChanged,
                ),
                const SizedBox(height: 18),
                SnapActionButton(
                  buttonKey: const Key('parking-action'),
                  onPressed: canRequest ? onParking : null,
                  label: isSubmitting
                      ? '요청 처리 중…'
                      : isFull
                          ? '현재 만차입니다'
                          : selectedVehicle?.state.canRequestParking == false
                              ? '차량 상태를 확인해 주세요'
                              : '주차 요청',
                  icon: Icons.arrow_forward_rounded,
                ),
                const SizedBox(height: 11),
                Text(
                  '예상 시간에 맞춰 Gateway가 최적의 주차면을 자동 배정합니다.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class ParkingProgressPage extends StatelessWidget {
  const ParkingProgressPage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicle,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final CustomerVehicle? vehicle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final isRetrieval = _isRetrievalProgress(snapshot, vehicle);
    final stage = _jobStage(snapshot.job.state, snapshot.robot.state);
    final position = snapshot.robot.positionPct.clamp(0, 100).toInt();
    final jobMessage = snapshot.job.message.trim();
    final title = vehicle == null
        ? '로봇 작업 중'
        : isRetrieval
            ? '출차 진행 중'
            : '주차 진행 중';

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: title,
          subtitle: vehicle?.vehicleNumber ?? 'S.N.A.P AUTOMATED PARKING',
          connectionState: connectionState,
          centered: true,
        ),
        const SizedBox(height: 20),
        SnapSurface(
          padding: const EdgeInsets.all(12),
          child: ParkingLotDiagram(
            slots: snapshot.slots,
            targetSlot: snapshot.job.targetSlot,
            robotProgress: position,
            carryingVehicle: true,
          ),
        ),
        const SizedBox(height: 16),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          vehicle == null
                              ? '다른 차량의 작업을 진행하고 있어요'
                              : jobMessage.isNotEmpty
                                  ? jobMessage
                                  : _jobHeadline(
                                      snapshot.job.state,
                                      isRetrieval,
                                    ),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        if (snapshot.job.targetSlot != null) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            '배정 주차면 ${slotLabel(snapshot.job.targetSlot!)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '$position%',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: SnapColors.electricBlue,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '경로 위치 $position%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 24),
              JobStepper(activeStage: stage, isRetrieval: isRetrieval),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _PulsingDot(
                    color: connectionState == GatewayConnectionState.connected
                        ? SnapColors.electricBlue
                        : SnapColors.warning,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    connectionState == GatewayConnectionState.connected
                        ? '실시간 연결됨'
                        : '연결 복구 중',
                    style: TextStyle(
                      color: connectionState == GatewayConnectionState.connected
                          ? SnapColors.electricBlue
                          : SnapColors.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '앱을 닫아도 로봇 작업은 Gateway에서 계속됩니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ParkingCompletePage extends StatelessWidget {
  const ParkingCompletePage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicle,
    required this.isSubmitting,
    required this.onRefresh,
    required this.onRetrieval,
    this.onHome,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final CustomerVehicle vehicle;
  final bool isSubmitting;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetrieval;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final slot = vehicle.slotId ?? '-';

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '주차 완료',
          subtitle: vehicle.vehicleNumber,
          connectionState: connectionState,
          centered: true,
          statusColor: SnapColors.success,
        ),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SnapColors.success.withOpacity(0.12),
              border: Border.all(
                color: SnapColors.success.withOpacity(0.55),
                width: 1.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: SnapColors.success.withOpacity(0.22),
                  blurRadius: 26,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: SnapColors.success,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '안전하게 주차했어요',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            children: <Widget>[
              Semantics(
                label:
                    '${vehicle.vehicleNumber} 차량이 ${slotLabel(slot)}번 주차면에 안전하게 주차되었습니다.',
                image: true,
                child: _CompletedParkingBay(
                  slot: slot,
                  slots: snapshot.slots,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SummaryMetric(
                      label: '차량 정보',
                      value: vehicle.vehicleNumber,
                    ),
                  ),
                  _MetricDivider(),
                  Expanded(
                    child: _SummaryMetric(
                      label: '주차면',
                      value: slotLabel(slot),
                      highlighted: true,
                    ),
                  ),
                  _MetricDivider(),
                  Expanded(
                    child: _SummaryMetric(
                      label: '주차 시간',
                      value: vehicle.expectedMinutes == null
                          ? '-'
                          : '${durationLabel(vehicle.expectedMinutes)} 예정',
                    ),
                  ),
                ],
              ),
              if (vehicle.updatedAt != null) ...<Widget>[
                const SizedBox(height: 18),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '입차 완료 ${formatClock(vehicle.updatedAt!)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SnapActionButton(
                buttonKey: const Key('retrieval-action'),
                onPressed:
                    connectionState == GatewayConnectionState.connected &&
                            !isSubmitting &&
                            vehicle.state.canRequestRetrieval
                        ? onRetrieval
                        : null,
                label: isSubmitting ? '요청 처리 중…' : '출차 요청',
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: 10),
              Text(
                '출차 요청 후 로봇이 차량을 입구로 이동합니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onHome,
                child: const Text('홈으로'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VehicleManagementPage extends StatelessWidget {
  const VehicleManagementPage({
    required this.connectionState,
    required this.vehicles,
    required this.selectedVehicleId,
    required this.registrationController,
    required this.isSubmitting,
    required this.onRefresh,
    required this.onVehicleSelected,
    required this.onRegister,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final List<CustomerVehicle> vehicles;
  final String? selectedVehicleId;
  final TextEditingController registrationController;
  final bool isSubmitting;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onVehicleSelected;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '내 차량',
          subtitle: '주차와 출차에 사용할 차량을 관리합니다.',
          connectionState: connectionState,
        ),
        const SizedBox(height: 10),
        _HeroStage(
          height: 270,
          glowColor: SnapColors.electricBlue,
          child: Image.asset(
            SnapAssets.carHero,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
            cacheWidth: 1200,
          ),
        ),
        const SizedBox(height: 12),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: registrationController,
            builder: (context, value, _) {
              final normalized = value.text.trim();
              final valid = _isValidVehicleNumber(normalized);
              final canRegister = connected && !isSubmitting && valid;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    vehicles.isEmpty ? '차량을 등록하세요' : '새 차량 등록',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('registration-field'),
                    controller: registrationController,
                    maxLength: 32,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: '차량번호',
                      hintText: '12가 3456',
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      suffixIcon: valid
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: SnapColors.success,
                            )
                          : null,
                    ),
                    onSubmitted: canRegister ? (_) => onRegister() : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    valid ? '등록 가능한 차량번호입니다.' : '차량번호를 정확히 입력해 주세요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: valid
                              ? _successColor(context)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  SnapActionButton(
                    buttonKey: const Key('registration-action'),
                    onPressed: canRegister ? onRegister : null,
                    label: isSubmitting ? '등록 중…' : '차량 등록',
                    blackInLight: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: SnapColors.electricBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '등록한 차량으로 주차와 출차를 요청할 수 있어요.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        if (vehicles.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            '등록 차량',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          ...vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VehicleTile(
                key: Key('vehicle-${vehicle.id}'),
                vehicle: vehicle,
                selected: vehicle.id == selectedVehicleId,
                onTap: () => onVehicleSelected(vehicle.id),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({
    required this.connectionState,
    required this.vehicles,
    required this.snapshot,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final List<CustomerVehicle> vehicles;
  final ParkingSnapshot? snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '이용 기록',
          subtitle: 'Gateway가 제공하는 현재 차량 상태',
          connectionState: connectionState,
        ),
        const SizedBox(height: 20),
        if (vehicles.isEmpty)
          const SnapSurface(
            padding: EdgeInsets.all(28),
            child: _CenteredMessage(
              icon: Icons.history_rounded,
              title: '표시할 차량 상태가 없습니다.',
              message: '차량을 등록하면 현재 주차 상태를 여기에서 확인할 수 있어요.',
            ),
          )
        else
          ...vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActivityTile(vehicle: vehicle),
            ),
          ),
        const SizedBox(height: 8),
        SnapSurface(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                color: SnapColors.electricBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '현재 Gateway 계약은 장기 이용 이력을 제공하지 않습니다. '
                  '이 화면은 실시간 차량 상태와 마지막 상태 변경 시각을 표시합니다.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (snapshot != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '마지막 동기화 ${formatClock(snapshot!.updatedAt)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.connectionState,
    required this.endpoint,
    required this.snapshot,
    required this.lastError,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onReconnect,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final Uri endpoint;
  final ParkingSnapshot? snapshot;
  final String? lastError;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onReconnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;
    final robotHealthy = connected &&
        snapshot != null &&
        _isHealthyRobotState(snapshot!.robot.state);

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '설정',
          subtitle: 'S.N.A.P AUTOMATED PARKING',
          connectionState: connectionState,
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _EndpointCard(endpoint: endpoint, connected: connected),
              const SizedBox(height: 14),
              ConnectionStatusRow(
                label: 'Gateway',
                value: connected ? '정상' : '연결 확인 중',
                healthy: connected,
              ),
              ConnectionStatusRow(
                label: '실시간 이벤트',
                value: connected ? '연결됨' : '재연결 대기',
                healthy: connected,
              ),
              ConnectionStatusRow(
                label: '주차 로봇',
                value: snapshot == null
                    ? '상태 미확인'
                    : robotLabel(snapshot!.robot.state),
                healthy: robotHealthy,
              ),
              if (lastError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  lastError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SnapColors.warning,
                      ),
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onReconnect,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Gateway 다시 연결'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '화면 모드',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Light와 Dark는 같은 정보 구조와 S.N.A.P 블루를 사용합니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              ThemeModeSelector(
                value: themeMode,
                onChanged: onThemeModeChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({
    required this.connectionState,
    required this.endpoint,
    required this.error,
    required this.onReconnect,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final Uri endpoint;
  final String? error;
  final VoidCallback onReconnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;
    final connecting = connectionState == GatewayConnectionState.connecting ||
        connectionState == GatewayConnectionState.reconnecting;

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        const _LargeBrandMark(),
        const SizedBox(height: 12),
        _HeroStage(
          height: 310,
          glowColor: SnapColors.electricBlue,
          child: Image.asset(
            SnapAssets.robotHero,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
            cacheWidth: 1000,
          ),
        ),
        const SizedBox(height: 12),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (connecting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    _PulsingDot(
                      color:
                          connected ? SnapColors.success : SnapColors.warning,
                    ),
                  const SizedBox(width: 9),
                  Text(
                    connectionLabel(connectionState),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConnectionStatusRow(
                label: '게이트웨이',
                value: connected ? '정상' : '연결 확인 중',
                healthy: connected,
              ),
              ConnectionStatusRow(
                label: '센서',
                value: connected ? '이벤트 수신 중' : '상태 확인 중',
                healthy: false,
              ),
              ConnectionStatusRow(
                label: '로봇',
                value: connected ? '준비 확인 중' : '연결 대기',
                healthy: false,
              ),
              const SizedBox(height: 12),
              _EndpointCard(endpoint: endpoint, connected: connected),
              if (error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SnapColors.warning,
                      ),
                ),
              ],
              const SizedBox(height: 16),
              SnapActionButton(
                buttonKey: const Key('connection-action'),
                onPressed: onReconnect,
                label: connected ? '연결 새로고침' : '연결 설정',
                icon: Icons.arrow_forward_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SnapPageHeader extends StatelessWidget {
  const SnapPageHeader({
    required this.title,
    required this.subtitle,
    required this.connectionState,
    this.centered = false,
    this.statusColor,
    super.key,
  });

  final String title;
  final String subtitle;
  final GatewayConnectionState connectionState;
  final bool centered;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;
    final badge = _ConnectionBadge(
      connected: connected,
      statusColor: statusColor,
    );
    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.35,
              ),
        ),
      ],
    );

    if (centered) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(width: 42),
          Expanded(child: titleBlock),
          badge,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 12),
        _MiniBrandMark(statusColor: statusColor),
      ],
    );
  }
}

class SnapSurface extends StatelessWidget {
  const SnapSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.62),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.22 : 0.055),
            blurRadius: dark ? 24 : 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SnapActionButton extends StatelessWidget {
  const SnapActionButton({
    required this.buttonKey,
    required this.onPressed,
    required this.label,
    this.icon,
    this.blackInLight = false,
    super.key,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool blackInLight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    final useBlack = blackInLight && !dark;
    final colors = useBlack
        ? const <Color>[Color(0xFF24272B), Color(0xFF050607)]
        : dark
            ? const <Color>[Color(0xFF229BFA), Color(0xFF0068DD)]
            : const <Color>[Color(0xFF147FE5), Color(0xFF0058C2)];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: colors) : null,
        color: enabled
            ? null
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        boxShadow: enabled && !useBlack
            ? <BoxShadow>[
                BoxShadow(
                  color: SnapColors.electricBlue.withOpacity(dark ? 0.36 : 0.2),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label),
            if (icon != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(icon, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class DurationSelector extends StatelessWidget {
  const DurationSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = <int>[60, 120, 180, 240];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.7),
        ),
      ),
      child: Row(
        children: values.map((minutes) {
          final selected = value == minutes;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              enabled: enabled,
              label: '$minutes분',
              excludeSemantics: true,
              child: InkWell(
                onTap: enabled ? () => onChanged(minutes) : null,
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: selected
                        ? <BoxShadow>[
                            BoxShadow(
                              color: SnapColors.electricBlue.withOpacity(0.24),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    '$minutes분',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class ParkingLotDiagram extends StatelessWidget {
  const ParkingLotDiagram({
    required this.slots,
    required this.robotProgress,
    this.targetSlot,
    this.compact = false,
    this.carryingVehicle = false,
    super.key,
  });

  final List<ParkingSlot> slots;
  final String? targetSlot;
  final int robotProgress;
  final bool compact;
  final bool carryingVehicle;

  @override
  Widget build(BuildContext context) {
    final normalized = List<ParkingSlot>.generate(6, (index) {
      final id = '${index + 1}';
      for (final slot in slots) {
        if (_sameSlot(slot.id, id)) {
          return slot;
        }
      }
      return ParkingSlot(id: id, state: SlotState.unknown);
    });
    final left = <ParkingSlot>[normalized[0], normalized[2], normalized[4]];
    final right = <ParkingSlot>[normalized[1], normalized[3], normalized[5]];
    final position = robotProgress.clamp(0, 100).toInt();
    final progress = position / 100;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final availableWidth = MediaQuery.sizeOf(context).width - 60;
    final diagramHeight = (availableWidth * (compact ? 1.06 : 1.0))
        .clamp(392.0, compact ? 520.0 : 540.0)
        .toDouble();

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: carryingVehicle
          ? '주차 로봇이 차량을 ${targetSlot == null ? '배정된 주차면' : '${slotLabel(targetSlot!)}번 주차면'}으로 이동 중, $position퍼센트'
          : '주차면 6곳의 실시간 현황, 로봇 위치 $position퍼센트',
      child: Container(
        height: diagramHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const <Color>[Color(0xFF15191E), Color(0xFF080A0D)]
                : const <Color>[Color(0xFFF5F7F9), Color(0xFFE8EDF2)],
          ),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.outlineVariant.withOpacity(0.7),
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _LotRoutePainter(
                  targetSlot: targetSlot,
                  robotProgress: position,
                  carryingVehicle: carryingVehicle,
                  dark: dark,
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _BayColumn(
                        slots: left,
                        targetSlot: targetSlot,
                      ),
                    ),
                    SizedBox(width: compact ? 68 : 82),
                    Expanded(
                      child: _BayColumn(
                        slots: right,
                        targetSlot: targetSlot,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                alignment: Alignment(0, -0.7 + progress * 1.4),
                child: _RobotCarrier(
                  compact: compact,
                  carryingVehicle: carryingVehicle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BayColumn extends StatelessWidget {
  const _BayColumn({required this.slots, required this.targetSlot});

  final List<ParkingSlot> slots;
  final String? targetSlot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: slots.map((slot) {
        final numeric = int.tryParse(slot.id)?.toString() ?? slot.id;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ParkingBay(
              key: Key('slot-$numeric'),
              slot: slot,
              highlighted:
                  targetSlot != null && _sameSlot(slot.id, targetSlot!),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class ParkingBay extends StatelessWidget {
  const ParkingBay({
    required this.slot,
    required this.highlighted,
    super.key,
  });

  final ParkingSlot slot;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final reserved = slot.state == SlotState.reserved;
    final locked = reserved ||
        slot.state == SlotState.unavailable ||
        slot.state == SlotState.unknown;
    final occupied = slot.state == SlotState.occupied;
    final active = highlighted || reserved;
    final borderColor = active
        ? SnapColors.electricBlue
        : Theme.of(context).colorScheme.outline.withOpacity(0.42);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: active
            ? SnapColors.electricBlue.withOpacity(0.09)
            : Theme.of(context).colorScheme.surface.withOpacity(0.32),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor, width: active ? 1.7 : 1),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: SnapColors.electricBlue.withOpacity(0.22),
                  blurRadius: 15,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Center(
              child: Text(
                slotLabel(slot.id),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: active
                          ? SnapColors.electricBlue
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          if (slot.state == SlotState.available)
            const Positioned(
              top: 12,
              right: 12,
              child: _PulsingDot(color: SnapColors.success, size: 7),
            ),
          if (locked)
            Positioned(
              top: 9,
              right: 9,
              child: Icon(
                Icons.lock_rounded,
                size: 17,
                color: active
                    ? SnapColors.electricBlue
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (occupied)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 20, 30, 8),
                child: Opacity(
                  opacity: 0.42,
                  child: Image.asset(
                    SnapAssets.carTop,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    cacheWidth: 180,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RobotCarrier extends StatelessWidget {
  const _RobotCarrier({
    required this.compact,
    required this.carryingVehicle,
  });

  final bool compact;
  final bool carryingVehicle;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 50.0 : 64.0;
    final height = compact ? 88.0 : 116.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            bottom: 0,
            width: width,
            height: height * 0.64,
            child: Image.asset(
              SnapAssets.robotTop,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              filterQuality: FilterQuality.high,
              cacheWidth: 180,
            ),
          ),
          if (carryingVehicle)
            Positioned(
              top: -height * 0.06,
              width: width * 1.12,
              height: height * 0.86,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: SnapColors.electricBlue.withOpacity(0.22),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Image.asset(
                  SnapAssets.carTop,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  filterQuality: FilterQuality.high,
                  cacheWidth: 220,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LotRoutePainter extends CustomPainter {
  const _LotRoutePainter({
    required this.targetSlot,
    required this.robotProgress,
    required this.carryingVehicle,
    required this.dark,
  });

  final String? targetSlot;
  final int robotProgress;
  final bool carryingVehicle;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final lanePaint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withOpacity(0.12)
      ..style = PaintingStyle.fill;
    for (double y = 18; y < size.height; y += 18) {
      canvas.drawCircle(Offset(size.width / 2, y), 1.5, lanePaint);
    }

    final target = int.tryParse(targetSlot ?? '');
    if (target == null || target < 1 || target > 6) {
      return;
    }
    final row = (target - 1) ~/ 2;
    final right = target.isEven;
    final start = Offset(
      size.width / 2,
      size.height * (0.15 + robotProgress.clamp(0, 100) / 100 * 0.7),
    );
    final end = Offset(
      size.width * (right ? 0.72 : 0.28),
      size.height * ((row + 0.5) / 3),
    );
    final corner = Offset(start.dx, end.dy);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(corner.dx, corner.dy)
      ..lineTo(end.dx, end.dy);
    final glow = Paint()
      ..color = SnapColors.electricBlue.withOpacity(0.2)
      ..strokeWidth = carryingVehicle ? 11 : 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final route = Paint()
      ..color = SnapColors.electricBlue.withOpacity(0.9)
      ..strokeWidth = carryingVehicle ? 3.2 : 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, glow)
      ..drawPath(path, route);

    final angle = math.atan2(end.dy - corner.dy, end.dx - corner.dx);
    const arrowLength = 10.0;
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * math.cos(angle - math.pi / 5),
        end.dy - arrowLength * math.sin(angle - math.pi / 5),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowLength * math.cos(angle + math.pi / 5),
        end.dy - arrowLength * math.sin(angle + math.pi / 5),
      );
    canvas.drawPath(arrow, route);
  }

  @override
  bool shouldRepaint(covariant _LotRoutePainter oldDelegate) {
    return targetSlot != oldDelegate.targetSlot ||
        robotProgress != oldDelegate.robotProgress ||
        carryingVehicle != oldDelegate.carryingVehicle ||
        dark != oldDelegate.dark;
  }
}

class JobStepper extends StatelessWidget {
  const JobStepper({
    required this.activeStage,
    required this.isRetrieval,
    super.key,
  });

  final int activeStage;
  final bool isRetrieval;

  @override
  Widget build(BuildContext context) {
    final labels = isRetrieval
        ? const <String>['요청 접수', '차량 확인', '출차 중', '완료']
        : const <String>['요청 접수', '차량 이동', '주차 중', '완료'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(labels.length, (index) {
        final done = index < activeStage;
        final active = index == activeStage;
        return Expanded(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index <= activeStage
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? SnapColors.electricBlue
                          : active
                              ? SnapColors.electricBlue.withOpacity(0.14)
                              : Colors.transparent,
                      border: Border.all(
                        color: done || active
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: active ? 2 : 1,
                      ),
                      boxShadow: active
                          ? <BoxShadow>[
                              BoxShadow(
                                color:
                                    SnapColors.electricBlue.withOpacity(0.24),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: done
                        ? const Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: Colors.white,
                          )
                        : active
                            ? const Center(
                                child: CircleAvatar(
                                  radius: 4.5,
                                  backgroundColor: SnapColors.electricBlue,
                                ),
                              )
                            : null,
                  ),
                  if (index < labels.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index < activeStage
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                labels[index],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: done || active
                          ? SnapColors.electricBlue
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class VehicleTile extends StatelessWidget {
  const VehicleTile({
    required this.vehicle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CustomerVehicle vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SnapColors.electricBlue.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.directions_car_filled_outlined,
                  color: SnapColors.electricBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vehicle.vehicleNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vehicleStateLabel(vehicle.state),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (vehicle.slotId != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '주차면 ${slotLabel(vehicle.slotId!)}',
                    style: const TextStyle(
                      color: SnapColors.electricBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? SnapColors.electricBlue
                    : Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.vehicle, super.key});

  final CustomerVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SnapColors.electricBlue.withOpacity(0.1),
            ),
            child: const Icon(
              Icons.route_rounded,
              color: SnapColors.electricBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  vehicle.vehicleNumber,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(vehicleStateLabel(vehicle.state)),
                if (vehicle.updatedAt != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    formatClock(vehicle.updatedAt!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (vehicle.slotId != null)
            Text(
              slotLabel(vehicle.slotId!),
              style: const TextStyle(
                color: SnapColors.electricBlue,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class ConnectionStatusRow extends StatelessWidget {
  const ConnectionStatusRow({
    required this.label,
    required this.value,
    required this.healthy,
    super.key,
  });

  final String label;
  final String value;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
                Theme.of(context).colorScheme.outlineVariant.withOpacity(0.55),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: healthy ? SnapColors.success : SnapColors.warning,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: (healthy ? SnapColors.success : SnapColors.warning)
                      .withOpacity(0.28),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.settings_brightness_outlined, '시스템'),
      (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    ];
    return Row(
      children: options.map((option) {
        final selected = value == option.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: option == options.last ? 0 : 8),
            child: Semantics(
              button: true,
              selected: selected,
              label: '${option.$3} 화면 모드',
              excludeSemantics: true,
              child: InkWell(
                key: Key('theme-mode-${option.$1.name}'),
                onTap: () => onChanged(option.$1),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? SnapColors.electricBlue.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? SnapColors.electricBlue
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        option.$2,
                        color: selected
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        option.$3,
                        style: TextStyle(
                          color: selected
                              ? SnapColors.electricBlue
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class ParkingBayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.grey.withOpacity(0.3);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = SnapColors.electricBlue.withOpacity(0.72)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final centerLeft = size.width * 0.26;
    final centerRight = size.width * 0.74;
    final path = Path()
      ..moveTo(centerLeft, size.height)
      ..lineTo(centerLeft, 0)
      ..moveTo(centerRight, 0)
      ..lineTo(centerRight, size.height)
      ..moveTo(0, size.height - 1)
      ..lineTo(size.width, size.height - 1);
    canvas
      ..drawPath(path, linePaint)
      ..drawLine(
        Offset(centerLeft, 1),
        Offset(centerRight, 1),
        glowPaint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompletedParkingBay extends StatelessWidget {
  const _CompletedParkingBay({required this.slot, required this.slots});

  final String slot;
  final List<ParkingSlot> slots;

  @override
  Widget build(BuildContext context) {
    final orderedIds = slots.map((entry) => entry.id).toList()
      ..sort((left, right) {
        return (int.tryParse(left) ?? 1 << 30)
            .compareTo(int.tryParse(right) ?? 1 << 30);
      });
    final currentIndex = orderedIds.indexWhere((id) => _sameSlot(id, slot));
    final previous =
        currentIndex > 0 ? slotLabel(orderedIds[currentIndex - 1]) : '--';
    final next = currentIndex >= 0 && currentIndex < orderedIds.length - 1
        ? slotLabel(orderedIds[currentIndex + 1])
        : '--';
    return Container(
      height: 284,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: Theme.of(context).brightness == Brightness.dark
              ? const <Color>[Color(0xFF171B20), Color(0xFF090B0E)]
              : const <Color>[Color(0xFFF3F6F8), Color(0xFFE4E9ED)],
        ),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(child: CustomPaint(painter: ParkingBayPainter())),
          Positioned(
            top: 12,
            left: 12,
            child: Text(
              previous,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Text(
              next,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Positioned(
            top: 10,
            child: Text(
              slotLabel(slot),
              style: const TextStyle(
                color: SnapColors.electricBlue,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Positioned.fill(
            top: 38,
            bottom: 18,
            child: FractionallySizedBox(
              widthFactor: 0.4,
              child: Image.asset(
                SnapAssets.carTop,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.high,
                cacheWidth: 420,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children, required this.onRefresh});

  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({
    required this.vehicles,
    required this.selectedVehicle,
    required this.onChanged,
  });

  final List<CustomerVehicle> vehicles;
  final CustomerVehicle? selectedVehicle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedVehicle?.id,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.directions_car_outlined),
        labelText: '주차할 차량',
        suffixIcon: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: SnapColors.electricBlue,
          ),
        ),
      ),
      items: vehicles
          .map(
            (vehicle) => DropdownMenuItem<String>(
              value: vehicle.id,
              child: Text(vehicle.vehicleNumber),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _EmptyVehiclePanel extends StatelessWidget {
  const _EmptyVehiclePanel({required this.onRegisterVehicle});

  final VoidCallback onRegisterVehicle;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 130,
            child: Image.asset(
              SnapAssets.carHero,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              cacheWidth: 800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '먼저 차량을 등록해 주세요',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '등록한 차량으로 주차와 출차를 요청할 수 있습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          SnapActionButton(
            buttonKey: const Key('register-first-vehicle'),
            onPressed: onRegisterVehicle,
            label: '차량 등록하기',
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: highlighted ? SnapColors.electricBlue : null,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.7),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 48, color: SnapColors.electricBlue),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _HeroStage extends StatelessWidget {
  const _HeroStage({
    required this.height,
    required this.glowColor,
    required this.child,
  });

  final double height;
  final Color glowColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Positioned(
            left: 30,
            right: 30,
            bottom: 12,
            height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: glowColor.withOpacity(
                      Theme.of(context).brightness == Brightness.dark
                          ? 0.22
                          : 0.1,
                    ),
                    blurRadius: 55,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _LargeBrandMark extends StatelessWidget {
  const _LargeBrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          'S.N.A.P',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: 8,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'AUTOMATED PARKING',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.2,
              ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 2,
          decoration: BoxDecoration(
            color: SnapColors.electricBlue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
}

class _MiniBrandMark extends StatelessWidget {
  const _MiniBrandMark({this.statusColor});

  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 48,
      child: Stack(
        alignment: Alignment.centerRight,
        children: <Widget>[
          Positioned(
            left: 0,
            width: 42,
            height: 42,
            child: Image.asset(
              SnapAssets.robotHero,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              cacheWidth: 128,
            ),
          ),
          Positioned(
            right: 0,
            child: Text(
              'S.N.A.P',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          if (statusColor != null)
            Positioned(
              top: 1,
              right: 0,
              child: _PulsingDot(color: statusColor!, size: 7),
            ),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected, this.statusColor});

  final bool connected;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Center(
            child: Icon(
              Icons.directions_car_outlined,
              color: SnapColors.electricBlue,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _PulsingDot(
              color: statusColor ??
                  (connected ? SnapColors.electricBlue : SnapColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withOpacity(0.45), blurRadius: 8),
        ],
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({required this.endpoint, required this.connected});

  final Uri endpoint;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.language_rounded,
            size: 20,
            color: connected
                ? SnapColors.electricBlue
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              endpoint.toString(),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Gateway 주소 복사',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: endpoint.toString()));
            },
            icon: const Icon(Icons.content_copy_rounded, size: 17),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

int _jobStage(JobState state, String rawRobotState) {
  final robotState = rawRobotState.trim().toUpperCase();
  return switch (state) {
    JobState.requested || JobState.vehicleDetected => 0,
    JobState.running => switch (robotState) {
        'CARRYING_TO_SLOT' || 'MOVING_TO_SLOT' => 1,
        'ACQUIRING_VEHICLE' ||
        'LIFTING' ||
        'CARRYING_TO_EXIT' ||
        'APPROACHING' ||
        'GRIPPING' ||
        'REVERSING' =>
          2,
        _ => 1,
      },
    JobState.movingToVehicle => 1,
    JobState.movingToSlot => 1,
    JobState.lifting || JobState.retrieving => 2,
    JobState.parked || JobState.returning => 3,
    _ => 0,
  };
}

String _jobHeadline(JobState state, bool isRetrieval) {
  return switch (state) {
    JobState.requested ||
    JobState.vehicleDetected =>
      isRetrieval ? '출차 요청을 확인하고 있어요' : '주차 요청을 확인하고 있어요',
    JobState.movingToVehicle => '로봇이 차량으로 이동 중',
    JobState.lifting => '차량을 안전하게 싣는 중',
    JobState.movingToSlot ||
    JobState.running =>
      isRetrieval ? '차량을 입구로 이동 중' : '차량 이동 중',
    JobState.retrieving => '차량을 입구로 이동 중',
    JobState.returning => '로봇이 대기 위치로 복귀 중',
    _ => '작업 상태 확인 중',
  };
}

bool _isRetrievalProgress(
  ParkingSnapshot snapshot,
  CustomerVehicle? vehicle,
) {
  if (vehicle != null) {
    final isRetrievalState = switch (vehicle.state) {
      VehicleState.retrievalRequested ||
      VehicleState.retrieving ||
      VehicleState.retrieved =>
        true,
      _ => false,
    };
    if (isRetrievalState) {
      return true;
    }
  }

  final robotState = snapshot.robot.state.trim().toUpperCase();
  return robotState == 'MOVING_TO_PARKED_VEHICLE' ||
      robotState == 'CARRYING_TO_EXIT' ||
      snapshot.job.state == JobState.retrieving ||
      snapshot.job.message.contains('출차');
}

bool _isHealthyRobotState(String rawState) {
  final state = rawState.trim().toUpperCase();
  return state.isNotEmpty &&
      !const <String>{
        'UNKNOWN',
        'OFFLINE',
        'FAULT',
        'ERROR',
        'EMERGENCY_STOP',
        '상태 미확인',
      }.contains(state);
}

bool _isActiveJobState(JobState state) {
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

bool _sameSlot(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber == rightNumber;
  }
  return left == right;
}

bool _isValidVehicleNumber(String value) {
  final normalized = value.trim();
  return normalized.isNotEmpty && normalized.length <= 32;
}

Color _successColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? SnapColors.success
      : SnapColors.successDeep;
}

String vehicleStateLabel(VehicleState state) {
  return switch (state) {
    VehicleState.readyToPark => '주차 준비',
    VehicleState.parkingRequested => '주차 요청 접수',
    VehicleState.parkingInProgress => '주차 진행 중',
    VehicleState.parked => '주차 완료',
    VehicleState.retrievalRequested => '출차 요청 접수',
    VehicleState.retrieving => '출차 진행 중',
    VehicleState.retrieved => '출차 완료',
    VehicleState.error => '확인 필요',
    VehicleState.unknown => '상태 확인 중',
  };
}

String connectionLabel(GatewayConnectionState state) {
  return switch (state) {
    GatewayConnectionState.connected => '주차장 연결됨',
    GatewayConnectionState.connecting => '주차장 연결 중',
    GatewayConnectionState.reconnecting => '주차장 재연결 중',
    GatewayConnectionState.disconnected => '주차장 연결 끊김',
  };
}

String robotLabel(String rawState) {
  return switch (rawState.trim().toUpperCase()) {
    'READY' || 'IDLE' || 'DONE' || 'IDLE_AT_STANDBY' => '준비됨',
    'OFFLINE' => '연결 확인 필요',
    'FAULT' => '안전 확인 필요',
    _ => rawState,
  };
}

String durationLabel(int? minutes) {
  if (minutes == null) {
    return '-';
  }
  return switch (minutes) {
    60 => '60분',
    120 => '120분',
    180 => '180분',
    240 => '240분+',
    _ => '$minutes분',
  };
}

String slotLabel(String value) => value == '-' ? value : value.padLeft(2, '0');

String formatClock(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
