import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml hide Position;
import 'package:maplibre_gl/maplibre_gl.dart' as mlg;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const DelleeniApp());

class DelleeniApp extends StatefulWidget {
  const DelleeniApp({super.key});

  @override
  State<DelleeniApp> createState() => _DelleeniAppState();
}

class _DelleeniAppState extends State<DelleeniApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() => setState(() {
        _themeMode =
            _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      });

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دِلِّينِي',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        themeMode: _themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087E70)),
          scaffoldBackgroundColor: const Color(0xFFF5F7F7),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF35B7A3),
            brightness: Brightness.dark,
          ),
        ),
        home: MapHomePage(
          isDark: _themeMode == ThemeMode.dark,
          onToggleTheme: _toggleTheme,
        ),
      );
}

class IraqPlace {
  const IraqPlace(this.name, this.governorate, this.point);
  final String name;
  final String governorate;
  final LatLng point;
}


class NearbyPlace {
  const NearbyPlace({required this.id, required this.name, required this.category, required this.point, this.address = ''});
  final int id; final String name; final String category; final LatLng point; final String address;
}

class RouteManeuver {
  const RouteManeuver({required this.point, required this.instruction});
  final LatLng point;
  final String instruction;
}

// مراكز مدن تقريبية وليست عناوين أو حدوداً إدارية رسمية.
const iraqPlaces = <IraqPlace>[
  IraqPlace('بغداد', 'بغداد', LatLng(33.3152, 44.3661)),
  IraqPlace('البصرة', 'البصرة', LatLng(30.5085, 47.7804)),
  IraqPlace('الموصل', 'نينوى', LatLng(36.3350, 43.1189)),
  IraqPlace('أربيل', 'أربيل', LatLng(36.1901, 44.0091)),
  IraqPlace('النجف', 'النجف', LatLng(32.0003, 44.3354)),
  IraqPlace('كربلاء', 'كربلاء', LatLng(32.6160, 44.0249)),
  IraqPlace('العمارة', 'ميسان', LatLng(31.8359, 47.1448)),
  IraqPlace('الناصرية', 'ذي قار', LatLng(31.0570, 46.2573)),
  IraqPlace('الكوت', 'واسط', LatLng(32.5128, 45.8182)),
  IraqPlace('الحلة', 'بابل', LatLng(32.4811, 44.4217)),
  IraqPlace('الديوانية', 'القادسية', LatLng(31.9929, 44.9255)),
  IraqPlace('السماوة', 'المثنى', LatLng(31.3185, 45.2803)),
  IraqPlace('تكريت', 'صلاح الدين', LatLng(34.6071, 43.6782)),
  IraqPlace('بعقوبة', 'ديالى', LatLng(33.7485, 44.6427)),
  IraqPlace('الرمادي', 'الأنبار', LatLng(33.4237, 43.3078)),
  IraqPlace('كركوك', 'كركوك', LatLng(35.4681, 44.3922)),
  IraqPlace('دهوك', 'دهوك', LatLng(36.8671, 42.9500)),
  IraqPlace('السليمانية', 'السليمانية', LatLng(35.5613, 45.4300)),
];

const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

