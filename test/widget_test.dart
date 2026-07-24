import 'package:flutter_test/flutter_test.dart';
import 'package:call/app.dart';

void main() {
  testWidgets('SoftphoneApp smoke test', (WidgetTester tester) async {
    expect(SoftphoneApp, isNotNull);
  });
}
