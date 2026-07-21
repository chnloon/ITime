import 'package:flutter_test/flutter_test.dart';
import 'package:oigo/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OiGoApp());
    expect(find.text('OiGo'), findsOneWidget);
  });
}