class MapHomePage extends StatefulWidget {
  const MapHomePage({
    required this.isDark,
    required this.onToggleTheme,
    this.showMap = true,
    super.key,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final bool showMap;

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  mlg.MapLibreMapController? _map;
  bool _mapStyleLoaded = false;
  bool _is3d = true;
  int _mapPaletteIndex = 0;
  static const List<String> _mapPaletteIds = ['green', 'blue', 'gold', 'gray', 'pink'];
  static const List<String> _mapPaletteNames = ['الأخضر', 'الأزرق', 'الذهبي', 'الرمادي', 'الوردي'];

  String get _mapStyleUrl =>
      'https://raw.githubusercontent.com/akaml7143-source/Delleeni/feature/iraq-3d-map/assets/map_styles/${_mapPaletteIds[_mapPaletteIndex]}.json';

  Future<void> _loadMapPalette() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('map_palette_index') ?? 0;
    if (!mounted) return;
    setState(() => _mapPaletteIndex = saved.clamp(0, _mapPaletteIds.length - 1).toInt());
  }

  Future<void> _cycleMapPalette() async {
    final next = (_mapPaletteIndex + 1) % _mapPaletteIds.length;
    setState(() {
      _mapStyleLoaded = false;
      _map = null;
      _mapPaletteIndex = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('map_palette_index', next);
    if (mounted) {
      _message('تم تغيير ألوان الخريطة إلى النمط ${_mapPaletteNames[next]}');
    }
  }
  bool _selectingOriginFromMap = false;
  bool _showAdvancedSearchOptions = false;
  final TextEditingController _fromController =
      TextEditingController(text: 'موقعي الحالي');
  final TextEditingController _toController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  LatLng? _userPoint;
  LatLng? _routeOrigin;
  LatLng? _selectedMapOrigin;
  LatLng? _routeDestination;
  List<LatLng> _routePoints = [];
  List<String> _instructions = [];
  List<RouteManeuver> _routeManeuvers = [];
  int _nextManeuverIndex = 0;
  final Map<int, Set<int>> _announcedManeuverStages = <int, Set<int>>{};
  String _nextInstruction = 'حدد نقطة الانطلاق والوجهة';
  String _voiceText = '';
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;
  bool _loadingRoute = false;
  bool _tracking = false;
  double _headingDegrees = 0;
  Timer? _safetyReminderTimer;
  int _safetyReminderIndex = 0;
  bool _listening = false;
  bool _speaking = false;
  bool _voiceConversation = false;
  bool _speechInitialized = false;
  bool _voiceTurnHandled = false;
  final List<Map<String, String>> _voiceChatHistory = <Map<String, String>>[];
  StreamSubscription<Position>? _positionSubscription;
  DateTime? _lastRerouteAt;
  bool _rerouting = false;
  bool _loadingNearby = false;
  List<NearbyPlace> _nearbyPlaces = [];
  NearbyPlace? _selectedNearby;
  final Set<int> _favoritePlaceIds = <int>{};
  bool _showFavoritesOnly = false;
  String _nearbyCategoryFilter = 'الكل';
  String _nearbySearchQuery = '';
  final List<NearbyPlace> _recentDestinations = <NearbyPlace>[];
  final Set<int> _announcedRoadAlertIds = <int>{};

  String _nearbyCategoryLabel(String category) {
    const labels = <String, String>{
      'restaurant': 'مطعم',
      'cafe': 'مقهى',
      'fast_food': 'وجبات سريعة',
      'food_court': 'ساحة طعام',
      'ice_cream': 'مثلجات',
      'hospital': 'مستشفى',
      'fire_station': 'مركز إطفاء',
      'ambulance_station': 'مركز إسعاف',
      'construction': 'أعمال طريق',
      'roadworks': 'أعمال طريق',
      'traffic_calming': 'مطب تهدئة',
      'pothole': 'حفرة بالطريق',
      'damaged_road': 'طريق متضرر',
      'clinic': 'عيادة',
      'doctors': 'طبيب',
      'dentist': 'طبيب أسنان',
      'pharmacy': 'صيدلية',
      'healthcare': 'خدمات صحية',
      'fuel': 'محطة وقود',
      'bank': 'مصرف',
      'atm': 'صراف آلي',
      'school': 'مدرسة',
      'police': 'مركز شرطة',
      'post_office': 'بريد',
      'library': 'مكتبة',
      'parking': 'موقف سيارات',
      'marketplace': 'سوق',
      'car_wash': 'غسل سيارات',
      'charging_station': 'شحن مركبات',
      'supermarket': 'سوبرماركت',
      'convenience': 'متجر مواد غذائية',
      'mall': 'مركز تسوق',
      'clothes': 'ملابس',
      'bakery': 'مخبز',
      'hotel': 'فندق',
      'guest_house': 'دار ضيافة',
      'museum': 'متحف',
      'park': 'حديقة',
      'playground': 'ملعب أطفال',
      'bus_station': 'محطة حافلات',
    };
    return labels[category.toLowerCase()] ?? category.replaceAll('_', ' ');
  }

  bool _matchesNearbyCategory(NearbyPlace place) {
    if (_nearbyCategoryFilter == 'الكل') return true;
    final category = place.category.toLowerCase();
    switch (_nearbyCategoryFilter) {
      case 'مطاعم ومقاهي':
        return ['restaurant', 'cafe', 'fast_food', 'food_court', 'ice_cream', 'bakery'].contains(category);
      case 'صحة':
        return ['hospital', 'clinic', 'doctors', 'pharmacy', 'dentist', 'fire_station', 'ambulance_station'].contains(category) || category == 'healthcare';
      case 'سلامة الطرق':
        return ['construction', 'roadworks', 'traffic_calming', 'pothole', 'damaged_road'].contains(category);
      case 'تسوق':
        return place.category.isNotEmpty && !['restaurant', 'cafe', 'fast_food', 'hospital', 'clinic', 'pharmacy', 'fuel', 'bank', 'atm', 'school', 'police'].contains(category);
      case 'خدمات':
        return ['fuel', 'bank', 'atm', 'school', 'police', 'post_office', 'library', 'parking', 'car_wash', 'charging_station', 'bus_station'].contains(category);
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFavoritePlaces();
    _loadRecentDestinations();
    _loadMapPalette();
  }

  Future<void> _loadFavoritePlaces() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _favoritePlaceIds.addAll(prefs.getStringList('favorite_place_ids')?.map(int.tryParse).whereType<int>() ?? const <int>[]));
  }

  Future<void> _loadRecentDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('recent_destinations') ?? const <String>[];
    final places = <NearbyPlace>[];
    for (final value in saved) {
      try {
        final item = jsonDecode(value) as Map<String, dynamic>;
        places.add(NearbyPlace(
          id: (item['id'] as num).toInt(),
          name: item['name'] as String,
          category: item['category'] as String? ?? 'مكان',
          point: LatLng(
            (item['lat'] as num).toDouble(),
            (item['lon'] as num).toDouble(),
          ),
          address: item['address'] as String? ?? '',
        ));
      } catch (_) {
        // تجاهل السجل التالف دون تعطيل بقية السجلات.
      }
    }
    if (!mounted) return;
    setState(() {
      _recentDestinations
        ..clear()
        ..addAll(places.take(8));
    });
  }

  Future<void> _saveRecentDestination(NearbyPlace place) async {
    setState(() {
      _recentDestinations.removeWhere((item) =>
          item.name == place.name &&
          item.point.latitude == place.point.latitude &&
          item.point.longitude == place.point.longitude);
      _recentDestinations.insert(0, place);
      if (_recentDestinations.length > 8) {
        _recentDestinations.removeRange(8, _recentDestinations.length);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'recent_destinations',
      _recentDestinations.map((item) => jsonEncode({
        'id': item.id,
        'name': item.name,
        'category': item.category,
        'lat': item.point.latitude,
        'lon': item.point.longitude,
        'address': item.address,
      })).toList(),
    );
  }

  Future<void> _clearRecentDestinations() async {
    setState(_recentDestinations.clear);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_destinations');
  }

  Future<void> _toggleFavoritePlace(int id) async {
    setState(() {
      if (!_favoritePlaceIds.add(id)) _favoritePlaceIds.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_place_ids', _favoritePlaceIds.map((value) => value.toString()).toList());
  }

  List<IraqPlace> _findPlaces(String query) {
    final value = query.trim();
    if (value.isEmpty) return [];
    return iraqPlaces
        .where((p) => p.name.contains(value) || p.governorate.contains(value))
        .toList();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _safetyReminderTimer?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(value, textDirection: TextDirection.rtl)));
  }

  Future<LatLng?> _currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _message('فعّل خدمة الموقع GPS أولاً');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _message('التطبيق يحتاج إذن الموقع حتى يحدد مكانك');
      return null;
    }
    final position = await Geolocator.getCurrentPosition();
    final point = LatLng(position.latitude, position.longitude);
    if (mounted) setState(() => _userPoint = point);
    return point;
  }


  void _selectMapDestination(mlg.LatLng coordinates) {
    final point = LatLng(coordinates.latitude, coordinates.longitude);
    if (_selectingOriginFromMap) {
      setState(() {
        _selectedMapOrigin = point;
        _fromController.text = 'نقطة من الخريطة';
        _selectingOriginFromMap = false;
      });
      unawaited(_syncMapAnnotations());
      _message('تم تحديد نقطة الانطلاق • ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}');
      return;
    }
    final place = NearbyPlace(
      id: -((point.latitude * 100000).round().abs() +
          (point.longitude * 100000).round().abs()),
      name: 'نقطة من الخريطة',
      category: 'وجهة محددة',
      point: point,
      address: 'إحداثيات: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
    );
    setState(() {
      _selectedNearby = place;
      _toController.text = place.name;
      _routeDestination = point;
    });
    unawaited(_syncMapAnnotations());
    _message('تم تحديد الوجهة على الخريطة • ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}');
  }

  Future<void> _addGovernorateBoundaries() async {
    final controller = _map;
    if (controller == null || !_mapStyleLoaded) return;

    const sourceId = 'iraq-governorates-ar';
    const lineLayerId = 'iraq-governorate-borders-ar';
    const labelLayerId = 'iraq-governorate-labels-ar';
    const geoJsonUrl =
        'https://raw.githubusercontent.com/akaml7143-source/Delleeni/feature/iraq-3d-map/assets/data/iraq_governorates.geojson';

    const paletteColors = <String>[
      '#176b45',
      '#2563a6',
      '#a47a20',
      '#68727d',
      '#b45b7a',
    ];
    final borderColor = paletteColors[_mapPaletteIndex.clamp(0, 4)];

    try {
      final sourceIds = await controller.getSourceIds();
      if (!sourceIds.contains(sourceId)) {
        await controller.addSource(
          sourceId,
          const mlg.GeojsonSourceProperties(
            data: geoJsonUrl,
            attribution: 'geoBoundaries · CC0 1.0 · Iraq ADM1 (18 governorates)',
            maxzoom: 10,
            tolerance: 0.25,
          ),
        );
      }

      final layerIds = await controller.getLayerIds();
      if (!layerIds.contains(lineLayerId)) {
        await controller.addLineLayer(
          sourceId,
          lineLayerId,
          mlg.LineLayerProperties(
            lineColor: borderColor,
            lineWidth: ['interpolate', ['linear'], ['zoom'], 4.5, 1.2, 7, 2.0, 10, 2.7],
            lineOpacity: 1.0,
            lineJoin: 'round',
          ),
          minzoom: 4.5,
        );
      }

      if (!layerIds.contains(labelLayerId)) {
        await controller.addSymbolLayer(
          sourceId,
          labelLayerId,
          mlg.SymbolLayerProperties(
            textField: ['get', 'name_ar'],
            textFont: ['Noto Sans Regular'],
            textSize: ['interpolate', ['linear'], ['zoom'], 5, 9, 7, 11, 10, 13],
            textMaxWidth: 8,
            textAnchor: 'center',
            textColor: borderColor,
            textHaloColor: '#ffffff',
            textHaloWidth: 1.5,
            textHaloBlur: 0.3,
            textPadding: 3,
            textAllowOverlap: false,
            textIgnorePlacement: false,
          ),
          minzoom: 5,
        );
      }
    } catch (error) {
      debugPrint('Governorate boundaries could not be added: $error');
    }
  }

  Future<void> _syncMapAnnotations() async {
    final map = _map;
    if (map == null || !_mapStyleLoaded || map.isDisposed) return;
    try {
      await map.clearLines();
      await map.clearCircles();
      if (_routePoints.length > 1) {
        await map.addLine(mlg.LineOptions(
          geometry: _routePoints
              .map((point) => mlg.LatLng(point.latitude, point.longitude))
              .toList(),
          lineColor: '#08AFA0',
          lineWidth: 6,
        ));
      }
      if (_selectedMapOrigin != null) {
        await map.addCircle(mlg.CircleOptions(
          geometry: mlg.LatLng(_selectedMapOrigin!.latitude, _selectedMapOrigin!.longitude),
          circleColor: '#16A34A', circleRadius: 9,
          circleStrokeColor: '#FFFFFF', circleStrokeWidth: 2,
        ));
      }
      if (_routeOrigin != null && _userPoint == null && _selectedMapOrigin == null) {
        await map.addCircle(mlg.CircleOptions(
          geometry: mlg.LatLng(_routeOrigin!.latitude, _routeOrigin!.longitude),
          circleColor: '#16A34A',
          circleRadius: 8,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));
      }
      if (_routeDestination != null) {
        await map.addCircle(mlg.CircleOptions(
          geometry: mlg.LatLng(_routeDestination!.latitude, _routeDestination!.longitude),
          circleColor: '#DC2626',
          circleRadius: 9,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));
      }
      for (final place in _nearbyPlaces) {
        final roadAlert = ['construction', 'roadworks', 'traffic_calming', 'pothole', 'damaged_road'].contains(place.category);
        final emergency = ['hospital', 'clinic', 'pharmacy', 'fire_station', 'ambulance_station', 'police'].contains(place.category);
        await map.addCircle(mlg.CircleOptions(
          geometry: mlg.LatLng(place.point.latitude, place.point.longitude),
          circleColor: roadAlert ? '#DC2626' : emergency ? '#2563EB' : '#E9A23B',
          circleRadius: roadAlert ? 7 : 5,
          circleStrokeColor: '#FFFFFF', circleStrokeWidth: 1.5,
        ));
      }
      if (_userPoint != null) {
        await map.addCircle(mlg.CircleOptions(
          geometry: mlg.LatLng(_userPoint!.latitude, _userPoint!.longitude),
          circleColor: '#073B5C',
          circleRadius: 8,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));
      }
    } catch (_) {
      // The map style can be replaced while GPS or route updates are arriving.
    }
  }

  Future<void> _loadNearbyPlaces({bool showSheet = true}) async {
    if (_loadingNearby) return;
    final center = _userPoint ?? await _currentLocation();
    if (center == null) return;
    setState(() => _loadingNearby = true);
    try {
      const radius = 6000;
      final query = '[out:json][timeout:30];('
          'nwr(around:$radius,${center.latitude},${center.longitude})["name"]["amenity"~"restaurant|cafe|fast_food|food_court|ice_cream|hospital|clinic|doctors|dentist|pharmacy|fuel|bank|atm|school|police|fire_station|ambulance_station|post_office|library|parking|marketplace|car_wash|charging_station|bus_station"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["name"]["shop"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["name"]["healthcare"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["name"]["tourism"~"hotel|guest_house|museum"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["name"]["leisure"~"park|playground"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["highway"~"construction|roadworks|traffic_calming"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["traffic_calming"];'
          'nwr(around:$radius,${center.latitude},${center.longitude})["hazard"~"pothole|damaged_road"];'
          ');out center 120;';
      // نجرب أكثر من خادم عام؛ قد يتوقف أحد خوادم Overpass مؤقتاً.
      http.Response? response;
      Object? lastError;
      const endpoints = [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://overpass.private.coffee/api/interpreter',
      ];
      for (final endpoint in endpoints) {
        try {
          final candidate = await http
              .post(
                Uri.parse(endpoint),
                headers: const {'Accept': 'application/json'},
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 25));
          if (candidate.statusCode == 200) {
            response = candidate;
            break;
          }
          lastError = Exception('Overpass HTTP ${candidate.statusCode}');
        } catch (error) {
          lastError = error;
        }
      }
      if (response == null) throw lastError ?? Exception('places unavailable');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];
      final places = <NearbyPlace>[];
      for (final item in elements) {
        final e = item as Map<String, dynamic>;
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final lat = e['lat'] ?? (e['center'] as Map?)?['lat'];
        final lon = e['lon'] ?? (e['center'] as Map?)?['lon'];
        if (lat is! num || lon is! num) continue;
        final category = (tags['amenity'] ?? tags['shop'] ?? tags['healthcare'] ?? tags['tourism'] ?? tags['leisure'] ?? (tags.containsKey('traffic_calming') ? 'traffic_calming' : null) ?? tags['hazard'] ?? tags['highway'] ?? 'مكان').toString();
        final address = [tags['addr:street'], tags['addr:suburb'], tags['addr:city']].where((v) => v != null && v.toString().isNotEmpty).join('، ');
        final fallbackName = ['construction', 'roadworks'].contains(category)
            ? 'أعمال طريق'
            : category == 'traffic_calming' ? 'مطب تهدئة'
            : category == 'pothole' ? 'حفرة بالطريق'
            : category == 'damaged_road' ? 'طريق متضرر' : 'مكان غير مسمى';
        places.add(NearbyPlace(id: (e['id'] as num).toInt(), name: (tags['name:ar'] ?? tags['name'] ?? tags['brand'] ?? fallbackName).toString(), category: category, point: LatLng(lat.toDouble(), lon.toDouble()), address: address));
      }
      places.sort((a,b) => Geolocator.distanceBetween(center.latitude, center.longitude, a.point.latitude, a.point.longitude).compareTo(Geolocator.distanceBetween(center.latitude, center.longitude, b.point.latitude, b.point.longitude)));
      if (!mounted) return;
      setState(() => _nearbyPlaces = places.take(80).toList());
      await _syncMapAnnotations();
      if (places.isEmpty) {
        _message('ما لقينا أماكن مسجلة ضمن 6 كم حالياً. جرّب التحديث لاحقاً');
      }
      if (showSheet) _showNearbyPlaces();
    } catch (_) {
      _message(_nearbyPlaces.isEmpty
          ? 'تعذّر الاتصال بخدمات الأماكن القريبة. تحقق من الإنترنت وحاول لاحقاً'
          : 'تعذّر تحديث الأماكن؛ أبقينا النتائج السابقة ظاهرة');
    }
    finally { if (mounted) setState(() => _loadingNearby = false); }
  }

  Future<void> _reportNearbyPlace(NearbyPlace place) async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/note/new#map=18/${place.point.latitude}/${place.point.longitude}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _message('تعذّر فتح صفحة الإبلاغ؛ حاول مرة أخرى');
  }

  void _showNearbyPlaces() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.isDark ? const Color(0xFF202A2A) : Colors.white,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          child: StatefulBuilder(
            builder: (context, refreshSheet) {
              final query = _nearbySearchQuery.trim().toLowerCase();
              final visiblePlaces = _nearbyPlaces.where((place) {
                final matchesFavorite = !_showFavoritesOnly || _favoritePlaceIds.contains(place.id);
                final matchesCategory = _matchesNearbyCategory(place);
                final searchable = '${place.name} ${place.category} ${place.address}'.toLowerCase();
                return matchesFavorite && matchesCategory &&
                    (query.isEmpty || searchable.contains(query));
              }).toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('أماكن قريبة منك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textDirection: TextDirection.rtl),
                        ),
                        IconButton(
                          tooltip: 'تحديث الأماكن القريبة',
                          onPressed: _loadingNearby
                              ? null
                              : () async {
                                  await _loadNearbyPlaces(showSheet: false);
                                  if (context.mounted) refreshSheet(() {});
                                },
                          icon: _loadingNearby
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      textDirection: TextDirection.rtl,
                      onChanged: (value) => refreshSheet(() => _nearbySearchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن مطعم أو متجر أو مستشفى...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _nearbySearchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => refreshSheet(() => _nearbySearchQuery = ''),
                                icon: const Icon(Icons.close),
                              ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        isDense: true,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _showFavoritesOnly ? 'الأماكن المفضلة' : 'كل الأماكن القريبة',
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => refreshSheet(() => _showFavoritesOnly = !_showFavoritesOnly),
                          icon: Icon(_showFavoritesOnly ? Icons.store : Icons.star),
                          label: Text(_showFavoritesOnly ? 'عرض الكل' : 'المفضلة'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['الكل', 'مطاعم ومقاهي', 'صحة', 'تسوق', 'خدمات', 'سلامة الطرق']
                          .map((category) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: _nearbyCategoryFilter == category,
                                  onSelected: (_) => refreshSheet(() => _nearbyCategoryFilter = category),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: visiblePlaces.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _nearbyPlaces.isEmpty
                                    ? 'ماكو أماكن مسجلة حول موقعك حالياً. حدّث القائمة بعد قليل.'
                                    : 'ماكو أماكن تطابق البحث والتصنيف. امسح كلمة البحث أو غيّر التصنيف.',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: visiblePlaces.length,
                            itemBuilder: (context, index) {
                              final place = visiblePlaces[index];
                              final here = _userPoint ?? place.point;
                              final km = Geolocator.distanceBetween(
                                    here.latitude, here.longitude,
                                    place.point.latitude, place.point.longitude,
                                  ) / 1000;
                              return ListTile(
                                leading: const Icon(Icons.place, color: Color(0xFFE9A23B)),
                                title: Text(place.name, textDirection: TextDirection.rtl),
                                subtitle: Text(
                                  '${_nearbyCategoryLabel(place.category)} • ${km.toStringAsFixed(1)} كم${place.address.isEmpty ? '' : ' • ${place.address}'}',
                                  textDirection: TextDirection.rtl,
                                ),
                                trailing: Wrap(
                                  spacing: 0,
                                  children: [
                                    IconButton(
                                      tooltip: 'إضافة للمفضلة',
                                      onPressed: () {
                                        _toggleFavoritePlace(place.id);
                                        refreshSheet(() {});
                                      },
                                      icon: Icon(
                                        _favoritePlaceIds.contains(place.id) ? Icons.star : Icons.star_border,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'الإبلاغ عن خطأ أو نقص',
                                      onPressed: () => _reportNearbyPlace(place),
                                      icon: const Icon(Icons.flag_outlined),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedNearby = place;
                                    _toController.text = place.name;
                                  });
                                  Navigator.pop(sheetContext);
                                  _map?.animateCamera(
                                    mlg.CameraUpdate.newCameraPosition(
                                      mlg.CameraPosition(
                                        target: mlg.LatLng(place.point.latitude, place.point.longitude),
                                        zoom: 16,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'المصدر OpenStreetMap؛ قد تكون بعض الأماكن وأعمال الطرق ناقصة أو غير محدثة، وليست بيانات مرور مباشرة. زر الإبلاغ يفتح صفحة OSM لتكتب الملاحظة بنفسك.',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(() => _nearbySearchQuery = '');
  }

  Future<void> _toggle3d() async {
    setState(() => _is3d = !_is3d);
    final map = _map;
    if (map == null) return;
    final camera = await map.queryCameraPosition();
    if (camera == null) return;
    await map.animateCamera(
      mlg.CameraUpdate.newCameraPosition(
        mlg.CameraPosition(
          target: camera.target,
          zoom: camera.zoom,
          bearing: camera.bearing,
          tilt: _is3d ? 55 : 0,
        ),
      ),
      duration: const Duration(milliseconds: 650),
    );
  }

  Future<void> _useMyLocationAsOrigin() async {
    final point = await _currentLocation();
    if (point == null || !mounted) return;
    setState(() => _fromController.text = 'موقعي الحالي');
    await _map?.animateCamera(mlg.CameraUpdate.newCameraPosition(
      mlg.CameraPosition(
        target: mlg.LatLng(point.latitude, point.longitude),
        zoom: 15,
        tilt: _is3d ? 55 : 0,
      ),
    ));
  }

  Future<void> _buildRoute() async {
    if (_loadingRoute) return;
    setState(() => _loadingRoute = true);
    try {
      LatLng? origin;
      if (_selectedMapOrigin != null) {
        origin = _selectedMapOrigin;
      } else if (_fromController.text.trim() == 'موقعي الحالي' ||
          _fromController.text.trim().isEmpty) {
        origin = await _currentLocation();
      } else {
        final matches = _findPlaces(_fromController.text);
        if (matches.isNotEmpty) origin = matches.first.point;
      }

      final destinations = _findPlaces(_toController.text);
      if (origin == null) {
        _message('حدد نقطة انطلاق معروفة أو اختر موقعي الحالي');
        return;
      }
      if (destinations.isEmpty && _selectedNearby == null) {
        _message('اختَر وجهة من الأماكن القريبة أو اكتب اسم مدينة');
        return;
      }
      final destination = _selectedNearby?.point ?? destinations.first.point;
      final recentDestination = _selectedNearby ??
          NearbyPlace(
            id: -1,
            name: destinations.first.name,
            category: 'مدينة',
            point: destination,
            address: destinations.first.governorate,
          );

      // خادم OSRM العام للتجربة فقط؛ لا يضمن الخدمة أو الاستمرارية للإنتاج.
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('route service returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        _message('ما حصلت مسار متاح بين هاتين النقطتين');
        return;
      }
      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final geometry = route['geometry']['coordinates'] as List;
      final points = geometry
          .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
          .toList();
      final steps = <String>[];
      final maneuvers = <RouteManeuver>[];
      for (final leg in route['legs'] as List) {
        for (final step in (leg['steps'] as List)) {
          final maneuver = step['maneuver'] as Map<String, dynamic>;
          final text = _maneuverText(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
            step['name']?.toString() ?? '',
          );
          if (text.isNotEmpty) {
            steps.add(text);
            final location = maneuver['location'] as List?;
            if (location != null && location.length >= 2) {
              maneuvers.add(RouteManeuver(
                point: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
                instruction: text,
              ));
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _routeOrigin = origin;
        _routeDestination = destination;
        _routePoints = points;
        _instructions = steps;
        _routeManeuvers = maneuvers;
        _nextManeuverIndex = maneuvers.length > 1 ? 1 : 0;
        _announcedManeuverStages.clear();
        _nextInstruction =
            steps.isEmpty ? 'اتبع الخط الأزرق على الخريطة' : steps.first;
        _routeDistanceMeters = (route['distance'] as num).toDouble();
        _routeDurationSeconds = (route['duration'] as num).toDouble();
      });
      if (points.isNotEmpty) {
        final centerLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
        final centerLon = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
        final zoom = _routeDistanceMeters > 100000 ? 6.5 : 11.5;
        await _map?.animateCamera(
          mlg.CameraUpdate.newCameraPosition(
            mlg.CameraPosition(
              target: mlg.LatLng(centerLat, centerLon),
              zoom: zoom,
              tilt: _is3d ? 55 : 0,
            ),
          ),
          duration: const Duration(milliseconds: 900),
        );
      }
      await _syncMapAnnotations();
      await _saveRecentDestination(recentDestination);
      await _speak('تم حساب المسار. $_nextInstruction');
    } catch (error) {
      _message('تعذّر حساب الطريق حالياً. تحقق من الإنترنت وحاول مرة ثانية');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  String _formatRouteDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} كم';
    return '${meters.round()} متر';
  }

  String _formatRouteDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes دقيقة تقريباً';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0
        ? '$hours ساعة تقريباً'
        : '$hours ساعة و$remaining دقيقة تقريباً';
  }

  String _maneuverText(String type, String modifier, String road) {
    final roadText = road.isEmpty ? 'الطريق' : 'باتجاه $road';
    if (type == 'arrive') return 'وصلت لوجهتك، عاشت إيدك، وصلت بالسلامة';
    if (type == 'depart') return 'يلا توكّل، واصل $roadText';
    if (modifier.contains('left')) return 'بعد شوية لف يسار، $roadText';
    if (modifier.contains('right')) return 'بعد شوية لف يمين، $roadText';
    if (modifier == 'uturn') return 'استدر وارجع بالاتجاه المعاكس';
    if (type == 'roundabout' || type == 'rotary') {
      return 'ادخل الدوار، $roadText';
    }
    if (type == 'merge') return 'اندَمج مع المسار $roadText';
    if (type == 'fork') return 'خذ التفرع $roadText';
    if (type == 'new name' || type == 'continue') return 'واصل سيده $roadText';
    return roadText;
  }

  Future<void> _startTracking() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await _currentLocation();
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _message('فعّل GPS حتى نتابع حركة السيارة');
      return;
    }
    await _positionSubscription?.cancel();
    setState(() => _tracking = true);
    _startSafetyReminders();
    _announcedRoadAlertIds.clear();
    if (_nearbyPlaces.isEmpty) unawaited(_loadNearbyPlaces(showSheet: false));
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 8,
      ),
    ).listen((position) async {
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _userPoint = point;
        if (position.speed > 1.2 && position.heading.isFinite) {
          _headingDegrees = position.heading;
        }
      });
      unawaited(_announceUpcomingManeuver(point));
      unawaited(_announceNearbyRoadAlerts(point));
      unawaited(_checkRouteDeviation(point));
      unawaited(_syncMapAnnotations());
      final camera = await _map?.queryCameraPosition();
      _map?.moveCamera(mlg.CameraUpdate.newCameraPosition(
        mlg.CameraPosition(
          target: mlg.LatLng(point.latitude, point.longitude),
          zoom: (camera?.zoom ?? 15) < 14 ? 15 : (camera?.zoom ?? 15),
          tilt: _is3d ? 55 : 0,
        ),
      ));
    }, onError: (_) {
      _message('انقطع تتبع الموقع');
      if (mounted) setState(() => _tracking = false);
    });
  }



  Future<void> _announceUpcomingManeuver(LatLng current) async {
    if (!_tracking || _routeManeuvers.isEmpty ||
        _nextManeuverIndex >= _routeManeuvers.length || _speaking) {
      return;
    }
    final index = _nextManeuverIndex;
    final maneuver = _routeManeuvers[index];
    final meters = const Distance().as(LengthUnit.Meter, current, maneuver.point);
    final stages = _announcedManeuverStages.putIfAbsent(index, () => <int>{});

    // تعليمات متدرجة باللهجة العراقية: تنبيه مبكر، ثم اقتراب، ثم انعطاف.
    if (meters <= 500 && meters > 180 && !stages.contains(0)) {
      stages.add(0);
      if (mounted) setState(() => _nextInstruction = maneuver.instruction);
      await _speak('استعد، بعد حوالي 500 متر، ${maneuver.instruction}');
    } else if (meters <= 180 && meters > 45 && !stages.contains(1)) {
      stages.add(1);
      if (mounted) setState(() => _nextInstruction = maneuver.instruction);
      await _speak('باقي حوالي 150 متر، ${maneuver.instruction}');
    } else if (meters <= 45 && !stages.contains(2)) {
      stages.add(2);
      if (mounted) setState(() => _nextInstruction = maneuver.instruction);
      await _speak('هسه، ${maneuver.instruction}');
    }

    if (meters <= 25 && stages.contains(2)) {
      _nextManeuverIndex++;
      if (_nextManeuverIndex < _routeManeuvers.length && mounted) {
        setState(() => _nextInstruction =
            _routeManeuvers[_nextManeuverIndex].instruction);
      } else if (mounted) {
        setState(() => _nextInstruction = 'وصلت إلى وجهتك');
      }
    }
  }

  Future<void> _checkRouteDeviation(LatLng current) async {
    final destination = _routeDestination;
    if (!_tracking || destination == null || _routePoints.length < 2 || _rerouting) {
      return;
    }

    // Sample the route to keep GPS updates lightweight on mobile devices.
    var nearestDistance = double.infinity;
    for (var i = 0; i < _routePoints.length; i += 5) {
      final meters = const Distance().as(
        LengthUnit.Meter,
        current,
        _routePoints[i],
      );
      if (meters < nearestDistance) nearestDistance = meters;
    }
    final last = _routePoints.last;
    final lastDistance = const Distance().as(LengthUnit.Meter, current, last);
    if (lastDistance < nearestDistance) nearestDistance = lastDistance;

    // Ignore small GPS drift and avoid repeated requests on poor connections.
    if (nearestDistance < 85) return;
    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < const Duration(seconds: 30)) {
      return;
    }

    _lastRerouteAt = now;
    _rerouting = true;
    await _speak('ابتعدت عن المسار المحدد، أحاول أحسب لك طريق جديد');
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${current.longitude},${current.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (data['code'] != 'Ok' || routes == null || routes.isEmpty) return;

      final route = routes.first as Map<String, dynamic>;
      final coordinates = route['geometry']['coordinates'] as List;
      final updatedPoints = coordinates
          .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
          .toList();
      final updatedInstructions = <String>[];
      final updatedManeuvers = <RouteManeuver>[];
      for (final leg in route['legs'] as List) {
        for (final step in (leg['steps'] as List)) {
          final maneuver = step['maneuver'] as Map<String, dynamic>;
          final instruction = _maneuverText(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
            step['name']?.toString() ?? '',
          );
          if (instruction.isNotEmpty) {
            updatedInstructions.add(instruction);
            final location = maneuver['location'] as List?;
            if (location != null && location.length >= 2) {
              updatedManeuvers.add(RouteManeuver(
                point: LatLng((location[1] as num).toDouble(), (location[0] as num).toDouble()),
                instruction: instruction,
              ));
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _routeOrigin = current;
        _routePoints = updatedPoints;
        _instructions = updatedInstructions;
        _routeManeuvers = updatedManeuvers;
        _nextManeuverIndex = updatedManeuvers.length > 1 ? 1 : 0;
        _announcedManeuverStages.clear();
        _nextInstruction = updatedInstructions.isEmpty
            ? 'اتبع المسار الجديد على الخريطة'
            : updatedInstructions.first;
        _routeDistanceMeters = (route['distance'] as num).toDouble();
        _routeDurationSeconds = (route['duration'] as num).toDouble();
      });
      await _syncMapAnnotations();
      await _speak('تم تحديث المسار بعد تغيير موقعك. $_nextInstruction');
    } catch (_) {
      // Keep the current route if the public routing service is unavailable.
    } finally {
      _rerouting = false;
    }
  }

  Future<void> _announceNearbyRoadAlerts(LatLng current) async {
    if (!_tracking || _speaking) return;
    for (final place in _nearbyPlaces) {
      if (!['construction', 'roadworks', 'traffic_calming', 'pothole', 'damaged_road'].contains(place.category) ||
          _announcedRoadAlertIds.contains(place.id)) {
        continue;
      }
      final meters = Geolocator.distanceBetween(
        current.latitude, current.longitude,
        place.point.latitude, place.point.longitude,
      );
      if (meters <= 350) {
        _announcedRoadAlertIds.add(place.id);
        final message = place.category == 'traffic_calming'
            ? 'انتبه، قدامك مطب تهدئة قريب.'
            : place.category == 'pothole'
                ? 'انتبه، قدامك بلاغ عن حفرة بالطريق.'
                : place.category == 'damaged_road'
                    ? 'تنبيه، أكو بلاغ عن طريق متضرر قدامك.'
                    : 'تنبيه طريق: قدامك أعمال طريق، خفف السرعة وانتبه.';
        await _speak(message);
        break;
      }
    }
  }

  void _startSafetyReminders() {
    _safetyReminderTimer?.cancel();
    _safetyReminderIndex = 0;
    const reminders = <String>[
      'أمانة، انتبه لطريقك وخلي عينك على الشارع.',
      'البس حزام الأمان، ولا تلزم الموبايل وإنت تسوق.',
      'حافظ على نفسك وعلى اللي وياك، وخلي مسافة أمان بينك وبين السيارة الجدامك.',
      'تره السرعة ما تفيد، خفف وخلّيك مرتاح.',
      'إذا تعبت، وقف بمكان آمن وخذلك استراحة، سلامتك أهم.',
      'هسه انتبه للطريق، وبعدك شوية وتوصل بالسلامة.',
    ];
    _safetyReminderTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (!_tracking || _speaking || !mounted) return;
      final reminder = reminders[_safetyReminderIndex % reminders.length];
      _safetyReminderIndex++;
      unawaited(_speak(reminder));
    });
  }

  Future<void> _stopTracking() async {
    _safetyReminderTimer?.cancel();
    _safetyReminderTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (mounted) setState(() => _tracking = false);
  }

  Future<void> _speak(String text) async {
    if (_speaking) return;
    _speaking = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      try {
        await _tts.setLanguage('ar-IQ');
      } catch (_) {
        await _tts.setLanguage('ar');
      }
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.44);
      await _tts.setPitch(1.02);
      await _tts.speak(text);
    } catch (_) {
      _message('الصوت العربي غير متوفر في إعدادات الجهاز');
    } finally {
      _speaking = false;
    }
  }

  Future<void> _askByVoice() async {
    if (_listening || _voiceConversation) {
      _voiceConversation = false;
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _voiceConversation = true;
    await _listenForVoiceTurn();
  }

  Future<void> _listenForVoiceTurn() async {
    if (!_voiceConversation || !mounted) return;

    // لا نعيد تهيئة خدمة التعرف بكل جولة؛ نوقف الجلسة السابقة فقط.
    await _tts.stop();
    await _speech.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_voiceConversation || !mounted) return;

    if (!_speechInitialized) {
      try {
        _speechInitialized = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            if (status == 'notListening' || status == 'done') {
              setState(() => _listening = false);
              // إذا انتهت مهلة الاستماع بلا نتيجة نهائية، لا نترك المحادثة معلّقة.
              if (_voiceConversation && !_voiceTurnHandled) {
                _voiceTurnHandled = true;
                unawaited(_completeVoiceTurn(_voiceText));
              }
            }
          },
          onError: (_) {
            _voiceConversation = false;
            if (mounted) setState(() => _listening = false);
            _message('ما كدرت أسمعك. تأكد من إذن المايك وخدمة التعرّف على الكلام واللغة العربية بالجهاز');
          },
        );
      } catch (_) {
        _speechInitialized = false;
      }
    }

    if (!_speechInitialized) {
      _voiceConversation = false;
      if (mounted) setState(() => _listening = false);
      _message('خدمة الاستماع مو متاحة. فعّل المايك وثبّت خدمة التعرّف على الكلام من إعدادات الجهاز');
      return;
    }

    if (!mounted || !_voiceConversation) return;
    setState(() {
      _listening = true;
      _voiceText = '';
    });
    _voiceTurnHandled = false;

    try {
      final availableLocales = await _speech.locales();
      final arabicLocales = availableLocales
          .where((locale) => locale.localeId.toLowerCase().startsWith('ar'))
          .toList();
      final iraqiLocale = arabicLocales.where(
        (locale) => locale.localeId.toLowerCase().replaceAll('-', '_') == 'ar_iq',
      );
      final selectedLocale = iraqiLocale.isNotEmpty
          ? iraqiLocale.first.localeId
          : (arabicLocales.isNotEmpty ? arabicLocales.first.localeId : null);

      await _speech.listen(
        localeId: selectedLocale,
        listenFor: const Duration(seconds: 25),
        pauseFor: const Duration(seconds: 5),
        onResult: (result) {
          if (!mounted) return;
          setState(() => _voiceText = result.recognizedWords);
          if (result.finalResult && !_voiceTurnHandled) {
            _voiceTurnHandled = true;
            setState(() => _listening = false);
            unawaited(_completeVoiceTurn(result.recognizedWords));
          }
        },
      );
    } catch (_) {
      _voiceConversation = false;
      if (mounted) setState(() => _listening = false);
      _message('صار خلل بفتح المايك. تأكد ماكو تطبيق ثاني يستخدمه وجرب مرة ثانية');
    }
  }

  Future<void> _completeVoiceTurn(String question) async {
    await _speech.stop();
    if (question.trim().isEmpty) {
      await _speak('ما وصلني كلام واضح، احچي مرة ثانية وبصوت واضح.');
    } else {
      await _answerRouteQuestion(question);
    }
    if (!_voiceConversation || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_voiceConversation && mounted) {
      await _listenForVoiceTurn();
    }
  }

  Future<void> _answerRouteQuestion(String question) async {
    final q = question.toLowerCase();

    // فهم أمر وجهة منطوق باللهجة العراقية، مثل: "وديني لكربلاء"
    // أو "من العمارة لبغداد". يعتمد على المدن المدعومة محلياً.
    final mentionedPlaces = iraqPlaces
        .where((place) => q.contains(place.name.toLowerCase()))
        .toList()
      ..sort((a, b) => q.indexOf(a.name).compareTo(q.indexOf(b.name)));
    final hasNavigationIntent = q.contains('وديني') ||
        q.contains('دليني') ||
        q.contains('أريد أروح') ||
        q.contains('اريد اروح') ||
        q.contains('طريق') ||
        q.contains('إلى') ||
        q.contains('الى') ||
        q.contains('روح');
    if (mentionedPlaces.length >= 2) {
      _fromController.text = mentionedPlaces.first.name;
      _toController.text = mentionedPlaces[1].name;
      await _speak('تمام، أبحث لك عن الطريق من ${mentionedPlaces.first.name} إلى ${mentionedPlaces[1].name}');
      await _buildRoute();
      return;
    }
    if (mentionedPlaces.length == 1 && hasNavigationIntent) {
      _toController.text = mentionedPlaces.first.name;
      await _speak('تمام، أبحث لك عن الطريق إلى ${mentionedPlaces.first.name}');
      await _buildRoute();
      return;
    }

    final answer = await _askConversationalAssistant(
      question,
      routeContext: _routePoints.isEmpty
          ? 'لا يوجد مسار نشط حالياً.'
          : 'المسافة: ${_formatRouteDistance(_routeDistanceMeters)}، الوقت التقديري: ${_formatRouteDuration(_routeDurationSeconds)}، التوجيه القادم: $_nextInstruction',
    );
    await _speak(answer);
  }

  Future<String> _askConversationalAssistant(
    String question, {
    required String routeContext,
  }) async {
    // مساعد محلي مجاني: لا يرسل كلام المستخدم أو موقعه إلى أي خادم.
    // يعتمد على قواعد وكلمات مفتاحية، وليس نموذج ذكاء اصطناعي توليدي.
    final q = question.trim().toLowerCase();

    if (q.isEmpty) return 'ما وصلني سؤالك، احچيلي شتريد تعرف.';
    if (q.contains('مرحبا') || q.contains('هلا') || q.contains('السلام عليكم') ||
        q.contains('شلونك') || q.contains('شخبارك')) {
      return 'هلا بيك، آني دلّيني. حاضر أساعدك بالطريق وبمعلومات التطبيق.';
    }
    if (q.contains('شكرا') || q.contains('مشكور') || q.contains('تسلم')) {
      return 'تدلّل، بالخدمة. الله يحفظك بطريقك.';
    }
    if (q.contains('اسمك') || q.contains('منو انت') || q.contains('شنو انت')) {
      return 'آني دلّيني، مساعدك داخل تطبيق الملاحة. أگدر أساعدك بالتوجيه وبعض الأسئلة الشائعة.';
    }
    if (q.contains('المسار') || q.contains('الطريق') || q.contains('وين وصلنا')) {
      if (_routePoints.isEmpty) {
        return 'ماكو مسار محسوب هسه. حدّد نقطة الانطلاق والوجهة واضغط اعرض الطريق.';
      }
      return 'المسار الحالي: ${routeContext}';
    }
    if (q.contains('كم باقي') || q.contains('شكد باقي') ||
        q.contains('المسافة') || q.contains('كم كيلو') || q.contains('بعيد')) {
      if (_routePoints.isEmpty) return 'بعد ما حسبنا الطريق. حدّد وجهتك أولاً.';
      return 'المسافة المحسوبة ${_formatRouteDistance(_routeDistanceMeters)}، والوقت التقديري ${_formatRouteDuration(_routeDurationSeconds)}.';
    }
    if (q.contains('انعطف') || q.contains('التوجيه القادم') ||
        q.contains('شنو أسوي') || q.contains('وين أروح')) {
      return _routePoints.isEmpty
          ? 'حدد وجهتك أولاً حتى أعطيك تعليمات الطريق.'
          : _nextInstruction;
    }
    if (q.contains('زحمة') || q.contains('ازدحام') || q.contains('مرور')) {
      return 'ما عندي حالياً بيانات حركة مرور مباشرة، لذلك ما أگدر أأكد وجود زحام. اتبع اللوحات وخفف السرعة.';
    }
    if (q.contains('سيطرة') || q.contains('تفتيش') || q.contains('نقطة تفتيش')) {
      return 'ما عندي بيانات مؤكدة ومباشرة عن السيطرات. انتبه للطريق واتبع تعليمات الجهات المختصة.';
    }
    if (q.contains('طقس') || q.contains('جو') || q.contains('مطر')) {
      return 'ما متصل حالياً بخدمة طقس مباشرة. افحص حالة الجو من مصدر موثوق قبل السفر.';
    }
    if (q.contains('حزام') || q.contains('سلامة') || q.contains('أمان')) {
      return 'سلامتك أولاً: اربط حزام الأمان، وخلي مسافة آمنة، ولا تستخدم الموبايل أثناء القيادة.';
    }
    if (q.contains('حادث') || q.contains('طوارئ') || q.contains('إسعاف')) {
      return 'إذا أكو حالة طارئة، وقف بمكان آمن إذا تگدر واتصل بخدمات الطوارئ المحلية. لا تستخدم الهاتف أثناء قيادة المركبة.';
    }
    if (q.contains('شلون أستخدم') || q.contains('طريقة الاستخدام') ||
        q.contains('ساعدني')) {
      return 'اكتب أو قل اسم الوجهة، حدّد الانطلاق إذا تحتاج، وبعدها اضغط اعرض الطريق. وللمحادثة اضغط احچي ويا دلّيني.';
    }
    return 'أگدر أساعدك بالمسار والمسافة والتوجيه القادم وتنبيهات السلامة. أما الأسئلة العامة المفتوحة فما عندي حالياً نموذج ذكاء اصطناعي متصل بيها، لأن هذا الوضع يعمل محلياً ومجاناً.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF172321);
    final panelColor = isDark ? const Color(0xFF202A2A) : Colors.white;


    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.showMap)
              Positioned.fill(
                child: mlg.MapLibreMap(
                  key: ValueKey('map-palette-$_mapPaletteIndex'),
                  initialCameraPosition: mlg.CameraPosition(
                    target: const mlg.LatLng(33.1, 43.8),
                    zoom: 4.8,
                    tilt: _is3d ? 55 : 0,
                  ),
                  styleString: _mapStyleUrl,
                  compassEnabled: true,
                  logoEnabled: false,
                  trackCameraPosition: true,
                  onMapCreated: (controller) => _map = controller,
                  onMapLongClick: (screenPoint, coordinates) =>
                      _selectMapDestination(coordinates),
                  onStyleLoadedCallback: () {
                    _mapStyleLoaded = true;
                    unawaited(_addGovernorateBoundaries());
                    unawaited(_syncMapAnnotations());
                  },
                ),
              )
            else
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFE7ECEB)),
              ),
            if (_tracking && _userPoint != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Transform.rotate(
                      angle: _headingDegrees * math.pi / 180,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF087E70), width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
                          ],
                        ),
                        child: const Icon(
                          Icons.navigation,
                          size: 34,
                          color: Color(0xFF087E70),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 12,
              child: Card(
                color: panelColor,
                elevation: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 12),
                      child: Text('دِلِّينِي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                      onPressed: widget.onToggleTheme,
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                    ),
                    IconButton(
                      tooltip: 'تغيير ألوان الخريطة: ${_mapPaletteNames[_mapPaletteIndex]}',
                      onPressed: _cycleMapPalette,
                      icon: const Icon(Icons.palette_outlined),
                    ),
                    IconButton(
                      tooltip: _is3d ? 'إيقاف العرض الثلاثي' : 'عرض ثلاثي الأبعاد',
                      onPressed: _toggle3d,
                      icon: Icon(_is3d ? Icons.view_in_ar : Icons.view_in_ar_outlined),
                    ),
                    IconButton(
                      tooltip: 'الأماكن القريبة',
                      onPressed: _loadingNearby ? null : _loadNearbyPlaces,
                      icon: _loadingNearby ? const SizedBox(width: 20,height: 20,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.store_mall_directory_outlined),
                    ),
                    IconButton(
                      tooltip: 'موقعي الحالي',
                      onPressed: _useMyLocationAsOrigin,
                      icon: const Icon(Icons.my_location),
                    ),
                    IconButton(
                      tooltip: 'إدارة الخرائط بدون إنترنت',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OfflineMapsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.download_for_offline_outlined),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Card(
                color: panelColor,
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_routePoints.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF173B35) : const Color(0xFFEAF5F2),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_formatRouteDistance(_routeDistanceMeters)} • ${_formatRouteDuration(_routeDurationSeconds)}',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'استمع للتوجيه',
                                    onPressed: () => _speak(_nextInstruction),
                                    icon: const Icon(Icons.volume_up, size: 18),
                                  ),
                                  const SizedBox(width: 4),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      minimumSize: const Size(0, 26),
                                      padding: const EdgeInsets.symmetric(horizontal: 9),
                                    ),
                                    onPressed: _tracking ? _stopTracking : _startTracking,
                                    child: Text(_tracking ? 'إيقاف التتبع' : 'ابدأ التتبع', style: const TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                              Text(
                                _nextInstruction,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(color: textColor, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _fromController,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 13),
                              onChanged: (_) => setState(() => _selectedMapOrigin = null),
                              decoration: InputDecoration(
                                hintText: 'من',
                                prefixIcon: const Icon(Icons.trip_origin, color: Color(0xFF08AFA0), size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF172321) : const Color(0xFFF1F7F7),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: TextField(
                              controller: _toController,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 13),
                              onChanged: (_) => setState(() => _selectedNearby = null),
                              decoration: InputDecoration(
                                hintText: 'إلى',
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF08AFA0), size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF172321) : const Color(0xFFF1F7F7),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'استخدم موقعي كنقطة انطلاق',
                            visualDensity: VisualDensity.compact,
                            onPressed: _useMyLocationAsOrigin,
                            icon: const Icon(Icons.my_location, size: 20),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
                            minimumSize: const Size(0, 26),
                          ),
                          onPressed: () => setState(() =>
                              _showAdvancedSearchOptions = !_showAdvancedSearchOptions),
                          icon: Icon(
                            _showAdvancedSearchOptions
                                ? Icons.expand_less
                                : Icons.tune,
                            size: 17,
                          ),
                          label: Text(
                            _showAdvancedSearchOptions
                                ? 'إخفاء الخيارات'
                                : 'خيارات إضافية وتحديد الانطلاق',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      if (_showAdvancedSearchOptions) ...[
                      if (_selectedMapOrigin != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3, right: 6),
                            child: Text(
                              'انطلاق من الخريطة • ${_selectedMapOrigin!.latitude.toStringAsFixed(5)}, ${_selectedMapOrigin!.longitude.toStringAsFixed(5)}',
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: const Size(0, 30),
                          ),
                          onPressed: () => setState(() =>
                              _selectingOriginFromMap = !_selectingOriginFromMap),
                          icon: Icon(_selectingOriginFromMap
                              ? Icons.touch_app
                              : Icons.trip_origin),
                          label: Text(
                            _selectingOriginFromMap
                                ? 'اضغط مطولاً على الخريطة لتحديد الانطلاق...'
                                : 'تحديد نقطة الانطلاق من الخريطة',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_selectedNearby != null &&
                          _selectedNearby!.category == 'وجهة محددة')
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Text(
                              'وجهة الخريطة • ${_selectedNearby!.point.latitude.toStringAsFixed(5)}, ${_selectedNearby!.point.longitude.toStringAsFixed(5)}',
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      if (_recentDestinations.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'الوجهات الأخيرة',
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _clearRecentDestinations,
                                    child: const Text('مسح السجل'),
                                  ),
                                ],
                              ),
                              SizedBox(
                                height: 28,
                                child: ListView(
                                  reverse: true,
                                  scrollDirection: Axis.horizontal,
                                  children: _recentDestinations.map((place) =>
                                    Padding(
                                      padding: const EdgeInsetsDirectional.only(start: 4),
                                      child: ActionChip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(Icons.history, size: 16),
                                        label: Text(place.name),
                                        onPressed: () {
                                          setState(() {
                                            _selectedNearby = place;
                                            _toController.text = place.name;
                                          });
                                        },
                                      ),
                                    ),
                                  ).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_toController.text.isNotEmpty && _findPlaces(_toController.text).isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 5, right: 8),
                            child: Text(
                              'الوجهة: ${_findPlaces(_toController.text).first.name} — ${_findPlaces(_toController.text).first.governorate}',
                              style: Theme.of(context).textTheme.bodySmall,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loadingRoute ? null : _buildRoute,
                              icon: _loadingRoute
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.alt_route),
                              label: const Text('اعرض الطريق'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _askByVoice,
                              icon: Icon(_voiceConversation ? Icons.call_end : Icons.mic_none),
                              label: Text(_listening ? 'دا أسمعك...' : (_voiceConversation ? 'إنهاء المحادثة' : 'احچي ويا دلّيني')),
                            ),
                          ),
                        ],
                      ),
                      if (_voiceText.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('سمعتك: $_voiceText', textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

}
}

