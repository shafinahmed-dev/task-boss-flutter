import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/main.dart';
import 'package:task_boss/services/app_state.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
        ],
        child: const MainApp(),
      ),
    );
  });
}
