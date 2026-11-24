import 'package:delleeni/services/delleeni_backend.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
