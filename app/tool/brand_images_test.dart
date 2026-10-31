// Renders Duo's icons and link-preview image from the app's own widgets.
// Run: flutter test tool/brand_images_test.dart --update-goldens
import 'dart:io';
import 'dart:typed_data';

import 'package:duo/core/models.dart';
import 'package:duo/ui/buddies.dart';
import 'package:duo/ui/pet_sprite.dart';
import 'package:duo/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(File('assets/fonts/$f').readAsBytesSync()))));
  }
  await loader.load();
}

Widget still(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

Future<void> render(WidgetTester tester, Size size, Widget child, String path) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(still(RepaintBoundary(child: child)));
  await tester.pumpAndSettle();
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(path));
}

/// The two buddies on sunflower yellow. Maskable icons keep them inside the safe zone.
Widget icon({required bool maskable}) => ColoredBox(
  color: DuoColors.sunflower,
  child: Center(child: Buddies(size: maskable ? 200 : 270)),
);

void main() {
  setUpAll(() async {
    await loadFont('Fraunces', ['Fraunces-Medium.ttf', 'Fraunces-SemiBold.ttf']);
    await loadFont('Nunito', ['Nunito-Regular.ttf', 'Nunito-SemiBold.ttf', 'Nunito-Bold.ttf']);
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize());

  testWidgets('app icon', (tester) async {
    await render(tester, const Size(512, 512), icon(maskable: false), '../web/icons/Icon-512.png');
  });

  testWidgets('maskable app icon', (tester) async {
    await render(tester, const Size(512, 512), icon(maskable: true), '../web/icons/Icon-maskable-512.png');
  });

  testWidgets('link preview', (tester) async {
    const ink = DuoColors.ink;
    await render(
      tester,
      const Size(1200, 630),
      ColoredBox(
        color: DuoColors.paper,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(80, 70, 70, 60),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'duo',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 110,
                        fontWeight: FontWeight.w600,
                        color: ink,
                        height: 1,
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'one tiny game a day,\nfor you and your person.',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 50,
                        fontWeight: FontWeight.w600,
                        color: ink,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 28),
                    Text(
                      'daily games · live chess & ludo · a pet you raise together',
                      style: TextStyle(fontFamily: 'Nunito', fontSize: 26, fontWeight: FontWeight.w600, color: ink),
                    ),
                    Spacer(),
                    Text(
                      'dyduo.netlify.app',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: DuoColors.tomato,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Buddies(size: 170),
                  const SizedBox(height: 10),
                  PetSprite(
                    stage: PetStage.kid,
                    mood: PetMood.happy,
                    color: petColors['mint']!,
                    outfit: 'party',
                    size: 190,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      '../web/og-image.png',
    );
  });
}
