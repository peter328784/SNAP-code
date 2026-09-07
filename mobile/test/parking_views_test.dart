import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/core/networking/pi_gateway_session.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  testWidgets('loading page shows the brand, status, endpoint, and CTA',
      (tester) async {
    final endpoint = Uri.parse('http://192.168.0.20:8101');
    var reconnectRequests = 0;

    await _pumpPage(
      tester,
      LoadingPage(
        connectionState: GatewayConnectionState.reconnecting,
        endpoint: endpoint,
        error: null,
        onReconnect: () => reconnectRequests += 1,
        onRefresh: _noRefresh,
      ),
    );

    expect(find.text('S.N.A.P'), findsOneWidget);
    expect(find.text('AUTOMATED PARKING'), findsOneWidget);
    expect(find.text('주차장 재연결 중'), findsOneWidget);
    expect(find.text('게이트웨이'), findsOneWidget);
    expect(find.text('센서'), findsOneWidget);
    expect(find.text('로봇'), findsOneWidget);
    expect(_findEndpoint(endpoint), findsOneWidget);
    expect(_findAsset(SnapAssets.robotHero), findsOneWidget);
    expect(find.text('연결 설정'), findsOneWidget);

    final connectionAction = find.byKey(const Key('connection-action'));
    await tester.ensureVisible(connectionAction);
    await tester.tap(connectionAction);

    expect(reconnectRequests, 1);
  });

  testWidgets('vehicle management shows its brand, hero, and registration CTA',
      (tester) async {
    final registrationController = TextEditingController(text: 'SNAP-01');
    addTearDown(registrationController.dispose);
    var registrationRequests = 0;

    await _pumpPage(
      tester,
      VehicleManagementPage(
        connectionState: GatewayConnectionState.connected,
        vehicles: const <CustomerVehicle>[
          CustomerVehicle(
            id: 'VEH-1',
            vehicleNumber: '12가3456',
            state: VehicleState.readyToPark,
          ),
        ],
        selectedVehicleId: 'VEH-1',
        registrationController: registrationController,
        isSubmitting: false,
        onRefresh: _noRefresh,
        onVehicleSelected: (_) {},
        onRegister: () => registrationRequests += 1,
      ),
    );

    expect(find.byType(SnapPageHeader), findsOneWidget);
    expect(find.text('내 차량'), findsOneWidget);
    expect(find.text('주차와 출차에 사용할 차량을 관리합니다.'), findsOneWidget);
    expect(find.text('S.N.A.P'), findsOneWidget);
    expect(_findAsset(SnapAssets.robotHero), findsOneWidget);
    expect(_findAsset(SnapAssets.carHero), findsOneWidget);
    expect(find.text('새 차량 등록'), findsOneWidget);
    expect(find.byKey(const Key('registration-field')), findsOneWidget);
    expect(find.text('등록 가능한 차량번호입니다.'), findsOneWidget);
    expect(find.byKey(const Key('vehicle-VEH-1')), findsOneWidget);
    expect(find.text('차량 등록'), findsOneWidget);

    final registrationAction = find.byKey(const Key('registration-action'));
    await tester.ensureVisible(registrationAction);
    await tester.tap(registrationAction);

    expect(registrationRequests, 1);
  });

  testWidgets('parking selection forwards duration and parking actions',
      (tester) async {
    const vehicle = CustomerVehicle(
      id: 'VEH-1',
      vehicleNumber: '12가3456',
      state: VehicleState.readyToPark,
    );
    var selectedMinutes = 0;
    var parkingRequests = 0;

    await _pumpPage(
      tester,
      ParkingSelectionPage(
        connectionState: GatewayConnectionState.connected,
        snapshot: _snapshot(),
        vehicles: const <CustomerVehicle>[vehicle],
        selectedVehicle: vehicle,
        expectedMinutes: 120,
        isSubmitting: false,
        isFull: false,
        onRefresh: _noRefresh,
        onVehicleSelected: (_) {},
        onExpectedMinutesChanged: (minutes) => selectedMinutes = minutes,
        onParking: () => parkingRequests += 1,
        onRegisterVehicle: () {},
      ),
    );

    final parkingButton = tester.widget<FilledButton>(
      find.byKey(const Key('parking-action')),
    );
    expect(parkingButton.onPressed, isNotNull);
    expect(
      Theme.of(tester.element(find.byType(ParkingSelectionPage))).brightness,
      Brightness.light,
    );
    expect(find.byType(SnapPageHeader), findsOneWidget);
    expect(find.text('주차하기'), findsOneWidget);
    expect(find.text('S.N.A.P  ·  demo-01'), findsOneWidget);
    expect(find.text('주차면 현황'), findsOneWidget);
    expect(find.byType(ParkingLotDiagram), findsOneWidget);
    expect(find.byKey(const Key('slot-1')), findsOneWidget);
    expect(_findAsset(SnapAssets.robotTop), findsOneWidget);
    expect(_findAsset(SnapAssets.carTop), findsOneWidget);
    expect(find.text('예상 주차 시간'), findsOneWidget);
    expect(find.byType(DurationSelector), findsOneWidget);
    expect(find.text('120분'), findsOneWidget);
    expect(find.text('주차 요청'), findsOneWidget);

    await tester.ensureVisible(find.text('180분'));
    await tester.tap(find.text('180분'));
    await tester.ensureVisible(find.byKey(const Key('parking-action')));
    await tester.tap(find.byKey(const Key('parking-action')));

    expect(selectedMinutes, 180);
    expect(parkingRequests, 1);
  });

  testWidgets('parking action is disabled while full or disconnected',
      (tester) async {
    const vehicle = CustomerVehicle(
      id: 'VEH-1',
      vehicleNumber: '12가3456',
      state: VehicleState.readyToPark,
    );

    Future<void> pump({
      required GatewayConnectionState connectionState,
      required bool isFull,
    }) {
      return _pumpPage(
        tester,
        ParkingSelectionPage(
          connectionState: connectionState,
          snapshot: _snapshot(),
          vehicles: const <CustomerVehicle>[vehicle],
          selectedVehicle: vehicle,
          expectedMinutes: 120,
          isSubmitting: false,
          isFull: isFull,
          onRefresh: _noRefresh,
          onVehicleSelected: (_) {},
          onExpectedMinutesChanged: (_) {},
          onParking: () {},
          onRegisterVehicle: () {},
        ),
      );
    }

    await pump(
      connectionState: GatewayConnectionState.connected,
      isFull: true,
    );
    expect(find.text('현재 만차입니다'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('parking-action')))
          .onPressed,
      isNull,
    );

    await pump(
      connectionState: GatewayConnectionState.disconnected,
      isFull: false,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('parking-action')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('parking progress shows the live storyboard progress contract',
      (tester) async {
    const vehicle = CustomerVehicle(
      id: 'VEH-1',
      vehicleNumber: '12가3456',
      state: VehicleState.parkingInProgress,
    );

    await _pumpPage(
      tester,
      ParkingProgressPage(
        connectionState: GatewayConnectionState.connected,
        snapshot: _progressSnapshot(),
        vehicle: vehicle,
        onRefresh: _noRefresh,
      ),
    );

    expect(find.byType(SnapPageHeader), findsOneWidget);
    expect(find.text('주차 진행 중'), findsOneWidget);
    expect(find.text(vehicle.vehicleNumber), findsOneWidget);
    expect(find.byType(ParkingLotDiagram), findsOneWidget);
    expect(find.byKey(const Key('slot-2')), findsOneWidget);
    expect(_findAsset(SnapAssets.robotTop), findsOneWidget);
    expect(_findAsset(SnapAssets.carTop), findsWidgets);
    expect(find.text('경로 위치 64%'), findsOneWidget);
    expect(find.text('배정 주차면 02'), findsOneWidget);
    expect(find.byType(JobStepper), findsOneWidget);
    expect(find.text('실시간 연결됨'), findsOneWidget);
  });

  testWidgets('parking completion shows updatedAt and requests retrieval',
      (tester) async {
    final vehicle = CustomerVehicle(
      id: 'VEH-2',
      vehicleNumber: '34나5678',
      state: VehicleState.parked,
      slotId: '2',
      expectedMinutes: 120,
      updatedAt: DateTime(2026, 8, 25, 14, 18),
    );
    var retrievalRequests = 0;

    await _pumpPage(
      tester,
      ParkingCompletePage(
        connectionState: GatewayConnectionState.connected,
        snapshot: _snapshot(),
        vehicle: vehicle,
        isSubmitting: false,
        onRefresh: _noRefresh,
        onRetrieval: () => retrievalRequests += 1,
      ),
      brightness: Brightness.dark,
    );

    expect(find.byType(SnapPageHeader), findsOneWidget);
    expect(find.text('주차 완료'), findsOneWidget);
    expect(find.text(vehicle.vehicleNumber), findsWidgets);
    expect(find.text('안전하게 주차했어요'), findsOneWidget);
    expect(_findAsset(SnapAssets.carTop), findsOneWidget);
    expect(find.text('입차 완료 14:18:00'), findsOneWidget);
    expect(find.text('02'), findsWidgets);
    expect(find.text('출차 요청'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(ParkingCompletePage))).brightness,
      Brightness.dark,
    );

    final retrievalAction = find.byKey(const Key('retrieval-action'));
    await tester.ensureVisible(retrievalAction);
    await tester.tap(retrievalAction);

    expect(retrievalRequests, 1);
  });

  for (final viewport in <({String name, Size size})>[
    (name: 'portrait', size: const Size(430, 932)),
    (name: 'landscape', size: const Size(932, 430)),
    (name: 'tablet portrait', size: const Size(834, 1194)),
    (name: 'tablet landscape', size: const Size(1194, 834)),
  ]) {
    testWidgets(
      'storyboard pages avoid overflow in ${viewport.name}',
      (tester) async {
        final registrationController = TextEditingController(
          text: '12가 3456',
        );
        addTearDown(registrationController.dispose);

        for (final page in _storyboardPages(registrationController)) {
          await _pumpPage(tester, page, physicalSize: viewport.size);
          await tester.pump();

          expect(
            tester.takeException(),
            isNull,
            reason: '${page.runtimeType} overflowed in ${viewport.name}',
          );
        }
      },
    );
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  Brightness brightness = Brightness.light,
  Size physicalSize = const Size(430, 932),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: SnapTheme.light(),
      darkTheme: SnapTheme.dark(),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: page),
    ),
  );
}

