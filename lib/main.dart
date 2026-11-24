import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml hide Position;
import 'package:maplibre_gl/maplibre_gl.dart' as mlg;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  bool _is3d = false;
  final TextEditingController _fromController =
      TextEditingController(text: 'موقعي الحالي');
  final TextEditingController _toController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  LatLng? _userPoint;
  LatLng? _routeOrigin;
  LatLng? _routeDestination;
  List<LatLng> _routePoints = [];
  List<String> _instructions = [];
  String _nextInstruction = 'حدد نقطة الانطلاق والوجهة';
  String _voiceText = '';
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;
  bool _loadingRoute = false;
  bool _tracking = false;
  bool _listening = false;
  bool _speaking = false;
  StreamSubscription<Position>? _positionSubscription;
  DateTime? _lastRerouteAt;
  bool _rerouting = false;
  bool _loadingNearby = false;
  List<NearbyPlace> _nearbyPlaces = [];
  NearbyPlace? _selectedNearby;

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
      if (_routeOrigin != null && _userPoint == null) {
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
        await map.addCircle(mlg.CircleOptions(geometry: mlg.LatLng(place.point.latitude, place.point.longitude), circleColor: '#E9A23B', circleRadius: 5, circleStrokeColor: '#FFFFFF', circleStrokeWidth: 1.5));
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

  Future<void> _loadNearbyPlaces() async {
    if (_loadingNearby) return;
    final center = _userPoint ?? await _currentLocation();
    if (center == null) return;
    setState(() => _loadingNearby = true);
    try {
      const radius = 4000;
      final query = '[out:json][timeout:25];('
          'nwr(around:$radius,\${center.latitude},\${center.longitude})["name"]["amenity"~"restaurant|cafe|fast_food|hospital|clinic|pharmacy|fuel|bank|atm|school|police"];'
          'nwr(around:$radius,\${center.latitude},\${center.longitude})["name"]["shop"];'
          'nwr(around:$radius,\${center.latitude},\${center.longitude})["name"]["healthcare"];'
          ');out center 80;';
      final response = await http.post(Uri.parse('https://overpass-api.de/api/interpreter'), body: {'data': query}).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) throw Exception('places unavailable');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];
      final places = <NearbyPlace>[];
      for (final item in elements) {
        final e = item as Map<String, dynamic>;
        final tags = e['tags'] as Map<String, dynamic>? ?? {};
        final lat = e['lat'] ?? (e['center'] as Map?)?['lat'];
        final lon = e['lon'] ?? (e['center'] as Map?)?['lon'];
        if (lat is! num || lon is! num) continue;
        final category = (tags['amenity'] ?? tags['shop'] ?? tags['healthcare'] ?? 'مكان').toString();
        final address = [tags['addr:street'], tags['addr:suburb'], tags['addr:city']].where((v) => v != null && v.toString().isNotEmpty).join('، ');
        places.add(NearbyPlace(id: (e['id'] as num).toInt(), name: (tags['name:ar'] ?? tags['name'] ?? tags['brand'] ?? 'مكان غير مسمى').toString(), category: category, point: LatLng(lat.toDouble(), lon.toDouble()), address: address));
      }
      places.sort((a,b) => Geolocator.distanceBetween(center.latitude, center.longitude, a.point.latitude, a.point.longitude).compareTo(Geolocator.distanceBetween(center.latitude, center.longitude, b.point.latitude, b.point.longitude)));
      if (!mounted) return;
      setState(() => _nearbyPlaces = places.take(80).toList());
      await _syncMapAnnotations();
      _showNearbyPlaces();
    } catch (_) { _message('تعذّر تحميل الأماكن القريبة. تحقق من الإنترنت وحاول لاحقاً'); }
    finally { if (mounted) setState(() => _loadingNearby = false); }
  }

  void _showNearbyPlaces() {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: widget.isDark ? const Color(0xFF202A2A) : Colors.white, builder: (sheetContext) => SafeArea(child: SizedBox(height: MediaQuery.of(sheetContext).size.height * 0.65, child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('أماكن قريبة منك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      Expanded(child: _nearbyPlaces.isEmpty ? const Center(child: Text('ماكو أماكن مسجلة ضمن المنطقة')) : ListView.builder(itemCount: _nearbyPlaces.length, itemBuilder: (context,index) {
        final place = _nearbyPlaces[index]; final here = _userPoint ?? place.point;
        final km = Geolocator.distanceBetween(here.latitude,here.longitude,place.point.latitude,place.point.longitude)/1000;
        return ListTile(leading: const Icon(Icons.place,color: Color(0xFFE9A23B)),title: Text(place.name,textDirection: TextDirection.rtl),subtitle: Text('\${place.category} • \${km.toStringAsFixed(1)} كم\${place.address.isEmpty ? '' : ' • \${place.address}'}',textDirection: TextDirection.rtl),trailing: const Icon(Icons.directions),onTap: () { setState(() { _selectedNearby=place; _toController.text=place.name; }); Navigator.pop(sheetContext); _map?.animateCamera(mlg.CameraUpdate.newCameraPosition(mlg.CameraPosition(target: mlg.LatLng(place.point.latitude,place.point.longitude),zoom:16))); });
      })),
      const Padding(padding: EdgeInsets.all(12),child: Text('المصدر OpenStreetMap؛ قد تكون بعض الأماكن ناقصة أو غير محدثة.',textDirection: TextDirection.rtl)),
    ])))));
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
      if (_fromController.text.trim() == 'موقعي الحالي' ||
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
      for (final leg in route['legs'] as List) {
        for (final step in (leg['steps'] as List)) {
          final maneuver = step['maneuver'] as Map<String, dynamic>;
          final text = _maneuverText(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
            step['name']?.toString() ?? '',
          );
          if (text.isNotEmpty) steps.add(text);
        }
      }
      if (!mounted) return;
      setState(() {
        _routeOrigin = origin;
        _routeDestination = destination;
        _routePoints = points;
        _instructions = steps;
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
      await _speak('تم حساب المسار. $_nextInstruction');
    } catch (error) {
      _message('تعذّر حساب الطريق حالياً. تحقق من الإنترنت وحاول مرة ثانية');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  String _maneuverText(String type, String modifier, String road) {
    final roadText = road.isEmpty ? 'الطريق' : 'باتجاه $road';
    if (type == 'arrive') return 'وصلت إلى وجهتك';
    if (type == 'depart') return 'يلا انطلق $roadText';
    if (modifier.contains('left')) return 'بعد شوية خذ يسار $roadText';
    if (modifier.contains('right')) return 'بعد شوية خذ يمين $roadText';
    if (modifier == 'uturn') return 'استدر وارجع بالاتجاه المعاكس';
    if (type == 'roundabout' || type == 'rotary') {
      return 'ادخل الدوار، $roadText';
    }
    if (type == 'merge') return 'اندَمج مع المسار $roadText';
    if (type == 'fork') return 'خذ التفرع $roadText';
    if (type == 'new name' || type == 'continue') return 'كمّل دغري $roadText';
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
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 8,
      ),
    ).listen((position) async {
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userPoint = point);
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
      for (final leg in route['legs'] as List) {
        for (final step in (leg['steps'] as List)) {
          final maneuver = step['maneuver'] as Map<String, dynamic>;
          final instruction = _maneuverText(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
            step['name']?.toString() ?? '',
          );
          if (instruction.isNotEmpty) updatedInstructions.add(instruction);
        }
      }
      if (!mounted) return;
      setState(() {
        _routeOrigin = current;
        _routePoints = updatedPoints;
        _instructions = updatedInstructions;
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

  Future<void> _stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (mounted) setState(() => _tracking = false);
  }

  Future<void> _speak(String text) async {
    try {
      try { await _tts.setLanguage('ar-IQ'); } catch (_) { await _tts.setLanguage('ar'); }
      await _tts.setSpeechRate(0.43);
      await _tts.setPitch(1.02);
      await _tts.speak(text);
    } catch (_) {
      _message('الصوت العربي غير متوفر في إعدادات الجهاز');
    }
  }

  Future<void> _askByVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
        _message('ما كدرت أسمع الصوت. تأكد من إذن المايكروفون');
      },
    );
    if (!available) {
      _message('خدمة تحويل الصوت إلى نص غير متاحة على هذا الجهاز');
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
    final availableLocales = await _speech.locales();
    final arabicLocales = availableLocales
        .where((locale) => locale.localeId.toLowerCase().startsWith('ar'))
        .toList();
    final iraqiLocale = arabicLocales.where(
      (locale) => locale.localeId.toLowerCase() == 'ar_iq',
    );
    final selectedLocale = iraqiLocale.isNotEmpty
        ? iraqiLocale.first.localeId
        : (arabicLocales.isNotEmpty ? arabicLocales.first.localeId : null);
    await _speech.listen(
      localeId: selectedLocale,
      listenFor: const Duration(seconds: 7),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _voiceText = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _answerRouteQuestion(result.recognizedWords);
        }
      },
    );
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

    String answer;
    if (_routePoints.isEmpty) {
      answer = 'حدد من وين تريد تنطلق ووين وجهتك، وبعدها أگدر أساعدك بالطريق.';
    } else if (q.contains('باقي') || q.contains('مسافة') || q.contains('بعيد')) {
      answer = 'المسافة الكلية تقريباً ${(_routeDistanceMeters / 1000).toStringAsFixed(1)} كيلومتر، والوقت التقديري ${(_routeDurationSeconds / 60).round()} دقيقة.';
    } else if (q.contains('انعطف') || q.contains('وين') || q.contains('الطريق')) {
      answer = _nextInstruction;
    } else {
      answer = 'حالياً أگدر أجاوبك عن المسافة والوقت وتعليمات الطريق. المساعد الذكي الحواري الكامل يحتاج ربط خادم آمن، وهذا بعده مو مفعّل.';
    }
    await _speak(answer);
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
                  initialCameraPosition: mlg.CameraPosition(
                    target: const mlg.LatLng(33.1, 43.8),
                    zoom: 5.5,
                    tilt: _is3d ? 55 : 0,
                  ),
                  styleString: isDark
                      ? 'https://tiles.openfreemap.org/styles/dark'
                      : 'https://tiles.openfreemap.org/styles/liberty',
                  compassEnabled: true,
                  logoEnabled: false,
                  trackCameraPosition: true,
                  onMapCreated: (controller) => _map = controller,
                  onStyleLoadedCallback: () {
                    _mapStyleLoaded = true;
                    unawaited(_syncMapAnnotations());
                  },
                ),
              )
            else
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFE7ECEB)),
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
            if (_routePoints.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 224,
                child: Card(
                  color: panelColor,
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${(_routeDistanceMeters / 1000).toStringAsFixed(1)} كم  •  ${(_routeDurationSeconds / 60).round()} دقيقة تقريباً',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Text(_nextInstruction, textDirection: TextDirection.rtl,
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _tracking ? _stopTracking : _startTracking,
                                icon: Icon(_tracking ? Icons.pause : Icons.navigation),
                                label: Text(_tracking ? 'إيقاف التتبع' : 'ابدأ تتبع السيارة'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'استمع للتوجيه',
                              onPressed: () => _speak(_nextInstruction),
                              icon: const Icon(Icons.volume_up),
                            ),
                          ],
                        ),
                        const Text(
                          'المسار تجريبي وقد لا يعكس كل الطرق أو الإغلاقات؛ انتبه للطريق واللوحات.',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _fromController,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          hintText: 'من وين تنطلق؟ (الافتراضي موقعي)',
                          prefixIcon: const Icon(Icons.trip_origin, color: Color(0xFF08AFA0)),
                          isDense: true,
                          filled: true,
                          fillColor: isDark ? const Color(0xFF172321) : const Color(0xFFF1F7F7),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _toController,
                              textDirection: TextDirection.rtl,
                              onChanged: (_) => setState(() => _selectedNearby = null),
                              decoration: InputDecoration(
                                hintText: 'وين تريد تروح؟',
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF08AFA0)),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF172321) : const Color(0xFFF1F7F7),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'موقعي الحالي كنقطة انطلاق',
                            onPressed: _useMyLocationAsOrigin,
                            icon: const Icon(Icons.my_location),
                          ),
                        ],
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
                      const SizedBox(height: 8),
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
                              icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                              label: Text(_listening ? 'دا أسمعك...' : 'احچي ويا دلّيني'),
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
  static const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

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
