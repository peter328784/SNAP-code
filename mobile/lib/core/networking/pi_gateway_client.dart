import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../contracts/parking_models.dart';

class GatewayException implements Exception {
  const GatewayException(
    this.message, {
    this.statusCode,
    this.uri,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final Uri? uri;
  final Object? cause;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    return '$message$status';
  }
}

class DuplicateSubmissionException implements Exception {
  const DuplicateSubmissionException();

  @override
  String toString() => '이전 요청의 응답을 기다리는 중입니다.';
}

class PiGatewayClient {
  PiGatewayClient({
    required Uri baseUri,
    this.requestTimeout = const Duration(seconds: 6),
    HttpClient? httpClient,
  })  : baseUri = _normalizedBaseUri(baseUri),
        _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final Duration requestTimeout;
  final HttpClient _httpClient;

  Uri get eventsUri => _endpoint('/v1/events').replace(
        scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      );

  Future<GatewayHealth> getHealth() async {
    return GatewayHealth.fromPayload(await _request('GET', '/health'));
  }

  Future<ParkingSnapshot> fetchSnapshot({String lotId = 'demo-01'}) async {
    final encodedLotId = Uri.encodeComponent(lotId);
    final path = '/v1/parking-lots/$encodedLotId/snapshot';
    final payload = await _request('GET', path);
    return _parseContract(
      'Snapshot',
      _endpoint(path),
      () => ParkingSnapshot.fromPayload(
        payload,
        strict: true,
        expectedLotId: lotId,
      ),
    );
  }

  Future<List<CustomerVehicle>> fetchVehicles({
    required String customerId,
  }) async {
    final encodedCustomerId = Uri.encodeComponent(customerId);
    final path = '/v1/customers/$encodedCustomerId/vehicles';
    final payload = await _request('GET', path);
    return _parseContract('차량 목록', _endpoint(path), () {
      final envelope = asStringMap(payload);
      final responseCustomerId =
          (envelope['customerId'] ?? envelope['customer_id'])?.toString();
      if (responseCustomerId != null && responseCustomerId != customerId) {
        throw FormatException(
          '차량 목록 customerId가 다릅니다: '
          'expected=$customerId actual=$responseCustomerId',
        );
      }
      final rawVehicles = payload is List<Object?>
          ? payload
          : envelope['vehicles'] ?? envelope['data'];
      if (rawVehicles is! List<Object?>) {
        throw const FormatException('차량 목록 응답에 vehicles 배열이 없습니다.');
      }
      return rawVehicles.map((value) {
        if (value is! Map<Object?, Object?>) {
          throw const FormatException('각 차량은 JSON object여야 합니다.');
        }
        return CustomerVehicle.fromJson(asStringMap(value));
      }).toList(growable: false);
    });
  }

  Future<CustomerVehicle> registerVehicle({
    required String customerId,
    required String vehicleNumber,
  }) async {
    final encodedCustomerId = Uri.encodeComponent(customerId);
    final path = '/v1/customers/$encodedCustomerId/vehicles';
    final payload = await _request(
      'POST',
      path,
      body: <String, Object?>{'vehicleNumber': vehicleNumber},
    );
    return _parseContract(
      '차량 등록',
      _endpoint(path),
      () => CustomerVehicle.fromPayload(payload),
    );
  }

  Future<GatewayCommandResult> requestParking({
    required String customerId,
    required String vehicleId,
    required int expectedMinutes,
    String lotId = 'demo-01',
    ParkingSnapshot? fallback,
  }) async {
    final payload = await _request(
      'POST',
      '/v1/parking-requests',
      body: <String, Object?>{
        'customerId': customerId,
        'vehicleId': vehicleId,
        'expectedMinutes': expectedMinutes,
      },
    );
    return _parseCommandResult(
      payload,
      path: '/v1/parking-requests',
      lotId: lotId,
      fallback: fallback,
    );
  }

  Future<GatewayCommandResult> confirmParking({
    required String requestId,
    String lotId = 'demo-01',
    ParkingSnapshot? fallback,
  }) async {
    final encodedRequestId = Uri.encodeComponent(requestId);
    final payload = await _request(
      'POST',
      '/v1/parking-requests/$encodedRequestId/confirm',
      body: const <String, Object?>{},
    );
    return _parseCommandResult(
      payload,
      path: '/v1/parking-requests/$encodedRequestId/confirm',
      lotId: lotId,
      fallback: fallback,
    );
  }

