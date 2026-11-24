import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/delleeni_backend.dart';
import 'trip_planner_page.dart';

/// Community and live-data tools. No location is read until the user taps
/// a location-dependent action; submissions remain pending for moderation.
class IraqFeaturesPage extends StatefulWidget {
  const IraqFeaturesPage({super.key});

  @override
  State<IraqFeaturesPage> createState() => _IraqFeaturesPageState();
}

class _IraqFeaturesPageState extends State<IraqFeaturesPage> {
  final DelleeniBackend _backend = DelleeniBackend();
  DelleeniSession? _session;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _accessibility = [];
  List<Map<String, dynamic>> _routeStops = [];
  String? _selectedRouteName;

  static const _governorates = [
    'بغداد','البصرة','نينوى','أربيل','النجف','كربلاء','ميسان','ذي قار',
    'واسط','بابل','القادسية','المثنى','صلاح الدين','ديالى','الأنبار',
    'كركوك','دهوك','السليمانية',
  ];

  bool get _configured => _backend.isConfigured;

  @override
  void dispose() {
    _backend.close();
    super.dispose();
  }

  void _showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value, textDirection: TextDirection.rtl)),
    );
  }

  Future<Position?> _getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage('فعّل خدمة الموقع أولاً.');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showMessage('يلزم السماح بالموقع لهذا الإجراء فقط.');
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<DelleeniSession> _getSession() async {
    if (_session != null) return _session!;
    final session = await _backend.signInAnonymously();
    _session = session;
    return session;
  }

  Future<void> _loadReports() async {
    if (!_configured) {
      _showMessage('أضف إعدادات Supabase أولاً لتشغيل البلاغات الحية.');
      return;
    }
    setState(() => _busy = true);
    try {
      final position = await _getPosition();
      if (position == null) return;
      final rows = await _backend.fetchNearbyReports(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: 5000,
      );
      if (mounted) setState(() => _reports = rows);
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر تحميل البلاغات: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRoutes() async {
    if (!_configured) {
      _showMessage('بيانات النقل تظهر بعد إعداد الخادم وإضافة خطوط موثقة.');
      return;
    }
    final city = await _askText('اسم المدينة', hint: 'مثلاً: العمارة');
    if (city == null || city.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final rows = await _backend.fetchTransitRoutes(city: city.trim());
      if (mounted) setState(() => _routes = rows);
      if (rows.isEmpty) _showMessage('لا توجد خطوط منشورة وموثقة لهذه المدينة بعد.');
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر تحميل خطوط النقل: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAccessibility() async {
    if (!_configured) {
      _showMessage('بيانات الوصول الميسر تحتاج خادماً وبيانات ميدانية موثقة.');
      return;
    }
    setState(() => _busy = true);
    try {
      final position = await _getPosition();
      if (position == null) return;
      final rows = await _backend.fetchAccessibilityFeatures(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: 3000,
      );
      if (mounted) setState(() => _accessibility = rows);
      if (rows.isEmpty) _showMessage('لا توجد نقاط وصول ميسر موثقة منشورة بعد.');
    } catch (error) {
      if (mounted) setState(() => _error = 'تعذر تحميل بيانات الوصول: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askText(String title, {String? hint}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _submitRoadReport() async {
    if (!_configured) {
      _showMessage('خدمات البلاغات غير مهيأة بعد. راجع ملف BACKEND_SETUP_AR.md.');
      return;
    }
    const kinds = {
      'ازدحام': 'traffic',
      'إغلاق طريق': 'closure',
      'أعمال صيانة': 'roadwork',
      'خطر على الطريق': 'hazard',
      'أخرى': 'other',
    };
    String selected = 'traffic';
    final detailsController = TextEditingController();
    final governorateController = ValueNotifier<String>(_governorates[0]);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('إرسال بلاغ طريق', textDirection: TextDirection.rtl),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'نوع البلاغ'),
                  items: kinds.entries.map((entry) => DropdownMenuItem(
                    value: entry.value, child: Text(entry.key),
                  )).toList(),
                  onChanged: (value) => refresh(() => selected = value ?? selected),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: governorateController.value,
                  decoration: const InputDecoration(labelText: 'المحافظة'),
                  items: _governorates.map((name) => DropdownMenuItem(
                    value: name, child: Text(name),
                  )).toList(),
                  onChanged: (value) => refresh(() =>
                    governorateController.value = value ?? governorateController.value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  maxLength: 240,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل مختصرة (اختياري)',
                    hintText: 'لا تكتب معلومات شخصية',
                  ),
                ),
                const Text(
                  'سيُرسل موقع البلاغ بعد موافقتك، ولن يظهر للعامة قبل مراجعته. تنتهي صلاحيته بعد 6 ساعات.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إرسال للمراجعة'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      detailsController.dispose();
      governorateController.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final position = await _getPosition();
      if (position == null) return;
      final session = await _getSession();
      await _backend.submit('road_reports', {
        'kind': selected,
        'details': detailsController.text.trim(),
        'governorate': governorateController.value,
        'location': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
        'created_by': session.userId,
        'status': 'pending',
      }, accessToken: session.accessToken);
      _showMessage('وصل البلاغ إلى قائمة المراجعة. شكراً لمساهمتك.');
    } catch (error) {
      _showMessage('تعذر إرسال البلاغ: $error');
    } finally {
      detailsController.dispose();
      governorateController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _suggestPlace() async {
    if (!_configured) {
      _showMessage('خدمات إضافة الأماكن غير مهيأة بعد.');
      return;
    }
    final name = await _askText('اسم المكان');
    if (name == null || name.trim().isEmpty) return;
    final category = await _askText('نوع المكان', hint: 'صيدلية، سوق، ورشة...');
    if (category == null || category.trim().isEmpty) return;
    final governorate = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _governorates.map((item) => ListTile(
            title: Text(item, textDirection: TextDirection.rtl),
            onTap: () => Navigator.pop(context, item),
          )).toList(),
        ),
      ),
    );
    if (governorate == null) return;
    setState(() => _busy = true);
    try {
      final position = await _getPosition();
      if (position == null) return;
      final session = await _getSession();
      final inserted = await _backend.submit('places', {
        'name': name.trim(),
        'category': category.trim(),
        'governorate': governorate,
        'location': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
        'created_by': session.userId,
        'source': 'community',
        'status': 'pending',
      }, accessToken: session.accessToken);
      if (inserted.isNotEmpty && inserted.first['id'] != null) {
        await _backend.submit('community_contributions', {
          'entity_type': 'place',
          'entity_id': inserted.first['id'],
          'action': 'add',
          'payload': {'name': name.trim(), 'category': category.trim()},
          'created_by': session.userId,
          'status': 'pending',
        }, accessToken: session.accessToken);
      }
      _showMessage('تم إرسال المكان للمراجعة قبل نشره على الخريطة.');
    } catch (error) {
      _showMessage('تعذر إرسال المكان: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, textDirection: TextDirection.rtl,
          style: Theme.of(context).textTheme.titleMedium)),
      ],
    ),
  );

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String description,
    String? status,
    VoidCallback? onTap,
  }) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon, size: 28),
      title: Text(title, textDirection: TextDirection.rtl),
      subtitle: Text(description, textDirection: TextDirection.rtl),
      trailing: status == null ? null : Text(status,
        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.secondary)),
      onTap: onTap,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خدمات دِلّيني'), centerTitle: true),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'من هنا تصل إلى خدمات الدليل والبلاغات والنقل ومساهمات المجتمع. لا تُرسل إحداثيات موقعك إلا عند اختيار إجراء يحتاج الموقع.',
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
              _sectionTitle('الخريطة والملاحة', Icons.map_outlined),
              _featureCard(icon: Icons.download_for_offline, title: 'خرائط المحافظات دون إنترنت',
                description: 'إدارة تنزيل الخرائط المخزنة على الجهاز.'),
              _featureCard(icon: Icons.mic, title: 'المساعد الصوتي العراقي',
                description: 'أوامر الملاحة الصوتية الأساسية تعمل من الواجهة الرئيسية.'),
              _featureCard(icon: Icons.alt_route, title: 'ترتيب الرحلات متعددة الوجهات',
                description: 'اختر مدناً متعددة ودع محرك الطرق يقترح ترتيباً أقصر للقيادة.',
                status: 'تجريبي',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const TripPlannerPage(),
                ))),
              _featureCard(icon: Icons.view_in_ar, title: 'عرض ثلاثي الأبعاد',
                description: 'الموجود حالياً إمالة الكاميرا فقط؛ نماذج المباني تحتاج بيانات هندسية.',
                status: 'جزئي'),
              _sectionTitle('دليل المجتمع والطرق', Icons.place_outlined),
              _featureCard(icon: Icons.add_location_alt, title: 'اقتراح إضافة مكان',
                description: 'إرسال مكان جديد مع موقعه للمراجعة قبل النشر.',
                status: _configured ? 'متاح بعد إعداد الخادم' : 'يلزم إعداد الخادم',
                onTap: _suggestPlace),
              _featureCard(icon: Icons.report_gmailerrorred, title: 'إرسال بلاغ طريق',
                description: 'ازدحام أو إغلاق أو صيانة أو خطر؛ البلاغات الجديدة قيد المراجعة.',
                status: _configured ? 'متاح بعد إعداد الخادم' : 'يلزم إعداد الخادم',
                onTap: _submitRoadReport),
              _featureCard(icon: Icons.refresh, title: 'عرض البلاغات المؤكدة القريبة',
                description: 'لا تظهر إلا البلاغات المنشورة وغير المنتهية.',
                status: '${_reports.length} بلاغ',
                onTap: _loadReports),
              if (_reports.isNotEmpty) ..._reports.map((item) => ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(item['kind']?.toString() ?? 'بلاغ', textDirection: TextDirection.rtl),
                subtitle: Text('${item['governorate'] ?? ''} • ${item['details'] ?? ''}',
                  textDirection: TextDirection.rtl),
              )),
              _sectionTitle('النقل والوصول الميسر', Icons.directions_bus_outlined),
              _featureCard(icon: Icons.directions_bus, title: 'خطوط الباص والكيا',
                description: 'بحث الخطوط المنشورة والأجرة التقديرية عند توفر بيانات موثقة.',
                status: '${_routes.length} خط',
                onTap: _loadRoutes),
              if (_routes.isNotEmpty) ..._routes.map((item) => ListTile(
                leading: const Icon(Icons.route),
                title: Text(item['name']?.toString() ?? 'خط نقل', textDirection: TextDirection.rtl),
                subtitle: Text('${item['city'] ?? ''} • ${item['fare_min_iqd'] ?? '؟'} - ${item['fare_max_iqd'] ?? '؟'} د.ع',
                  textDirection: TextDirection.rtl),
                onTap: () async {
                  final routeId = item['id']?.toString();
                  if (routeId == null) return;
                  setState(() { _busy = true; _selectedRouteName = item['name']?.toString(); });
                  try {
                    final stops = await _backend.fetchTransitStops(routeId: routeId);
                    if (mounted) setState(() => _routeStops = stops);
                    if (stops.isEmpty) _showMessage('لا توجد محطات منشورة لهذا الخط بعد.');
                  } catch (error) {
                    _showMessage('تعذر تحميل محطات الخط: $error');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              )),
              if (_selectedRouteName != null) ...[
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('محطات خط $_selectedRouteName', textDirection: TextDirection.rtl),
                ),
                ..._routeStops.map((stop) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(stop['name']?.toString() ?? 'محطة', textDirection: TextDirection.rtl),
                  subtitle: Text('التسلسل: ${stop['sequence_no'] ?? ''}', textDirection: TextDirection.rtl),
                )),
              ],
              _featureCard(icon: Icons.accessible_forward, title: 'مسارات الوصول الميسر',
                description: 'عرض النقاط المنشورة والموثقة ضمن 3 كم من موقعك؛ لا نفترض أن الطريق مهيأ دون دليل.',
                status: '${_accessibility.length} نقطة',
                onTap: _loadAccessibility),
              if (_accessibility.isNotEmpty) ..._accessibility.map((item) => ListTile(
                leading: const Icon(Icons.accessible),
                title: Text(item['kind']?.toString() ?? 'ميزة وصول', textDirection: TextDirection.rtl),
                subtitle: Text(item['notes']?.toString() ?? '', textDirection: TextDirection.rtl),
              )),
              _sectionTitle('بيانات وإعدادات', Icons.settings_outlined),
              _featureCard(icon: Icons.storage_outlined, title: 'حالة الربط بالخادم',
                description: _configured ? 'تم العثور على إعدادات Supabase في وقت البناء.' :
                  'لم تُضبط قيم SUPABASE_URL وSUPABASE_ANON_KEY بعد.',
                status: _configured ? 'مهيأ' : 'غير مهيأ'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, textDirection: TextDirection.rtl,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'تنبيه: لا توجد بيانات نقل أو مبانٍ ثلاثية الأبعاد أو وصول ميسر مضافة افتراضياً. لا تُعرض معلومات غير موثقة على أنها حقيقة.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
