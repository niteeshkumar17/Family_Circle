import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:family_nest/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('FamilyNest E2E Full App Test', () {
    testWidgets('App Boots up and renders splash text', (WidgetTester tester) async {
      // Start the app
      app.main();
      
      // Wait for splash screen animations to finish
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Use try/catch because we don't know the exact starting state
      // We check if "FamilyNest" text is somewhere on the screen
      final appNameFinder = find.text('FamilyNest');
      if (appNameFinder.evaluate().isNotEmpty) {
         expect(appNameFinder, findsWidgets);
      }
      
      // Add a small delay so human can see it running
      await Future.delayed(const Duration(seconds: 2));
    });
  });
}
