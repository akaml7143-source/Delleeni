import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class _IraqiCity {
  const _IraqiCity(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

class TripPlannerPage extends StatefulWidget {
  const TripPlannerPage({super.key});
  @override
  State<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends State<TripPlannerPage> {
  static const _cities = <_IraqiCity>[
    _IraqiCity('بغداد',33.3152,44.3661), _IraqiCity('البصرة',30.5085,47.7804),
    _IraqiCity('الموصل',36.3350,43.1189), _IraqiCity('أربيل',36.1901,44.0091),
    _IraqiCity('النجف',32.0003,44.3354), _IraqiCity('كربلاء',32.6160,44.0249),
    _IraqiCity('العمارة',31.8359,47.1448), _IraqiCity('الناصرية',31.0570,46.2573),
    _IraqiCity('الكوت',32.5128,45.8182), _IraqiCity('الحلة',32.4811,44.4217),
    _IraqiCity('الديوانية',31.9929,44.9255), _IraqiCity('السماوة',31.3185,45.2803),
    _IraqiCity('تكريت',34.6071,43.6782), _IraqiCity('بعقوبة',33.7485,44.6427),
    _IraqiCity('الرمادي',33.4237,43.3078), _IraqiCity('كركوك',35.4681,44.3922),
    _IraqiCity('دهوك',36.8671,42.9500), _IraqiCity('السليمانية',35.5613,45.4300),
  ];

  final List<_IraqiCity> _stops = [];
  List<_IraqiCity> _ordered = [];
  double? _distanceMeters;
  double? _durationSeconds;
  bool _loading = false;
  String? _error;

  Future<void> _addStop() async {
    final available = _cities.where((city) => !_stops.any((stop) => stop.name == city.name)).toList();
    if (available.isEmpty) return;
    final city = await showModalBottomSheet<_IraqiCity>(
      context: context,
      builder: (context) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: available.map((item) => ListTile(
          leading: const Icon(Icons.location_city_outlined),
          title: Text(item.name, textDirection: TextDirection.rtl),
          onTap: () => Navigator.pop(context, item),
        )).toList(),
      )),
    );
    if (city != null && mounted) setState(() {
      _stops.add(city);
      _ordered = [];
      _distanceMeters = null;
      _durationSeconds = null;
    });
  }

  Future<void> _optimize() async {
    if (_stops.length < 2) {
      setState(() => _error = 'أضف محطتين على الأقل حتى نرتب الرحلة.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final coordinates = _stops.map((stop) => '${stop.longitude},${stop.latitude}').join(';');
      final uri = Uri.https('router.project-osrm.org', '/trip/v1/driving/$coordinates', const {
        'roundtrip': 'false', 'source': 'first', 'destination': 'last',
        'overview': 'false', 'steps': 'false',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('خدمة ترتيب المسارات غير متاحة (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final trips = data['trips'] as List? ?? [];
      final waypoints = data['waypoints'] as List? ?? [];
      if (data['code'] != 'Ok' || trips.isEmpty || waypoints.length != _stops.length) {
        throw Exception('تعذر إيجاد مسار يربط جميع المحطات.');
      }
      final trip = trips.first as Map<String, dynamic>;
      final orderedStops = List<_IraqiCity?>.filled(_stops.length, null);
      for (var inputIndex = 0; inputIndex < waypoints.length; inputIndex++) {
        final waypoint = waypoints[inputIndex] as Map<String, dynamic>;
        if ((waypoint['trips_index'] as num?)?.toInt() != 0) {
          throw Exception('المحطات ليست متصلة ضمن مسار واحد.');
        }
        final routeIndex = (waypoint['waypoint_index'] as num?)?.toInt();
        if (routeIndex == null || routeIndex < 0 || routeIndex >= _stops.length) {
          throw Exception('استجابة ترتيب المحطات غير مكتملة.');
        }
        orderedStops[routeIndex] = _stops[inputIndex];
      }
      if (orderedStops.any((stop) => stop == null)) {
        throw Exception('تعذر قراءة ترتيب المحطات من محرك الطرق.');
      }
      final sorted = orderedStops.cast<_IraqiCity>();
      if (!mounted) return;
      setState(() {
        _ordered = sorted;
        _distanceMeters = (trip['distance'] as num?)?.toDouble();
        _durationSeconds = (trip['duration'] as num?)?.toDouble();
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر ترتيب الرحلة: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تخطيط رحلة متعددة المحطات'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'اختر المدن التي تريد المرور بها. سيحاول محرك الطرق ترتيبها لتقليل مسافة القيادة مع تثبيت أول محطة وآخر محطة.',
              textDirection: TextDirection.rtl,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('محطات الرحلة (${_stops.length}/10)',
            textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleMedium)),
          FilledButton.tonalIcon(
            onPressed: _stops.length >= 10 ? null : _addStop,
            icon: const Icon(Icons.add), label: const Text('إضافة مدينة'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_stops.isEmpty) const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لم تضف محطات بعد.', textAlign: TextAlign.center, textDirection: TextDirection.rtl),
        ),
        ..._stops.asMap().entries.map((entry) => Card(
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(child: Text('${entry.key + 1}')),
            title: Text(entry.value.name, textDirection: TextDirection.rtl),
            trailing: IconButton(
              tooltip: 'إزالة المحطة', icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _stops.removeAt(entry.key);
                _ordered = [];
                _distanceMeters = null;
                _durationSeconds = null;
              }),
            ),
          ),
        )),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _optimize,
          icon: _loading ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route),
          label: Text(_loading ? 'جارٍ ترتيب المحطات...' : 'رتّب الرحلة حسب الطرق'),
        ),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, textDirection: TextDirection.rtl,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        if (_ordered.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('الترتيب المقترح', textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.titleLarge),
          if (_distanceMeters != null && _durationSeconds != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${(_distanceMeters! / 1000).toStringAsFixed(1)} كم • ${(_durationSeconds! / 60).round()} دقيقة تقريباً',
                textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ..._ordered.asMap().entries.map((entry) => ListTile(
            leading: CircleAvatar(child: Text('${entry.key + 1}')),
            title: Text(entry.value.name, textDirection: TextDirection.rtl),
            subtitle: Text(entry.key == 0 ? 'بداية الرحلة' :
              entry.key == _ordered.length - 1 ? 'نهاية الرحلة' : 'محطة مرور',
              textDirection: TextDirection.rtl),
          )),
        ],
        const SizedBox(height: 16),
        const Text(
          'مهم: الترتيب يعتمد على محرك OSRM العام وبيانات الطرق المتاحة، وليس خدمة مضمونة أو مخصصة للعراق. المدن ممثلة بإحداثيات مراكز تقريبية، لذلك راجع نقاط الانطلاق والوجهات الدقيقة قبل السفر.',
          textDirection: TextDirection.rtl, style: TextStyle(fontSize: 12),
        ),
      ]),
    );
  }
}