  Future<JobSnapshot> fetchJob(String jobId) async {
    final encodedJobId = Uri.encodeComponent(jobId);
    return JobSnapshot.fromJson(
      asStringMap(await _request('GET', '/v1/jobs/$encodedJobId')),
    );
  }

  Future<GatewayCommandResult> requestRetrieval({
    required String customerId,
    required String vehicleId,
    String lotId = 'demo-01',
    ParkingSnapshot? fallback,
  }) async {
    final payload = await _request(
      'POST',
      '/v1/retrieval-requests',
      body: <String, Object?>{
        'customerId': customerId,
        'vehicleId': vehicleId,
      },
    );
    return _parseCommandResult(
      payload,
      path: '/v1/retrieval-requests',
      lotId: lotId,
      fallback: fallback,
    );
  }

  void close() => _httpClient.close(force: true);

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = _endpoint(path);
    try {
      final request =
          await _httpClient.openUrl(method, uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(requestTimeout);
      final responseBody =
          await response.transform(utf8.decoder).join().timeout(requestTimeout);
      final payload = responseBody.trim().isEmpty
          ? const <String, Object?>{}
          : _decodeJson(responseBody, uri);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = asStringMap(payload);
        throw GatewayException(
          (error['detail'] ?? error['message'] ?? 'Gateway 요청이 실패했습니다.')
              .toString(),
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      return payload;
    } on GatewayException {
      rethrow;
    } on TimeoutException catch (error) {
      throw GatewayException(
        'Gateway 응답 시간이 초과됐습니다.',
        uri: uri,
        cause: error,
      );
    } on SocketException catch (error) {
      throw GatewayException('Gateway에 연결할 수 없습니다.', uri: uri, cause: error);
    } on HandshakeException catch (error) {
      throw GatewayException(
        'Gateway TLS 연결에 실패했습니다.',
        uri: uri,
        cause: error,
      );
    } on HttpException catch (error) {
      throw GatewayException(
        'Gateway HTTP 통신에 실패했습니다.',
        uri: uri,
        cause: error,
      );
    }
  }

  Object? _decodeJson(String value, Uri uri) {
    try {
      return jsonDecode(value);
    } on FormatException catch (error) {
      throw GatewayException(
        'Gateway가 올바른 JSON을 반환하지 않았습니다.',
        uri: uri,
        cause: error,
      );
    }
  }

  GatewayCommandResult _parseCommandResult(
    Object? payload, {
    required String path,
    required String lotId,
    ParkingSnapshot? fallback,
  }) {
    return _parseContract(
      '명령 응답',
      _endpoint(path),
      () => GatewayCommandResult.fromPayload(
        payload,
        fallback: fallback,
        strict: true,
        expectedLotId: lotId,
      ),
    );
  }

  T _parseContract<T>(String name, Uri uri, T Function() parse) {
    try {
      return parse();
    } on FormatException catch (error) {
      throw GatewayException(
        '$name 계약 오류: ${error.message}',
        uri: uri,
        cause: error,
      );
    }
  }

  Uri _endpoint(String suffix) {
    final prefix = baseUri.path == '/'
        ? ''
        : baseUri.path.endsWith('/')
            ? baseUri.path.substring(0, baseUri.path.length - 1)
            : baseUri.path;
    final path = suffix.startsWith('/') ? suffix : '/$suffix';
    return baseUri.replace(path: '$prefix$path');
  }

  static Uri _normalizedBaseUri(Uri value) {
    if (!value.hasAuthority || !{'http', 'https'}.contains(value.scheme)) {
      throw ArgumentError.value(value, 'baseUri', 'http 또는 https URI가 필요합니다.');
    }
    if (value.hasQuery || value.hasFragment) {
      throw ArgumentError.value(
        value,
        'baseUri',
        'query 또는 fragment가 없는 Gateway 기본 URI가 필요합니다.',
      );
    }
    return value;
  }
}
