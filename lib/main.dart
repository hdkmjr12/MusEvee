import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/downloader_provider.dart';
import 'providers/local_music_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0C10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MusicEveeApp());
}

typedef SpotMetaApp = MusicEveeApp;

class MusicEveeApp extends StatelessWidget {
  const MusicEveeApp({super.key});

  // Palet Musicolet Reverse-Engineered Dark UI
  static const Color bgCanvas = Color(0xFF0E1014);
  static const Color surfaceCard = Color(0xFF17191E);
  static const Color surfaceSubtle = Color(0xFF22252D);
  static const Color primaryAccent = Color(0xFF3898EC);
  static const Color primaryAccentDark = Color(0xFF1D74C6);
  static const Color textLight = Color(0xFFF2F4F7);
  static const Color textMuted = Color(0xFF98A2B3);
  static final Color hairlineBorder = Colors.white.withValues(alpha: 0.09);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocalMusicProvider>(
          create: (_) => LocalMusicProvider(),
        ),
        ChangeNotifierProxyProvider<LocalMusicProvider, DownloaderProvider>(
          create: (_) => DownloaderProvider(),
          update: (_, localMusic, downloader) {
            final d = downloader ?? DownloaderProvider();
            d.onLibraryChanged = () {
              localMusic.refreshLibrary();
            };
            return d;
          },
        ),
      ],
      child: MaterialApp(
        title: 'MusicEvee',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: _buildDarkTheme(),
        theme: _buildDarkTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgCanvas,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        onPrimary: Colors.white,
        secondary: primaryAccentDark,
        onSecondary: Colors.white,
        surface: surfaceCard,
        onSurface: textLight,
        error: Color(0xFFF04438),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF12151C),
        foregroundColor: textLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: hairlineBorder, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: hairlineBorder, width: 0.8),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: textMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hairlineBorder, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: hairlineBorder, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryAccent, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceSubtle,
          disabledForegroundColor: textMuted,
          elevation: 0,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textLight,
          backgroundColor: surfaceSubtle,
          minimumSize: const Size(44, 38),
          side: BorderSide(color: hairlineBorder, width: 0.8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSubtle,
        selectedColor: primaryAccent,
        disabledColor: surfaceSubtle,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: hairlineBorder, width: 0.8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1F242F),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
