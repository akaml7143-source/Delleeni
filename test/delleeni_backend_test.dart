import 'dart:convert';

import 'package:delleeni/services/delleeni_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('backend stays disabled until public Supabase config is supplied', () {
    final backend = DelleeniBackend(baseUrl: '', anonKey: '');
    expect(backend.isConfigured, isFalse);
    backend.close();
  });

  test('nearby lookup safely returns no rows while backend is not configured', () async {
    final backend = DelleeniBackend(baseUrl: '', anonKey: '');
    expect(
      await backend.nearbyPlaces(latitude: 33.3152, longitude: 44.3661),
      isEmpty,
    );
    backend.close();
  });

  test('anonymous contributor signup uses normalized Supabase URL', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://demo.supabase.co/auth/v1/signup');
      expect(request.headers['apikey'], 'public-key');
      expect(request.headers.entries.firstWhere((entry) => entry.key.toLowerCase() == 'authorization').value, 'Bearer public-key');
      return http.Response(jsonEncode({
        'access_token': 'test-access-token',
        'user': {'id': 'test-user-id'},
      }), 200);
    });
    final backend = DelleeniBackend(
      baseUrl: 'https://demo.supabase.co/',
      anonKey: 'public-key',
      client: client,
    );
    final session = await backend.signInAnonymously();
    expect(session.userId, 'test-user-id');
    expect(session.accessToken, 'test-access-token');
    backend.close();
  });

  test('moderator password login uses Supabase password grant', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/auth/v1/token');
      expect(request.url.queryParameters['grant_type'], 'password');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['email'], 'moderator@example.test');
      expect(body['password'], 'correct-horse');
      return http.Response(jsonEncode({
        'access_token': 'moderator-token',
        'user': {'id': 'moderator-id'},
      }), 200);
    });
    final backend = DelleeniBackend(
      baseUrl: 'https://demo.supabase.co',
      anonKey: 'public-key',
      client: client,
    );
    final session = await backend.signInWithPassword(
      email: 'moderator@example.test',
      password: 'correct-horse',
    );
    expect(session.userId, 'moderator-id');
    expect(session.accessToken, 'moderator-token');
    backend.close();
  });

  test('moderation RPC uses authenticated access token and rejects unknown result', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/review_delleeni_place');
      expect(request.headers['Authorization'], 'Bearer moderator-token');
      expect(jsonDecode(request.body), {
        'p_place_id': 'place-1',
        'p_decision': 'published',
      });
      return http.Response('true', 200);
    });
    final backend = DelleeniBackend(
      baseUrl: 'https://demo.supabase.co',
      anonKey: 'public-key',
      client: client,
    );
    expect(await backend.reviewPlace(
      placeId: 'place-1',
      decision: 'published',
      accessToken: 'moderator-token',
    ), isTrue);
    backend.close();
  });

  test('nearby road reports use spatial RPC with the requested radius', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/nearby_road_reports');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_lat'], 31.8);
      expect(body['p_lon'], 47.1);
      expect(body['p_radius_m'], 2500);
      return http.Response.bytes(utf8.encode(jsonEncode([
        {'id': 'report-1', 'kind': 'traffic', 'governorate': 'ميسان'},
      ])), 200);
    });
    final backend = DelleeniBackend(
      baseUrl: 'https://demo.supabase.co',
      anonKey: 'public-key',
      client: client,
    );
    final rows = await backend.fetchNearbyReports(
      latitude: 31.8,
      longitude: 47.1,
      radiusMeters: 2500,
    );
    expect(rows, hasLength(1));
    expect(rows.first['kind'], 'traffic');
    backend.close();
  });
}
