import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/app_config.dart';

void main() {
  test('uses a separate customer identity in app configuration', () {
    final config = AppConfig(
      gatewayBaseUri: Uri.parse('http://127.0.0.1:8101'),
      lotId: 'demo-01',
      customerId: 'customer-one',
    );

    expect(config.customerId, 'customer-one');
  });

  test('environment defaults include the demo customer', () {
    final config = AppConfig.fromEnvironment();

    expect(config.customerId, 'demo-customer');
  });
}
