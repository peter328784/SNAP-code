import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/core/networking/pi_gateway_session.dart';
import 'package:snap_mobile/features/parking_lot/parking_application.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  testWidgets('a dismissed parked vehicle can reopen its retrieval screen',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _ParkedVehicleSession();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: SnapTheme.light(),
        home: ParkingApplication(
          gatewayBaseUri: Uri.parse('http://172.30.1.80:8101'),
          lotId: 'demo-01',
          customerId: 'demo-customer',
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('출차 요청'), findsOneWidget);
    await tester.ensureVisible(find.text('홈으로'));
    await tester.tap(find.text('홈으로'));
    await tester.pumpAndSettle();

    expect(find.byType(ParkingSelectionPage), findsOneWidget);
    expect(find.text('출차 요청'), findsNothing);

    await tester.tap(find.text('차량'));
    await tester.pumpAndSettle();
    final parkedVehicle = find.byKey(const Key('vehicle-VEH-1'));
    await tester.scrollUntilVisible(
      parkedVehicle,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(parkedVehicle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.text('출차 요청'), findsOneWidget);
  });

  testWidgets('a command warning uses the accessible warning color pair',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _ParkedVehicleSession();
    addTearDown(session.dispose);
    final theme = SnapTheme.light();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: ParkingApplication(
          gatewayBaseUri: Uri.parse('http://172.30.1.80:8101'),
          lotId: 'demo-01',
          customerId: 'demo-customer',
          session: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final retrieval = find.byKey(const Key('retrieval-action'));
    await tester.ensureVisible(retrieval);
    await tester.tap(retrieval);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final warning = tester.widget<Text>(find.text('Bad state: offline'));
    expect(snackBar.backgroundColor, theme.colorScheme.error);
    expect(warning.style?.color, theme.colorScheme.onError);
  });
}

class _ParkedVehicleSession extends ChangeNotifier
    implements ParkingSessionController {
  @override
  GatewayConnectionState get connectionState =>
      GatewayConnectionState.connected;

  @override
  bool get isSubmitting => false;

  @override
  String? get lastError => null;

  @override
  String? get lastEventType => 'SNAPSHOT';

  @override
  ParkingSnapshot get snapshot => ParkingSnapshot(
        lotId: 'demo-01',
        updatedAt: DateTime.utc(2026, 9, 6, 1),
        slots: const <ParkingSlot>[
          ParkingSlot(id: '1', state: SlotState.occupied),
          ParkingSlot(id: '2', state: SlotState.available),
          ParkingSlot(id: '3', state: SlotState.available),
          ParkingSlot(id: '4', state: SlotState.available),
          ParkingSlot(id: '5', state: SlotState.available),
          ParkingSlot(id: '6', state: SlotState.available),
        ],
        robot: const RobotSnapshot(
          state: 'READY',
          batteryPct: 86,
          positionPct: 18,
        ),
        job: const JobSnapshot(
          state: JobState.idle,
          message: 'ready',
        ),
      );

  @override
  List<CustomerVehicle> get vehicles => <CustomerVehicle>[
        CustomerVehicle(
          id: 'VEH-1',
          vehicleNumber: '12가3456',
          state: VehicleState.parked,
          slotId: '1',
          expectedMinutes: 120,
          updatedAt: DateTime(2026, 9, 6, 10),
        ),
      ];

  @override
  Future<void> reconnectNow() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<CustomerVehicle> registerVehicle({required String vehicleNumber}) {
    throw UnimplementedError();
  }

  @override
  Future<GatewayCommandResult> requestParking({
    required String vehicleId,
    required int expectedMinutes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<GatewayCommandResult> requestRetrieval({required String vehicleId}) {
    return Future<GatewayCommandResult>.error(StateError('offline'));
  }

  @override
  Future<void> resume() async {}

  @override
  Future<void> start() async {}
}
