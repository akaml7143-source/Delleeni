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

  Uri _tableUri(String table, [Map<String, String>? query]) {
    final root = Uri.parse(baseUrl);
    return root.replace(
      path: '${root.path.replaceFirst(RegExp(r'/\$'), '')}/rest/v1/$table',
      queryParameters: query,
    );
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
          Uri.parse('${baseUrl.replaceFirst(RegExp(r'/\$'), '')}/rest/v1/rpc/nearby_places'),
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
  }) => getRows('road_reports', query: {
    'select': 'id,kind,details,city,governorate,created_at,expires_at',
    'status': 'eq.verified',
    'expires_at': 'gt.${DateTime.now().toUtc().toIso8601String()}',
    'order': 'created_at.desc',
    'limit': '100',
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
  }) => getRows('accessibility_features', query: {
    'select': 'id,kind,notes,verified,created_at',
    'status': 'eq.published',
    'verified': 'eq.true',
    'limit': '100',
  });

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
