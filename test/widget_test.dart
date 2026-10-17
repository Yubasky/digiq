import 'package:flutter_test/flutter_test.dart';
import 'package:digiq/main.dart';

void main() {
  testWidgets('DigiQ dashboard smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DigiQApp());
    expect(find.text('DigiQ Store'), findsOneWidget);
  });
}
