import 'package:delleeni/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Delleeni shows route planning controls in Arabic', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapHomePage(
        isDark: false,
        onToggleTheme: () {},
        showMap: false,
      ),
    ));
    expect(find.text('دِلِّينِي'), findsOneWidget);
    expect(find.text('من أين؟'), findsOneWidget);
    expect(find.text('إلى أين؟ اكتب اسم المدينة'), findsOneWidget);
    expect(find.text('اعرض الطريق'), findsOneWidget);
  });
}
