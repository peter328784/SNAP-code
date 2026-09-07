class AppConfig {
  AppConfig({
    required this.gatewayBaseUri,
    required this.lotId,
    required this.customerId,
  });

  factory AppConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment(
      'PI_API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8101',
    );
    const rawLotId = String.fromEnvironment(
      'PI_LOT_ID',
      defaultValue: 'demo-01',
    );
    const rawCustomerId = String.fromEnvironment(
      'PI_CUSTOMER_ID',
      defaultValue: String.fromEnvironment(
        'SNAP_CUSTOMER_ID',
        defaultValue: 'demo-customer',
      ),
    );

    final baseUri = Uri.tryParse(rawBaseUrl.trim());
    if (baseUri == null ||
        !baseUri.hasAuthority ||
        !{'http', 'https'}.contains(baseUri.scheme)) {
      throw ArgumentError.value(
        rawBaseUrl,
        'PI_API_BASE_URL',
        'http 또는 https Gateway URL이어야 합니다.',
      );
    }

    final lotId = rawLotId.trim();
    if (lotId.isEmpty) {
      throw ArgumentError.value(rawLotId, 'PI_LOT_ID', '주차장 ID가 필요합니다.');
    }

    final customerId = rawCustomerId.trim();
    if (customerId.isEmpty) {
      throw ArgumentError.value(
        rawCustomerId,
        'PI_CUSTOMER_ID',
        '고객 ID가 필요합니다.',
      );
    }

    return AppConfig(
      gatewayBaseUri: baseUri,
      lotId: lotId,
      customerId: customerId,
    );
  }

  final Uri gatewayBaseUri;
  final String lotId;
  final String customerId;
}
