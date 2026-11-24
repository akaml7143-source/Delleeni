import 'dart:convert';

import 'package:http/http.dart' as http;

/// Optional Supabase REST client for Delleeni.
///
/// Configure with --dart-define=SUPABASE_URL=... and
/// --dart-define=SUPABASE_ANON_KEY=... . Never embed service_role keys.
class DelleeniBackend {
  DelleeniBackend({
    String? baseUrl,
    String? anonKey,
    http.Client? client,
  })  : baseUrl = (baseUrl ?? const String.fromEnvironment('SUPABASE_URL')).trim(),
        anonKey = (anonKey ?? const String.fromEnvironment('SUPABASE_ANON_KEY')).trim(),
        _client = client ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final http.Client _client;

  bool get isConfigured =>
      baseUrl.startsWith('https://') && anonKey.isNotEmpty;

  Map<String, String> _headers({String? accessToken, bool jsonBody = false}) {
    if (!isConfigured) {
      throw StateError('خدمات دِلّيني الخلفية غير مهيأة بعد.');
    }
    return <String, String>{
      'apikey': anonKey,
      'Authorization': 'Bearer ${accessToken?.trim().isNotEmpty == true ? accessToken : anonKey}',
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      if (jsonBody) 'Prefer': 'return=representation',
    };
  }

  String get _basePath => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Uri _tableUri(String table, [Map<String, String>? query]) =>
      Uri.parse('$_basePath/rest/v1/$table').replace(queryParameters: query);

