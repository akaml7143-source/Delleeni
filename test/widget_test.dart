import 'package:delleeni/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Delleeni shows the full-screen map controls in Arabic', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapHomePage(
        isDark: false,
        onToggleTheme: () {},
        showMap: false,
      ),
    ));
    expect(find.text('دِلِّينِي'), findsOneWidget);
    expect(find.text('وين تريد تروح؟'), findsOneWidget);
    expect(find.text('من وين تنطلق؟ (الافتراضي موقعي)'), findsOneWidget);
    expect(find.text('اعرض الطريق'), findsOneWidget);
    expect(find.text('احچي ويا دلّيني'), findsOneWidget);
  });
  testWidgets('offline map manager lists Iraqi governorates', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OfflineMapsPage()));
    expect(find.text('إدارة الخرائط بدون إنترنت'), findsOneWidget);
    expect(find.text('خرائط محافظات العراق'), findsOneWidget);
    expect(find.text('البصرة'), findsOneWidget);
    expect(find.text('بغداد'), findsOneWidget);
    expect(find.text('لم تُنزّل بعد'), findsNWidgets(18));
  });

}
