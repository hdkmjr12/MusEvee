import 'package:flutter_test/flutter_test.dart';
import 'package:spotmeta_downloader/main.dart';

void main() {
  testWidgets('SpotMetaApp renders HomeScreen title and actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SpotMetaApp());

    expect(find.text('MusEvee'), findsOneWidget);
    expect(find.text('YOASOBI - Idol'), findsOneWidget);
  });
}

