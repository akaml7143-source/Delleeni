import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' hide Position;
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
  MapController? _map;
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

  Future<void> _toggle3d() async {
    setState(() => _is3d = !_is3d);
    final map = _map;
    if (map == null) return;
    final camera = map.getCamera();
    await map.animateCamera(
      CameraUpdate.position(
        center: camera.center,
        zoom: camera.zoom,
        bearing: camera.bearing,
        pitch: _is3d ? 55 : 0,
      ),
      animation: const CameraAnimation.fly(),
    );
  }

  Future<void> _useMyLocationAsOrigin() async {
    final point = await _currentLocation();
    if (point == null || !mounted) return;
    setState(() => _fromController.text = 'موقعي الحالي');
    await _map?.moveCamera(CameraUpdate.position(
      center: Geographic(lon: point.longitude, lat: point.latitude),
      zoom: 15,
      pitch: _is3d ? 55 : 0,
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
      if (destinations.isEmpty) {
        _message('اكتب اسم مدينة عراقية من القائمة المتاحة');
        return;
      }
      final destination = destinations.first.point;

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
          CameraUpdate.position(
            center: Geographic(lon: centerLon, lat: centerLat),
            zoom: zoom,
            pitch: _is3d ? 55 : 0,
          ),
          animation: const CameraAnimation.fly(),
        );
      }
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
    if (type == 'depart') return 'ابدأ السير $roadText';
    if (modifier.contains('left')) return 'بعد قليل انعطف يسار $roadText';
    if (modifier.contains('right')) return 'بعد قليل انعطف يمين $roadText';
    if (modifier == 'uturn') return 'استدر وارجع بالاتجاه المعاكس';
    if (type == 'roundabout' || type == 'rotary') {
      return 'ادخل الدوار، $roadText';
    }
    if (type == 'merge') return 'اندَمج مع المسار $roadText';
    if (type == 'fork') return 'خذ التفرع $roadText';
    if (type == 'new name' || type == 'continue') return 'استمر $roadText';
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
    ).listen((position) {
      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userPoint = point);
      unawaited(_checkRouteDeviation(point));
      final currentZoom = _map?.getCamera().zoom ?? 15.0;
      _map?.moveCamera(CameraUpdate.position(
        center: Geographic(lon: point.longitude, lat: point.latitude),
        zoom: currentZoom < 14 ? 15 : currentZoom,
        pitch: _is3d ? 55 : 0,
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
      await _tts.setLanguage('ar');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
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
              MapLibreMap(
              options: MapOptions(
                style: MapStyle.url(isDark
                    ? 'https://tiles.openfreemap.org/styles/dark'
                    : 'https://tiles.openfreemap.org/styles/liberty'),
                initCamera: CameraUpdate.position(
                  center: const Geographic(lon: 43.8, lat: 33.1),
                  zoom: 5.5,
                  pitch: _is3d ? 55 : 0,
                ),
              ),
              onMapCreated: (controller) => _map = controller,
              layers: [
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Feature(
                        geometry: LineString.from(_routePoints.map(
                          (p) => Geographic(lon: p.longitude, lat: p.latitude),
                        )),
                      ),
                    ],
                    color: const .literal(Color(0xFF08AFA0)),
                    width: const .literal(6),
                  ),
                if (_routeOrigin != null && _userPoint == null)
                  MarkerLayer(
                    points: [
                      Feature(
                        geometry: Point(Geographic(
                          lon: _routeOrigin!.longitude,
                          lat: _routeOrigin!.latitude,
                        )),
                      ),
                    ],
                    icon: const .iconData(Icons.trip_origin, color: Colors.green),
                    iconAnchor: const .literal(IconAnchor.bottom),
                  ),
                if (_routeDestination != null)
                  MarkerLayer(
                    points: [
                      Feature(
                        geometry: Point(Geographic(
                          lon: _routeDestination!.longitude,
                          lat: _routeDestination!.latitude,
                        )),
                      ),
                    ],
                    icon: const .iconData(Icons.location_on, color: Colors.red),
                    iconAnchor: const .literal(IconAnchor.bottom),
                  ),
                if (_userPoint != null)
                  MarkerLayer(
                    points: [
                      Feature(
                        geometry: Point(Geographic(
                          lon: _userPoint!.longitude,
                          lat: _userPoint!.latitude,
                        )),
                      ),
                    ],
                    icon: const .iconData(
                      Icons.directions_car_filled,
                      color: Color(0xFF073B5C),
                    ),
                    iconAnchor: const .literal(IconAnchor.bottom),
                  ),
              ],
              children: const [SourceAttribution(), MapCompass()],
            )
            else
              const ColoredBox(color: Color(0xFFE7ECEB)),
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
                      tooltip: 'موقعي الحالي',
                      onPressed: _useMyLocationAsOrigin,
                      icon: const Icon(Icons.my_location),
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _toController,
                              textDirection: TextDirection.rtl,
                              onChanged: (_) => setState(() {}),
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
