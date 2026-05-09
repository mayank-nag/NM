import 'package:flutter_test/flutter_test.dart';
import 'package:nm/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const NMApp());
    // Just verify it renders without crashing
    expect(find.byType(NMApp), findsOneWidget);
  });
}
