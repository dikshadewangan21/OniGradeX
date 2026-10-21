import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get isNetwork => status == null;
  @override
  String toString() => message;
}

class Session {
  Session(this.token, this.role, this.userId);
  final String token;
  final String role; // admin | officer | farmer
  final String userId;
}

class ApiClient {
  ApiClient(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (_token != null) o.headers['Authorization'] = 'Bearer $_token';
      h.next(o);
    }));
  }

  final Dio _dio;
  final _storage = const FlutterSecureStorage();
  String? _token;

  Future<Session?> restore() async {
    final t = await _storage.read(key: 'token');
    final r = await _storage.read(key: 'role');
    final u = await _storage.read(key: 'uid');
    if (t == null || r == null || u == null) return null;
    _token = t;
    return Session(t, r, u);
  }

  Future<void> logout() async {
    _token = null;
    await _storage.deleteAll();
  }

  String get baseUrl => _dio.options.baseUrl;

  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get('/api/v1/health');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<T> _call<T>(Future<Response<dynamic>> Function() f, T Function(dynamic) map) async {
    try {
      final r = await f();
      return map(r.data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == null) {
        throw ApiException('Cannot connect to server at ${_dio.options.baseUrl}. Please verify your network or server status.');
      }
      final d = e.response?.data;
      var msg = 'Request failed ($code)';
      if (d is Map && d['detail'] != null) {
        msg = d['detail'] is String ? d['detail'] as String : (d['detail'] as List).map((x) => x['msg']).join('; ');
      }
      if (code == 401 && _token != null) msg = 'Session expired. Please sign in again.';
      if (code == 401 && _token == null) msg = 'Invalid mobile number or password.';
      if (code == 429) msg = msg.isNotEmpty ? msg : 'Too many attempts. Please wait a moment before trying again.';
      if (code == 500) msg = 'Server encountered an internal error. Please try again or verify backend configuration.';
      throw ApiException(msg, status: code);
    }
  }

  Future<Session> login(String phone, String password) async {
    final s = await _call(
      () => _dio.post('/api/v1/auth/login', data: {'phone': phone, 'password': password}),
      (d) => Session(d['access_token'] as String, d['role'] as String, d['user_id'] as String),
    );
    _token = s.token;
    await _storage.write(key: 'token', value: s.token);
    await _storage.write(key: 'role', value: s.role);
    await _storage.write(key: 'uid', value: s.userId);
    return s;
  }

  Future<void> register(String phone, String name, String password) => _call(
      () => _dio.post('/api/v1/auth/register', data: {'phone': phone, 'name': name, 'password': password}),
      (_) {});

  Future<Map<String, dynamic>> me() => _call(() => _dio.get('/api/v1/auth/me'), (d) => Map<String, dynamic>.from(d));

  Future<Map<String, dynamic>> activeRule() =>
      _call(() => _dio.get('/api/v1/rules/active'), (d) => Map<String, dynamic>.from(d));

  Future<List<dynamic>> listRules() => _call(() => _dio.get('/api/v1/rules'), (d) => List<dynamic>.from(d));

  Future<void> publishRule(Map<String, dynamic> definition) =>
      _call(() => _dio.post('/api/v1/rules', data: {'definition': definition, 'activate': true}), (_) {});

  Future<List<dynamic>> mandis() => _call(() => _dio.get('/api/v1/mandis'), (d) => List<dynamic>.from(d));

  Future<void> createMandi(String name, String state, String district) => _call(
      () => _dio.post('/api/v1/mandis', data: {'name': name, 'state': state, 'district': district}), (_) {});

  Future<void> adminCreateUser(Map<String, dynamic> body) =>
      _call(() => _dio.post('/api/v1/admin/users', data: body), (_) {});

  Future<Map<String, dynamic>> syncCertificate(Map<String, dynamic> body) =>
      _call(() => _dio.post('/api/v1/certificates/sync', data: body), (d) => Map<String, dynamic>.from(d));

  Future<void> uploadImage(String certId, String path) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path,
          filename: 'batch.jpg', contentType: DioMediaType('image', path.toLowerCase().endsWith('png') ? 'png' : 'jpeg'))
    });
    await _call(() => _dio.post('/api/v1/certificates/$certId/image', data: form), (_) {});
  }

  Future<Map<String, dynamic>> listCertificates({int page = 1, String? grade}) => _call(
      () => _dio.get('/api/v1/certificates', queryParameters: {'page': page, 'page_size': 20, if (grade != null) 'grade': grade}),
      (d) => Map<String, dynamic>.from(d));

  Future<Map<String, dynamic>> verify(String id) =>
      _call(() => _dio.get('/api/v1/verify/$id'), (d) => Map<String, dynamic>.from(d));

  Future<void> raiseDispute(String certId, String reason) => _call(
      () => _dio.post('/api/v1/disputes', data: {'certificate_id': certId, 'reason': reason}), (_) {});

  Future<Map<String, dynamic>> listDisputes({String? status, int page = 1}) => _call(
      () => _dio.get('/api/v1/disputes', queryParameters: {'page': page, if (status != null) 'status': status}),
      (d) => Map<String, dynamic>.from(d));

  Future<void> resolveDispute(String id, String status, String note) => _call(
      () => _dio.post('/api/v1/disputes/$id/resolve', data: {'status': status, 'resolution_note': note}), (_) {});

  Future<void> assignDispute(String id, String officerId) => _call(
      () => _dio.post('/api/v1/disputes/$id/assign', data: {'officer_id': officerId}), (_) {});

  Future<List<dynamic>> assignedDisputes() => _call(
      () => _dio.get('/api/v1/disputes/assigned'), (d) => List<dynamic>.from(d));

  Future<void> reinspectDispute(String id, String certId, {String? notes}) => _call(
      () => _dio.post('/api/v1/disputes/$id/reinspect', data: {'certificate_id': certId, if (notes != null) 'notes': notes}), (_) {});

  Future<List<dynamic>> notifications() => _call(
      () => _dio.get('/api/v1/notifications'), (d) => List<dynamic>.from(d));

  Future<void> markNotificationRead(String id) => _call(
      () => _dio.post('/api/v1/notifications/$id/read'), (_) {});

  Future<Map<String, dynamic>> summary() =>
      _call(() => _dio.get('/api/v1/analytics/summary'), (d) => Map<String, dynamic>.from(d));

  Future<List<dynamic>> trends() => _call(() => _dio.get('/api/v1/analytics/trends'), (d) => List<dynamic>.from(d));

  Future<Map<String, dynamic>> flags() =>
      _call(() => _dio.get('/api/v1/analytics/flags'), (d) => Map<String, dynamic>.from(d));

  Future<Map<String, dynamic>> stockHealth() =>
      _call(() => _dio.get('/api/v1/analytics/stock-health'), (d) => Map<String, dynamic>.from(d));

  Future<Map<String, dynamic>> enamPrice(String mandi) => _call(
      () => _dio.get('/api/v1/prices/enam', queryParameters: {'mandi': mandi}), (d) => Map<String, dynamic>.from(d));
}
