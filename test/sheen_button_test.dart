import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throttle/widgets/ui.dart';

Widget _button() => SheenButton(
      onTap: () {},
      child: const SizedBox(
        width: 320,
        height: 100,
        child: ColoredBox(color: Colors.white),
      ),
    );

void main() {
  testWidgets('a glint every 2 s: 1 s of light, 1 s of calm', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: _button())));
    await tester.pump(const Duration(milliseconds: 100)); // app start-up
    // Calm: nothing animates (no frames).
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pump(const Duration(milliseconds: 1000)); // 1.1 s
    expect(tester.binding.hasScheduledFrame, isTrue); // glinting
    await tester.pump(const Duration(milliseconds: 850)); // 1.95 s
    expect(tester.binding.hasScheduledFrame, isTrue); // still: it lasts 1 s

    await tester.pump(const Duration(milliseconds: 250)); // 2.2 s
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse); // calm again

    await tester.pump(const Duration(milliseconds: 800)); // 3.0 s
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 300)); // 3.3 s
    expect(tester.binding.hasScheduledFrame, isTrue); // the next one
  });

  testWidgets('no glint while its tab is hidden', (tester) async {
    Widget tabs(int index) => MaterialApp(
          home: IndexedStack(
            index: index,
            children: [Center(child: _button()), const SizedBox()],
          ),
        );
    await tester.pumpWidget(tabs(1));
    await tester.pump(const Duration(seconds: 6));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(tabs(0));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('no glint when the rider asks for reduced motion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(child: _button()),
      ),
    ));
    await tester.pump(const Duration(seconds: 6));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('presses in under a finger', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Center(child: _button())));
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

    final finger =
        await tester.startGesture(tester.getCenter(find.byType(SheenButton)));
    await tester.pump();
    expect(scale(), lessThan(1));

    await finger.up();
    await tester.pump();
    expect(scale(), 1);
  });
}