  Future<DelleeniSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('أدخل البريد وكلمة المرور.');
    }
    final response = await _client
        .post(
          Uri.parse('$_basePath/auth/v1/token?grant_type=password'),
          headers: _headers(jsonBody: true),
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['access_token']?.toString() ?? '';
    final user = decoded['user'] as Map<String, dynamic>? ?? const {};
    final userId = user['id']?.toString() ?? '';
    if (token.isEmpty || userId.isEmpty) {
      throw const FormatException('لم يُرجع الخادم جلسة دخول صالحة.');
    }
    return DelleeniSession(userId: userId, accessToken: token);
  }

  Future<Map<String, dynamic>?> fetchMyProfile({
    required String accessToken,
  }) async {
    final rows = await getRows('user_profiles', query: {
      'select': 'id,display_name,role',
      'limit': '1',
    }, accessToken: accessToken);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> fetchPendingPlaces({
    required String accessToken,
  }) => getRows('places', query: {
    'select': 'id,name,category,address,city,governorate,created_at,created_by',
    'status': 'eq.pending',
    'order': 'created_at.asc',
    'limit': '100',
  }, accessToken: accessToken);

  Future<List<Map<String, dynamic>>> fetchPendingReports({
    required String accessToken,
  }) => getRows('road_reports', query: {
    'select': 'id,kind,details,city,governorate,created_at,expires_at,created_by',
    'status': 'eq.pending',
    'expires_at': 'gt.${DateTime.now().toUtc().toIso8601String()}',
    'order': 'created_at.asc',
    'limit': '100',
  }, accessToken: accessToken);

  Future<List<Map<String, dynamic>>> fetchPendingContributions({
    required String accessToken,
  }) => getRows('community_contributions', query: {
    'select': 'id,entity_type,entity_id,action,payload,created_at,created_by',
    'status': 'eq.pending',
    'order': 'created_at.asc',
    'limit': '100',
  }, accessToken: accessToken);

  Future<bool> reviewPlace({
    required String placeId,
    required String decision,
    required String accessToken,
  }) => _callRpcBoolean('review_delleeni_place', {
    'p_place_id': placeId,
    'p_decision': decision,
  }, accessToken: accessToken);

  Future<bool> reviewRoadReport({
    required String reportId,
    required String decision,
    required String accessToken,
  }) => _callRpcBoolean('review_delleeni_road_report', {
    'p_report_id': reportId,
    'p_decision': decision,
  }, accessToken: accessToken);

  Future<bool> reviewContribution({
    required String contributionId,
    required String decision,
    String? reviewerNotes,
    required String accessToken,
  }) => _callRpcBoolean('review_delleeni_contribution', {
    'p_contribution_id': contributionId,
    'p_decision': decision,
    'p_reviewer_notes': reviewerNotes,
  }, accessToken: accessToken);

  Future<bool> _callRpcBoolean(
    String functionName,
    Map<String, dynamic> arguments, {
    required String accessToken,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_basePath/rest/v1/rpc/$functionName'),
          headers: _headers(accessToken: accessToken, jsonBody: true),
          body: jsonEncode(arguments),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) == true;
  }

  Future<DelleeniSession> signInAnonymously() async {
    final response = await _client
        .post(
          Uri.parse('$_basePath/auth/v1/signup'),
          headers: _headers(jsonBody: true),
          body: jsonEncode(const {'data': {'display_name': 'زائر دِلّيني'}}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final token = decoded['access_token']?.toString() ?? '';
    final user = decoded['user'] as Map<String, dynamic>? ?? const {};
    final userId = user['id']?.toString() ?? '';
    if (token.isEmpty || userId.isEmpty) {
      throw const FormatException('لم يُرجع الخادم جلسة مساهم صالحة.');
    }
    return DelleeniSession(userId: userId, accessToken: token);
  }

  Future<List<Map<String, dynamic>>> getRows(
    String table, {
    Map<String, String>? query,
    String? accessToken,
  }) async {
    final response = await _client
        .get(_tableUri(table, query), headers: _headers(accessToken: accessToken))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> submit(
    String table,
    Map<String, dynamic> values, {
    required String accessToken,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw ArgumentError('يلزم تسجيل الدخول قبل إرسال مساهمة.');
    }
    final response = await _client
        .post(
          _tableUri(table),
          headers: _headers(accessToken: accessToken, jsonBody: true),
          body: jsonEncode(values),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = response.body.isEmpty ? const [] : jsonDecode(response.body);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList(growable: false)
        : const [];
  }

  Future<List<Map<String, dynamic>>> nearbyPlaces({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
    String? category,
  }) async {
    if (!isConfigured) return const [];
    final response = await _client
        .post(
          Uri.parse('$_basePath/rest/v1/rpc/nearby_places'),
          headers: _headers(jsonBody: true),
          body: jsonEncode({
            'p_lat': latitude,
            'p_lon': longitude,
            'p_radius_m': radiusMeters.clamp(100, 20000),
            'p_category': category,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList(growable: false)
        : const [];
  }

  Future<List<Map<String, dynamic>>> fetchNearbyReports({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  }) => _callRpc('nearby_road_reports', {
    'p_lat': latitude,
    'p_lon': longitude,
    'p_radius_m': radiusMeters.clamp(100, 20000),
  });

  Future<List<Map<String, dynamic>>> fetchTransitRoutes({required String city}) =>
      getRows('transit_routes', query: {
        'select': 'id,name,mode,city,governorate,fare_min_iqd,fare_max_iqd,notes',
        'status': 'eq.published',
        'city': 'ilike.*$city*',
        'order': 'name.asc',
        'limit': '100',
      });

  Future<List<Map<String, dynamic>>> fetchAccessibilityFeatures({
    required double latitude,
    required double longitude,
    int radiusMeters = 3000,
  }) => _callRpc('nearby_accessibility_features', {
    'p_lat': latitude,
    'p_lon': longitude,
    'p_radius_m': radiusMeters.clamp(100, 10000),
  });

  Future<List<Map<String, dynamic>>> fetchTransitStops({required String routeId}) =>
      getRows('transit_stops', query: {
        'select': 'id,name,sequence_no',
        'route_id': 'eq.$routeId',
        'order': 'sequence_no.asc',
        'limit': '100',
      });

  Future<List<Map<String, dynamic>>> _callRpc(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    if (!isConfigured) return const [];
    final response = await _client
        .post(
          Uri.parse('$_basePath/rest/v1/rpc/$functionName'),
          headers: _headers(jsonBody: true),
          body: jsonEncode(arguments),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DelleeniBackendException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList(growable: false)
        : const [];
  }

  void close() => _client.close();
}

class DelleeniSession {
  const DelleeniSession({required this.userId, required this.accessToken});
  final String userId;
  final String accessToken;
}

class DelleeniBackendException implements Exception {
  const DelleeniBackendException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'DelleeniBackendException($statusCode): $message';
}
