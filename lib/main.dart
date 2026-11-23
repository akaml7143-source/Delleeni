import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const DelleeniApp());

class DelleeniApp extends StatelessWidget {
  const DelleeniApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'دِلِّينِي',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087E70))),
        home: const MapHomePage(),
      );
}

class IraqPlace {
  const IraqPlace(this.name, this.governorate, this.point);
  final String name;
  final String governorate;
  final LatLng point;
}

// مراكز مدن تقريبية وليست حدوداً إدارية رسمية.
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
  const MapHomePage({super.key});
  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage> {
  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();
  String _query = '';
  LatLng? _userPoint;
  IraqPlace? _selected;
  bool _locating = false;

  List<IraqPlace> get _matches => _query.trim().isEmpty
      ? const []
      : iraqPlaces.where((p) => p.name.contains(_query.trim()) || p.governorate.contains(_query.trim())).toList();

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  void _select(IraqPlace p) {
    setState(() { _selected = p; _query = ''; _search.clear(); });
    _map.move(p.point, 11.5);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) { _message('فعّل خدمة الموقع ثم حاول مجدداً'); return; }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) { _message('لم يُسمح للتطبيق بالوصول إلى الموقع'); return; }
      final pos = await Geolocator.getCurrentPosition();
      final point = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _userPoint = point);
      _map.move(point, 15);
    } catch (_) { _message('تعذّر تحديد موقعك. تحقق من GPS والإنترنت'); }
    finally { if (mounted) setState(() => _locating = false); }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      ...iraqPlaces.map((p) => Marker(point: p.point, width: 40, height: 46,
        child: GestureDetector(onTap: () => _select(p), child: const Icon(Icons.location_on, color: Color(0xFF087E70), size: 38)))),
      if (_userPoint != null) Marker(point: _userPoint!, width: 26, height: 26,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 25)),
    ];
    return Scaffold(
      body: SafeArea(child: Stack(children: [
        FlutterMap(mapController: _map,
          options: const MapOptions(initialCenter: LatLng(33.1, 43.8), initialZoom: 5.5, minZoom: 4, maxZoom: 18),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'iq.delleeni.delleeni', maxZoom: 19),
            MarkerLayer(markers: markers),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ]),
        Positioned(top: 12, left: 14, right: 14, child: Column(children: [
          Material(elevation: 4, borderRadius: BorderRadius.circular(18), child: TextField(
            controller: _search, textDirection: TextDirection.rtl,
            decoration: InputDecoration(hintText: 'ابحث عن مدينة أو محافظة...', prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: () { _search.clear(); setState(() => _query = ''); }, icon: const Icon(Icons.close)),
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 17)),
            onChanged: (v) => setState(() => _query = v))),
          if (_matches.isNotEmpty) Container(margin: const EdgeInsets.only(top: 6), constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: ListView.builder(shrinkWrap: true, itemCount: _matches.length, itemBuilder: (context, i) {
              final p = _matches[i];
              return ListTile(dense: true, leading: const Icon(Icons.location_city), title: Text(p.name, textDirection: TextDirection.rtl),
                subtitle: Text(p.governorate, textDirection: TextDirection.rtl), onTap: () => _select(p));
            })),
        ])),
        Positioned(right: 16, bottom: 26, child: FloatingActionButton(heroTag: 'locate', onPressed: _locate,
          child: _locating ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location))),
        Positioned(left: 14, bottom: 28, child: Material(color: Colors.white, elevation: 3, borderRadius: BorderRadius.circular(14),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            const Text('دِلِّينِي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF087E70))),
            Text(_selected == null ? 'العراق بين يديك' : '${_selected!.name} - ${_selected!.governorate}', textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 11)),
          ])))),
      ])),
    );
  }
}
