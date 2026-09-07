import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../contracts/parking_models.dart';
import 'pi_gateway_client.dart';

enum GatewayConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting
}

abstract interface class ParkingSessionController implements Listenable {
  GatewayConnectionState get connectionState;
  ParkingSnapshot? get snapshot;
  List<CustomerVehicle> get vehicles;
  String? get lastError;
  String? get lastEventType;
  bool get isSubmitting;

  Future<void> start();
  Future<void> reconnectNow();
  Future<void> refresh();
  Future<void> resume();
  Future<GatewayCommandResult> requestParking({
    required String vehicleId,
    required int expectedMinutes,
  });
  Future<GatewayCommandResult> requestRetrieval({required String vehicleId});
  Future<CustomerVehicle> registerVehicle({required String vehicleNumber});
  void dispose();
}

class PiGatewaySession extends ChangeNotifier
    implements ParkingSessionController {
  PiGatewaySession({
    required this.client,
    this.lotId = 'demo-01',
    this.customerId = 'demo-customer',
    this.pingInterval = const Duration(seconds: 15),
    List<Duration>? reconnectDelays,
  }) : reconnectDelays = reconnectDelays == null || reconnectDelays.isEmpty
            ? const <Duration>[
                Duration(seconds: 1),
                Duration(seconds: 2),
                Duration(seconds: 4),
                Duration(seconds: 8),
                Duration(seconds: 15),
              ]
            : List<Duration>.unmodifiable(reconnectDelays);

  final PiGatewayClient client;
  final String lotId;
  final String customerId;
  final Duration pingInterval;
  final List<Duration> reconnectDelays;

  GatewayConnectionState _connectionState = GatewayConnectionState.disconnected;
  ParkingSnapshot? _snapshot;
  List<CustomerVehicle> _vehicles = const <CustomerVehicle>[];
  String? _lastError;
  String? _lastEventType;
  bool _isSubmitting = false;
  bool _disposed = false;
  bool _started = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  int _vehicleRequestSequence = 0;
  int _acceptedVehicleRequest = 0;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _retryTimer;

  @override
  GatewayConnectionState get connectionState => _connectionState;
  @override
  ParkingSnapshot? get snapshot => _snapshot;
  @override
  List<CustomerVehicle> get vehicles => _vehicles;
  @override
  String? get lastError => _lastError;
  @override
  String? get lastEventType => _lastEventType;
  @override
  bool get isSubmitting => _isSubmitting;

  @override
  Future<void> start() async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    final generation = ++_generation;
    await _connect(generation);
  }

  @override
  Future<void> reconnectNow() async {
    if (_disposed) {
      return;
    }
    _started = true;
    _retryTimer?.cancel();
    final generation = ++_generation;
    await _closeActiveSocket();
    _reconnectAttempt = 0;
    await _connect(generation);
  }

  @override
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    final generation = _generation;
    try {
      final latest = await _fetchGatewayState();
      if (_disposed || generation != _generation) {
        return;
      }
      _acceptSnapshot(latest.snapshot);
      _acceptVehicles(latest.vehicles, latest.vehicleRequest);
      _lastError = null;
      _notify();
    } catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _lastError = error.toString();
      _notify();
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    if (_connectionState == GatewayConnectionState.connected) {
      try {
        await refresh();
        return;
      } catch (_) {
        // Refresh failures are handed to the same bounded reconnect loop as WS failures.
      }
    }
    await reconnectNow();
  }

  @override
  Future<GatewayCommandResult> requestParking({
    required String vehicleId,
    required int expectedMinutes,
  }) {
    return _runExclusive(() async {
      final result = await client.requestParking(
        customerId: customerId,
        vehicleId: vehicleId,
        expectedMinutes: expectedMinutes,
        lotId: lotId,
        fallback: _snapshot,
      );
      _applyCommandSnapshot(result);
      await _refreshVehiclesBestEffort();
      return result;
    });
  }

  @override
  Future<GatewayCommandResult> requestRetrieval({required String vehicleId}) {
    return _runExclusive(() async {
      final result = await client.requestRetrieval(
        customerId: customerId,
        vehicleId: vehicleId,
        lotId: lotId,
        fallback: _snapshot,
      );
      _applyCommandSnapshot(result);
      await _refreshVehiclesBestEffort();
      return result;
    });
  }

  @override
  Future<CustomerVehicle> registerVehicle({required String vehicleNumber}) {
    return _runExclusive(() async {
      final vehicle = await client.registerVehicle(
        customerId: customerId,
        vehicleNumber: vehicleNumber,
      );
      _upsertVehicle(vehicle);
      await _refreshVehiclesBestEffort();
      return vehicle;
    });
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _started = false;
    ++_generation;
    _retryTimer?.cancel();
    await _closeActiveSocket();
    _connectionState = GatewayConnectionState.disconnected;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _started = false;
    ++_generation;
    _retryTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    client.close();
    super.dispose();
  }

  Future<void> _connect(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _retryTimer = null;
    _connectionState = _reconnectAttempt == 0
        ? GatewayConnectionState.connecting
        : GatewayConnectionState.reconnecting;
    _notify();

    try {
      // Every initial connection and reconnect resynchronizes both public lot
      // state and this customer's private vehicle list from REST first.
      final latest = await _fetchGatewayState();
      if (!_isCurrent(generation)) {
        return;
      }
      _acceptSnapshot(latest.snapshot);
      _acceptVehicles(latest.vehicles, latest.vehicleRequest);
      _lastError = null;
      _notify();

      final socket = await WebSocket.connect(client.eventsUri.toString())
          .timeout(client.requestTimeout);
      if (!_isCurrent(generation)) {
        await socket.close();
        return;
      }

      await _closeActiveSocket();
      _socket = socket;
      socket.pingInterval = pingInterval;
      _reconnectAttempt = 0;
      _connectionState = GatewayConnectionState.connected;
      _lastError = null;
      _socketSubscription = socket.listen(
        (message) => _handleSocketMessage(message, generation, socket),
        onError: (Object error) => _handleSocketEnd(error, generation, socket),
        onDone: () => _handleSocketEnd(null, generation, socket),
        cancelOnError: true,
      );
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _lastError = error.toString();
      _scheduleReconnect(generation);
    }
  }

  void _handleSocketMessage(Object? message, int generation, WebSocket socket) {
    if (!_isCurrent(generation) || !identical(_socket, socket)) {
      return;
    }
    try {
      final text = switch (message) {
        final String value => value,
        final List<int> value => utf8.decode(value),
        _ => throw const FormatException('지원하지 않는 WebSocket 메시지입니다.'),
      };
      final event = GatewayEvent.fromPayload(
        jsonDecode(text),
        fallback: _snapshot,
        strict: true,
        expectedLotId: lotId,
      );
      _acceptSnapshot(event.snapshot);
      _lastEventType = event.type;
      _lastError = null;
      _notify();
      unawaited(_refreshVehiclesAfterEvent(generation));
    } catch (error) {
      _lastError = '실시간 이벤트 해석 실패: $error';
      _notify();
    }
  }

  void _handleSocketEnd(Object? error, int generation, WebSocket socket) {
    if (!_isCurrent(generation) || !identical(_socket, socket)) {
      return;
    }
    _socket = null;
    _socketSubscription = null;
    if (error != null) {
      _lastError = '실시간 연결 종료: $error';
    }
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    if (!_isCurrent(generation) || _retryTimer?.isActive == true) {
      return;
    }
    _connectionState = GatewayConnectionState.reconnecting;
    final delay = reconnectDelays[
        _reconnectAttempt.clamp(0, reconnectDelays.length - 1).toInt()];
    _reconnectAttempt += 1;
    _retryTimer = Timer(delay, () => unawaited(_connect(generation)));
    _notify();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_isSubmitting) {
      throw const DuplicateSubmissionException();
    }
    _isSubmitting = true;
    _lastError = null;
    _notify();
    try {
      return await operation();
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  void _applyCommandSnapshot(GatewayCommandResult result) {
    if (result.snapshot != null) {
      _acceptSnapshot(result.snapshot!);
    }
    _lastError = null;
    _notify();
  }

  Future<
      ({
        ParkingSnapshot snapshot,
        List<CustomerVehicle> vehicles,
        int vehicleRequest,
      })> _fetchGatewayState() async {
    final vehicleRequest = ++_vehicleRequestSequence;
    final values = await Future.wait<Object>(<Future<Object>>[
      client.fetchSnapshot(lotId: lotId),
      client.fetchVehicles(customerId: customerId),
    ]);
    return (
      snapshot: values[0] as ParkingSnapshot,
      vehicles: values[1] as List<CustomerVehicle>,
      vehicleRequest: vehicleRequest,
    );
  }

  Future<void> _refreshVehiclesAfterEvent(int generation) async {
    final vehicleRequest = ++_vehicleRequestSequence;
    try {
      final latest = await client.fetchVehicles(customerId: customerId);
      if (!_isCurrent(generation)) {
        return;
      }
      _acceptVehicles(latest, vehicleRequest);
      _lastError = null;
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _lastError = '차량 목록 갱신 실패: $error';
      _notify();
    }
  }

  Future<void> _refreshVehiclesBestEffort() async {
    final vehicleRequest = ++_vehicleRequestSequence;
    try {
      final latest = await client.fetchVehicles(customerId: customerId);
      if (_disposed) {
        return;
      }
      _acceptVehicles(latest, vehicleRequest);
      _lastError = null;
      _notify();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _lastError = '차량 목록 갱신 실패: $error';
      _notify();
    }
  }

  void _acceptVehicles(List<CustomerVehicle> incoming, int request) {
    if (request < _acceptedVehicleRequest) {
      return;
    }
    _acceptedVehicleRequest = request;
    _vehicles = List<CustomerVehicle>.unmodifiable(incoming);
  }

  void _upsertVehicle(CustomerVehicle vehicle) {
    final index = _vehicles.indexWhere((existing) => existing.id == vehicle.id);
    if (index < 0) {
      _vehicles = List<CustomerVehicle>.unmodifiable(
        <CustomerVehicle>[..._vehicles, vehicle],
      );
    } else {
      final updated = List<CustomerVehicle>.of(_vehicles);
      updated[index] = vehicle;
      _vehicles = List<CustomerVehicle>.unmodifiable(updated);
    }
    _notify();
  }

  bool _acceptSnapshot(ParkingSnapshot incoming) {
    if (incoming.lotId != lotId) {
      throw GatewayException(
        'Snapshot lotId가 다릅니다: expected=$lotId actual=${incoming.lotId}',
      );
    }
    final current = _snapshot;
    if (current != null && incoming.updatedAt.isBefore(current.updatedAt)) {
      return false;
    }
    _snapshot = incoming;
    return true;
  }

  Future<void> _closeActiveSocket() async {
    final subscription = _socketSubscription;
    final socket = _socket;
    _socketSubscription = null;
    _socket = null;
    await subscription?.cancel();
    await socket?.close();
  }

  bool _isCurrent(int generation) =>
      !_disposed && _started && generation == _generation;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