class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  String _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  static const _governorates = <_Governorate>[
    _Governorate('بغداد', 44.12523, 44.59857, 33.23018, 33.49524),
    _Governorate('البصرة', 46.57106, 48.60723, 29.06360, 31.30036),
    _Governorate('نينوى', 41.21511, 44.30256, 34.92292, 37.07043),
    _Governorate('أربيل', 43.30990, 45.07183, 35.44852, 37.28441),
    _Governorate('النجف', 42.93575, 44.77969, 29.85008, 32.35879),
    _Governorate('كربلاء', 43.27373, 44.25045, 32.18089, 32.79774),
    _Governorate('ميسان', 46.31622, 47.86416, 31.13834, 32.91670),
    _Governorate('ذي قار', 45.63559, 47.13804, 30.51138, 32.01488),
    _Governorate('واسط', 44.49278, 46.58316, 31.99315, 33.53880),
    _Governorate('بابل', 43.90735, 45.15795, 32.13206, 33.29317),
    _Governorate('القادسية', 44.44309, 45.78382, 31.28803, 32.45588),
    _Governorate('المثنى', 43.81358, 46.74635, 28.99913, 31.77439),
    _Governorate('صلاح الدين', 42.41973, 44.93676, 33.43331, 35.73833),
    _Governorate('ديالى', 44.30044, 46.01932, 33.05781, 35.17480),
    _Governorate('الأنبار', 38.79491, 44.26047, 30.51055, 35.13620),
    _Governorate('كركوك', 43.22495, 44.82647, 34.74383, 35.90765),
    _Governorate('دهوك', 42.36994, 44.09227, 36.67493, 37.33356),
    _Governorate('السليمانية', 44.49007, 46.34084, 34.63386, 36.53472),
  ];

  ml.OfflineManager? _manager;
  final Map<String, double> _progress = {};
  final Map<String, int> _regionIds = {};
  final Set<String> _downloading = {};
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initOfflineManager();
  }

  Future<void> _initOfflineManager() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const paletteIds = ['green', 'blue', 'gold', 'gray', 'pink'];
      final savedPalette = (prefs.getInt('map_palette_index') ?? 0)
          .clamp(0, paletteIds.length - 1)
          .toInt();
      _styleUrl = 'https://raw.githubusercontent.com/akaml7143-source/Delleeni/feature/iraq-3d-map/assets/map_styles/${paletteIds[savedPalette]}.json';
      final manager = await ml.OfflineManager.createInstance();
      final regions = await manager.listOfflineRegions();
      if (!mounted) {
        manager.dispose();
        return;
      }
      _manager = manager;
      for (final region in regions) {
        final name = region.metadata['governorate'] as String?;
        if (name != null && _governorates.any((g) => g.name == name)) {
          _regionIds[name] = region.id;
          final status = await manager.getRegionStatus(regionId: region.id);
          if (status.complete) _progress[name] = 1;
          else if (status.progress != null) _progress[name] = status.progress!;
        }
      }
      setState(() => _initializing = false);
    } catch (error) {
      if (mounted) setState(() {
        _error = 'تعذّر تهيئة تنزيل الخرائط: $error';
        _initializing = false;
      });
    }
  }

  Future<void> _download(_Governorate governorate) async {
    final manager = _manager;
    if (manager == null || _downloading.contains(governorate.name)) return;
    setState(() {
      _downloading.add(governorate.name);
      _progress[governorate.name] = 0;
      _error = null;
    });
    try {
      final stream = manager.downloadRegion(
        definition: ml.OfflineTilePyramidRegionDefinition(
          bounds: ml.GeoBox(
            west: governorate.west,
            east: governorate.east,
            south: governorate.south,
            north: governorate.north,
          ),
          styleUrl: _styleUrl,
          minZoom: 5,
          maxZoom: 10,
          pixelRatio: 1,
        ),
        metadata: {'governorate': governorate.name},
      );
      await for (final update in stream) {
        if (!mounted) return;
        setState(() {
          _progress[governorate.name] = update.progress ?? 0;
          if (update.downloadCompleted) {
            _regionIds[governorate.name] = update.region.id;
            _progress[governorate.name] = 1;
          }
        });
      }
      if (mounted && _progress[governorate.name] == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('اكتمل تنزيل خريطة ${governorate.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذّر تنزيل ${governorate.name}: $error');
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(governorate.name));
    }
  }

  Future<void> _delete(_Governorate governorate) async {
    final manager = _manager;
    final id = _regionIds[governorate.name];
    if (manager == null || id == null) return;
    try {
      await manager.deleteRegion(regionId: id);
      if (!mounted) return;
      setState(() {
        _regionIds.remove(governorate.name);
        _progress.remove(governorate.name);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف خريطة ${governorate.name}')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذّر حذف الخريطة: $error');
    }
  }

  String _sizeLabel(double? progress) {
    if (progress == null) return 'الحجم يتحدد أثناء التنزيل';
    return '${(progress * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الخرائط بدون إنترنت'),
        centerTitle: true,
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'نزّل خريطة كل محافظة مرة واحدة لاستخدام بياناتها المخزنة عند انقطاع الإنترنت. '
                    'التنزيل الأول يحتاج اتصالاً مستقراً.',
                    textDirection: TextDirection.rtl,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 10),
                ..._governorates.map((governorate) {
                  final progress = _progress[governorate.name];
                  final downloaded = _regionIds.containsKey(governorate.name) && progress == 1;
                  final downloading = _downloading.contains(governorate.name);
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              child: Icon(downloaded ? Icons.offline_pin : Icons.location_city_outlined),
                            ),
                            title: Text(governorate.name, textDirection: TextDirection.rtl),
                            subtitle: Text(downloaded ? 'متاحة دون إنترنت' : downloading ? 'جارٍ التنزيل • ${_sizeLabel(progress)}' : 'غير محمّلة'),
                            trailing: downloaded
                                ? IconButton(
                                    tooltip: 'حذف الخريطة',
                                    onPressed: () => _delete(governorate),
                                    icon: const Icon(Icons.delete_outline),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: downloading ? null : () => _download(governorate),
                                    icon: downloading
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.download, size: 18),
                                    label: Text(downloading ? 'تنزيل...' : 'تنزيل'),
                                  ),
                          ),
                          if (downloading)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: LinearProgressIndicator(value: progress),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                const Text(
                  'التنزيل الحالي يحفظ طبقات الخريطة ضمن مستويات تقريبية 5–10. '
                  'بيانات الطرق والمسارات الصوتية دون إنترنت تحتاج محرك توجيه وبيانات طرق محلية منفصلة.',
                  style: TextStyle(fontSize: 12),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }
}

class _Governorate {
  const _Governorate(this.name, this.west, this.east, this.south, this.north);
  final String name;
  final double west;
  final double east;
  final double south;
  final double north;
}
