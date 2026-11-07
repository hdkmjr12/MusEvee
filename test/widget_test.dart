import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/main.dart';

void main() {
  testWidgets(
      'MusicEveeApp renders Musicolet NowPlayingView and switches to Downloader tab',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MusicEveeApp());
    await tester.pump();

    // Default tab is Musicolet Now Playing (Tab 1)
    expect(find.text('MusicEvee Player'), findsOneWidget);
    expect(find.text('Cari & Unduh Lagu'), findsOneWidget);

    // Switch to Downloader tab (Tab 5: Cloud Download icon in MusicoletBottomStrip)
    await tester.tap(find.byIcon(Icons.cloud_download_outlined).last);
    await tester.pump();

    expect(find.text('MusicEvee'), findsOneWidget);
    expect(find.text('v4.0'), findsOneWidget);
    expect(find.text('YOASOBI - Idol'), findsOneWidget);
  });
}
