import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/contracts/parking_models.dart';
import '../../core/networking/pi_gateway_client.dart';
import '../../core/networking/pi_gateway_session.dart';
import 'parking_views.dart';

class ParkingApplication extends StatefulWidget {
  const ParkingApplication({
    required this.gatewayBaseUri,
    required this.lotId,
    required this.customerId,
    this.session,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    super.key,
  });

  final Uri gatewayBaseUri;
  final String lotId;
  final String customerId;
  final ParkingSessionController? session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<ParkingApplication> createState() => _ParkingApplicationState();
}

class _ParkingApplicationState extends State<ParkingApplication>
    with WidgetsBindingObserver {
  late final ParkingSessionController _session;
  late final bool _ownsSession;
  final Map<String, int> _expectedMinutes = <String, int>{};
  final TextEditingController _registrationController = TextEditingController();

  ParkingTab _selectedTab = ParkingTab.home;
  String? _selectedVehicleId;
  String? _dismissedCompletionVehicleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsSession = widget.session == null;
    _session = widget.session ??
        PiGatewaySession(
          client: PiGatewayClient(baseUri: widget.gatewayBaseUri),
          lotId: widget.lotId,
          customerId: widget.customerId,
        );
    _session.addListener(_onSessionChanged);
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
    if (_ownsSession) {
      _session.dispose();
    }
    _registrationController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) {
      return;
    }
    final vehicles = _session.vehicles;
    if (_dismissedCompletionVehicleId != null &&
        !vehicles.any(
          (vehicle) =>
              vehicle.id == _dismissedCompletionVehicleId &&
              vehicle.state == VehicleState.parked,
        )) {
      _dismissedCompletionVehicleId = null;
    }
    if (vehicles.isNotEmpty &&
        !vehicles.any((vehicle) => vehicle.id == _selectedVehicleId)) {
      _selectedVehicleId = _preferredVehicle(vehicles, _session.snapshot)?.id ??
          vehicles.first.id;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _session.snapshot;
    final selectedVehicle = _preferredVehicle(
      _session.vehicles,
      snapshot,
      selectedId: _selectedVehicleId,
    );
    final hasActiveOperation = snapshot != null &&
        (_isActiveJob(snapshot.job.state) ||
            _activeVehicle(_session.vehicles, snapshot) != null);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            if (_session.isSubmitting ||
                _session.connectionState == GatewayConnectionState.connecting)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey<ParkingTab>(_selectedTab),
                  child: _buildSelectedPage(snapshot, selectedVehicle),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _selectedTab == ParkingTab.home && hasActiveOperation
          ? null
          : NavigationBar(
              selectedIndex: _selectedTab.index,
              onDestinationSelected: (index) {
                setState(() => _selectedTab = ParkingTab.values[index]);
              },
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '홈',
                ),
                NavigationDestination(
                  icon: Icon(Icons.directions_car_outlined),
                  selectedIcon: Icon(Icons.directions_car_filled_rounded),
                  label: '차량',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history_rounded),
                  label: '기록',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: '설정',
                ),
              ],
            ),
    );
  }

  Widget _buildSelectedPage(
    ParkingSnapshot? snapshot,
    CustomerVehicle? selectedVehicle,
  ) {
    return switch (_selectedTab) {
      ParkingTab.home => _buildHome(snapshot, selectedVehicle),
      ParkingTab.vehicles => VehicleManagementPage(
          connectionState: _session.connectionState,
          vehicles: _session.vehicles,
          selectedVehicleId: selectedVehicle?.id,
          registrationController: _registrationController,
          isSubmitting: _session.isSubmitting,
          onRefresh: _refresh,
          onVehicleSelected: _selectVehicle,
          onRegister: () => unawaited(_registerVehicle()),
        ),
      ParkingTab.activity => ActivityPage(
          connectionState: _session.connectionState,
          vehicles: _session.vehicles,
          snapshot: snapshot,
          onRefresh: _refresh,
        ),
      ParkingTab.settings => SettingsPage(
          connectionState: _session.connectionState,
          endpoint: widget.gatewayBaseUri,
          snapshot: snapshot,
          lastError: _session.lastError,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
          onReconnect: () => unawaited(_reconnect()),
          onRefresh: _refresh,
        ),
    };
  }

  Widget _buildHome(
    ParkingSnapshot? snapshot,
    CustomerVehicle? selectedVehicle,
  ) {
    if (snapshot == null) {
      return LoadingPage(
        connectionState: _session.connectionState,
        endpoint: widget.gatewayBaseUri,
        error: _session.lastError,
        onReconnect: () => unawaited(_reconnect()),
        onRefresh: _refresh,
      );
    }

    final activeVehicle = _activeVehicle(_session.vehicles, snapshot);
    if (_isActiveJob(snapshot.job.state) || activeVehicle != null) {
      return ParkingProgressPage(
        connectionState: _session.connectionState,
        snapshot: snapshot,
        // A lot-wide job can belong to another customer. Do not attribute that
        // job to the locally selected vehicle when its ID is not in this
        // customer's vehicle list.
        vehicle: activeVehicle,
        onRefresh: _refresh,
      );
    }

    final parkedVehicle = selectedVehicle?.state == VehicleState.parked &&
            selectedVehicle?.id != _dismissedCompletionVehicleId
        ? selectedVehicle
        : null;
    if (parkedVehicle != null) {
      return ParkingCompletePage(
        connectionState: _session.connectionState,
        snapshot: snapshot,
        vehicle: parkedVehicle,
        isSubmitting: _session.isSubmitting,
        onRefresh: _refresh,
        onRetrieval: () => unawaited(_requestRetrieval(parkedVehicle)),
        onHome: () {
          setState(() {
            _dismissedCompletionVehicleId = parkedVehicle.id;
            _selectedTab = ParkingTab.home;
          });
        },
      );
    }

    final isFull = snapshot.slots.isNotEmpty &&
        snapshot.slots.every((slot) => slot.state != SlotState.available);
    final expectedMinutes = selectedVehicle == null
        ? 120
        : _expectedMinutes[selectedVehicle.id] ??
            selectedVehicle.expectedMinutes ??
            120;

    return ParkingSelectionPage(
      connectionState: _session.connectionState,
      snapshot: snapshot,
      vehicles: _session.vehicles,
      selectedVehicle: selectedVehicle,
      expectedMinutes: expectedMinutes,
      isSubmitting: _session.isSubmitting,
      isFull: isFull,
      onRefresh: _refresh,
      onVehicleSelected: _selectVehicle,
      onExpectedMinutesChanged: (minutes) {
        if (selectedVehicle == null) {
          return;
        }
        setState(() => _expectedMinutes[selectedVehicle.id] = minutes);
      },
      onParking: () {
        if (selectedVehicle != null) {
          unawaited(_requestParking(selectedVehicle));
        }
      },
      onRegisterVehicle: () {
        setState(() => _selectedTab = ParkingTab.vehicles);
      },
    );
  }

  void _selectVehicle(String vehicleId) {
    setState(() {
      _selectedVehicleId = vehicleId;
      // Selecting a vehicle is an explicit request to reopen its current
      // state, including a completion screen dismissed with "홈으로".
      _dismissedCompletionVehicleId = null;
      _expectedMinutes.putIfAbsent(vehicleId, () => 120);
    });
  }

  Future<void> _refresh() async {
    try {
      await _session.refresh();
    } catch (error) {
      _showMessage(error.toString(), isWarning: true);
    }
  }

  Future<void> _reconnect() async {
    try {
      await _session.reconnectNow();
    } catch (error) {
      _showMessage(error.toString(), isWarning: true);
    }
  }

  Future<void> _requestParking(CustomerVehicle vehicle) async {
    try {
      await _session.requestParking(
        vehicleId: vehicle.id,
        expectedMinutes:
            _expectedMinutes[vehicle.id] ?? vehicle.expectedMinutes ?? 120,
      );
      _showMessage('${vehicle.vehicleNumber} 주차 요청을 접수했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isWarning: true);
    }
  }

  Future<void> _requestRetrieval(CustomerVehicle vehicle) async {
    try {
      await _session.requestRetrieval(vehicleId: vehicle.id);
      _showMessage('${vehicle.vehicleNumber} 출차 요청을 접수했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isWarning: true);
    }
  }

  Future<void> _registerVehicle() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final vehicleNumber = _registrationController.text.trim().toUpperCase();
    if (vehicleNumber.isEmpty || vehicleNumber.length > 32) {
      _showMessage('차량번호를 1~32자로 입력해 주세요.', isWarning: true);
      return;
    }

    try {
      final vehicle =
          await _session.registerVehicle(vehicleNumber: vehicleNumber);
      if (!mounted) {
        return;
      }
      _registrationController.clear();
      _expectedMinutes.putIfAbsent(vehicle.id, () => 120);
      setState(() => _selectedVehicleId = vehicle.id);
      _showMessage('$vehicleNumber 차량을 등록했습니다.');
    } catch (error) {
      _showMessage(error.toString(), isWarning: true);
    }
  }

  bool _isActiveJob(JobState state) {
    return _jobStateIsActive(state);
  }

  void _showMessage(String message, {bool isWarning = false}) {
    if (!mounted) {
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isWarning ? TextStyle(color: scheme.onError) : null,
          ),
          backgroundColor: isWarning ? scheme.error : null,
        ),
      );
  }
}

