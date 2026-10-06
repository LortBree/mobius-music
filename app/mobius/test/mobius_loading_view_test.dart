import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/widgets/mobius_loading_view.dart';

void main() {
  testWidgets('MobiusLoadingView renders 3D mobius loop image without text or logo wordmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MobiusLoadingView(size: 150),
        ),
      ),
    );

    // Verify 3D loop image is rendered
    expect(find.byType(Image), findsOneWidget);

    // Verify NO text or "Mobius Music" wordmark is rendered
    expect(find.byType(Text), findsNothing);
    expect(find.text('Mobius Music'), findsNothing);

    // Verify animation ticks smoothly
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MobiusLoadingView), findsOneWidget);
  });
}
