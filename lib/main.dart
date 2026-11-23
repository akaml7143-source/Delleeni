import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
    super.key,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  final MapController _map = MapController();
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

  Future<void> _useMyLocationAsOrigin() async {
    final point = await _currentLocation();
    if (point == null || !mounted) return;
    setState(() => _fromController.text = 'موقعي الحالي');
    _map.move(point, 15);
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
        final bounds = LatLngBounds.fromPoints(points);
        _map.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(38, 230, 38, 170),
          ),
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
      _map.move(point, _map.camera.zoom < 14 ? 15 : _map.camera.zoom);
    }, onError: (_) {
      _message('انقطع تتبع الموقع');
      if (mounted) setState(() => _tracking = false);
    });
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
    await _speech.listen(
      localeId: 'ar_IQ',
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
    final markers = <Marker>[
      if (_routeOrigin != null && _userPoint == null)
        Marker(
          point: _routeOrigin!,
          width: 42,
          height: 48,
          child: const Icon(Icons.trip_origin, color: Colors.green, size: 32),
        ),
      if (_routeDestination != null)
        Marker(
          point: _routeDestination!,
          width: 44,
          height: 48,
          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
        ),
      if (_userPoint != null)
        Marker(
          point: _userPoint!,
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .22), blurRadius: 8)],
            ),
            child: const Icon(Icons.directions_car_filled,
                color: Color(0xFF087E70), size: 34),
          ),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: const MapOptions(
                initialCenter: LatLng(33.1, 43.8),
                initialZoom: 5.5,
                minZoom: 4,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: isDark
                      ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'iq.delleeni.delleeni',
                  maxZoom: 19,
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 7,
                        color: const Color(0xFF1689E8),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                    TextSourceAttribution('© CARTO'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Card(
                color: panelColor,
                elevation: 5,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('دِلِّينِي', style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            )),
                          ),
                          IconButton(
                            tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                            onPressed: widget.onToggleTheme,
                            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                          ),
                          IconButton(
                            tooltip: 'موقعي الحالي',
                            onPressed: _useMyLocationAsOrigin,
                            icon: const Icon(Icons.my_location),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _fromController,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'من أين؟',
                          prefixIcon: Icon(Icons.trip_origin, color: Colors.green),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _toController,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'إلى أين؟ اكتب اسم المدينة',
                          prefixIcon: Icon(Icons.location_on, color: Colors.red),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loadingRoute ? null : _buildRoute,
                          icon: _loadingRoute
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.alt_route),
                          label: const Text('اعرض الطريق'),
                        ),
                      ),
                      if (_toController.text.isNotEmpty &&
                          _findPlaces(_toController.text).isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'الوجهة: ${_findPlaces(_toController.text).first.name} — ${_findPlaces(_toController.text).first.governorate}',
                            style: Theme.of(context).textTheme.bodySmall,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_routePoints.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 92,
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
              right: 14,
              bottom: 22,
              child: FloatingActionButton.extended(
                heroTag: 'voiceAssistant',
                onPressed: _askByVoice,
                icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                label: Text(_listening ? 'أسمعك...' : 'اسأل عن الطريق'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