CustomerVehicle? _preferredVehicle(
  List<CustomerVehicle> vehicles,
  ParkingSnapshot? snapshot, {
  String? selectedId,
}) {
  if (vehicles.isEmpty) {
    return null;
  }
  final jobVehicle = snapshot != null && _jobStateIsActive(snapshot.job.state)
      ? snapshot.job.vehicleId
      : null;
  if (jobVehicle != null) {
    final match =
        _firstWhereOrNull(vehicles, (vehicle) => vehicle.id == jobVehicle);
    if (match != null) {
      return match;
    }
  }
  if (selectedId != null) {
    final match =
        _firstWhereOrNull(vehicles, (vehicle) => vehicle.id == selectedId);
    if (match != null) {
      return match;
    }
  }
  return vehicles.first;
}

CustomerVehicle? _activeVehicle(
  List<CustomerVehicle> vehicles,
  ParkingSnapshot snapshot,
) {
  final jobVehicle =
      _jobStateIsActive(snapshot.job.state) ? snapshot.job.vehicleId : null;
  if (jobVehicle != null) {
    final match =
        _firstWhereOrNull(vehicles, (vehicle) => vehicle.id == jobVehicle);
    if (match != null) {
      return match;
    }
  }
  return _firstWhereOrNull(vehicles, (vehicle) {
    return switch (vehicle.state) {
      VehicleState.parkingRequested ||
      VehicleState.parkingInProgress ||
      VehicleState.retrievalRequested ||
      VehicleState.retrieving =>
        true,
      _ => false,
    };
  });
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}

bool _jobStateIsActive(JobState state) {
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
