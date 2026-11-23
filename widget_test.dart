import 'package:delleeni/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Delleeni app shows Arabic brand', (tester) async {
    await tester.pumpWidget(const DelleeniApp());
    expect(find.text('دِلِّينِي'), findsOneWidget);
    expect(find.text('ابحث عن مدينة أو محافظة...'), findsOneWidget);
  });
}