Future<void> _noRefresh() async {}

Finder _findAsset(String assetName) {
  return find.byWidgetPredicate(
    (widget) => widget is Image && _assetName(widget.image) == assetName,
    description: 'Image.asset($assetName)',
  );
}

String? _assetName(ImageProvider<Object> provider) {
  if (provider is AssetImage) {
    return provider.assetName;
  }
  if (provider is ResizeImage) {
    return _assetName(provider.imageProvider);
  }
  return null;
}

Finder _findEndpoint(Uri endpoint) {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText && widget.data == endpoint.toString(),
    description: 'endpoint ${endpoint.toString()}',
  );
}

List<Widget> _storyboardPages(
  TextEditingController registrationController,
) {
  const readyVehicle = CustomerVehicle(
    id: 'VEH-1',
    vehicleNumber: '12가3456',
    state: VehicleState.readyToPark,
  );
  final parkedVehicle = CustomerVehicle(
    id: 'VEH-2',
    vehicleNumber: '34나5678',
    state: VehicleState.parked,
    slotId: '2',
    expectedMinutes: 120,
    updatedAt: DateTime(2026, 8, 25, 14, 18),
  );

  return <Widget>[
    LoadingPage(
      connectionState: GatewayConnectionState.reconnecting,
      endpoint: Uri.parse('http://192.168.0.20:8101'),
      error: null,
      onReconnect: () {},
      onRefresh: _noRefresh,
    ),
    VehicleManagementPage(
      connectionState: GatewayConnectionState.connected,
      vehicles: const <CustomerVehicle>[readyVehicle],
      selectedVehicleId: readyVehicle.id,
      registrationController: registrationController,
      isSubmitting: false,
      onRefresh: _noRefresh,
      onVehicleSelected: (_) {},
      onRegister: () {},
    ),
    ParkingSelectionPage(
      connectionState: GatewayConnectionState.connected,
      snapshot: _snapshot(),
      vehicles: const <CustomerVehicle>[readyVehicle],
      selectedVehicle: readyVehicle,
      expectedMinutes: 120,
      isSubmitting: false,
      isFull: false,
      onRefresh: _noRefresh,
      onVehicleSelected: (_) {},
      onExpectedMinutesChanged: (_) {},
      onParking: () {},
      onRegisterVehicle: () {},
    ),
    ParkingProgressPage(
      connectionState: GatewayConnectionState.connected,
      snapshot: _progressSnapshot(),
      vehicle: const CustomerVehicle(
        id: 'VEH-1',
        vehicleNumber: '12가3456',
        state: VehicleState.parkingInProgress,
      ),
      onRefresh: _noRefresh,
    ),
    ParkingCompletePage(
      connectionState: GatewayConnectionState.connected,
      snapshot: _snapshot(),
      vehicle: parkedVehicle,
      isSubmitting: false,
      onRefresh: _noRefresh,
      onRetrieval: () {},
    ),
  ];
}

ParkingSnapshot _progressSnapshot() {
  return ParkingSnapshot(
    lotId: 'demo-01',
    updatedAt: DateTime.utc(2026, 8, 25, 12),
    slots: _snapshot().slots,
    robot: const RobotSnapshot(
      state: 'MOVING_TO_SLOT',
      batteryPct: 86,
      positionPct: 64,
    ),
    job: const JobSnapshot(
      state: JobState.movingToSlot,
      message: '차량 이동 중',
      vehicleId: 'VEH-1',
      targetSlot: '2',
    ),
  );
}

ParkingSnapshot _snapshot() {
  return ParkingSnapshot(
    lotId: 'demo-01',
    updatedAt: DateTime.utc(2026, 8, 25, 12),
    slots: const <ParkingSlot>[
      ParkingSlot(id: '1', state: SlotState.available),
      ParkingSlot(id: '2', state: SlotState.available),
      ParkingSlot(id: '3', state: SlotState.available),
      ParkingSlot(id: '4', state: SlotState.available),
      ParkingSlot(id: '5', state: SlotState.occupied),
      ParkingSlot(id: '6', state: SlotState.reserved),
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
}
