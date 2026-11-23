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
}
