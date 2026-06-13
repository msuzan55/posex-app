import 'package:flutter_test/flutter_test.dart';
import 'package:posex_app/app.dart';

void main() {
  testWidgets('PosEx app shows splash branding', (WidgetTester tester) async {
    await tester.pumpWidget(const PosexApp());
    await tester.pump();

    expect(find.text('PosEx'), findsOneWidget);
    expect(find.text('POS for Sri Lankan retail'), findsOneWidget);
  });
}
