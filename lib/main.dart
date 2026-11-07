import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/downloader_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFFFFFF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const SpotMetaApp());
}

class SpotMetaApp extends StatelessWidget {
  const SpotMetaApp({super.key});

  // Palet Modern Architectural UI (dhaauu.web.id + Linear/Vercel Surface Depth)
  static const Color bgCanvas = Color(0xFFF8FAFC);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSubtle = Color(0xFFF2F4F7);
  static const Color primaryBlue = Color(0xFF1677B8);
  static const Color primaryBlueDark = Color(0xFF0E5E93);
  static const Color textDark = Color(0xFF15181E);
  static const Color textMuted = Color(0xFF68717C);
  static const Color surfaceDark = Color(0xFF15191F);
  static final Color hairlineBorder = Colors.black.withValues(alpha: 0.07);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DownloaderProvider()),
      ],
      child: MaterialApp(
        title: 'MusEvee',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: bgCanvas,
          colorScheme: const ColorScheme.light(
            primary: primaryBlue,
            onPrimary: surfaceCard,
            secondary: primaryBlueDark,
            onSecondary: surfaceCard,
            surface: surfaceCard,
            onSurface: textDark,
            error: Color(0xFFD92D20),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: surfaceCard,
            foregroundColor: textDark,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: surfaceCard,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
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
              vertical: 13,
            ),
            hintStyle: const TextStyle(color: textMuted, fontSize: 13.5),
            labelStyle: const TextStyle(color: textMuted, fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: hairlineBorder, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: hairlineBorder, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: primaryBlue, width: 1.2),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: surfaceCard,
              disabledBackgroundColor: surfaceSubtle,
              disabledForegroundColor: textMuted,
              elevation: 0,
              minimumSize: const Size(48, 46),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                letterSpacing: -0.1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: textDark,
              backgroundColor: surfaceCard,
              minimumSize: const Size(44, 40),
              side: BorderSide(color: hairlineBorder, width: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
            selectedColor: primaryBlue,
            disabledColor: surfaceSubtle,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: hairlineBorder, width: 0.8),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: surfaceCard,
            indicatorColor: primaryBlue.withValues(alpha: 0.10),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            height: 62,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: primaryBlue, size: 20);
              }
              return const IconThemeData(color: textMuted, size: 19);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: primaryBlue,
                );
              }
              return const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: textMuted,
              );
            }),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: surfaceDark,
            contentTextStyle: const TextStyle(
              color: surfaceCard,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
