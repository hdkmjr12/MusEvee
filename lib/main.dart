import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/downloader_provider.dart';
import 'providers/local_music_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme/musevee_palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: MusEveePalette.dark.bottomBar,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MusEveeApp());
}

typedef SpotMetaApp = MusEveeApp;

class MusEveeApp extends StatefulWidget {
  final SettingsProvider? settingsProvider;

  const MusEveeApp({super.key, this.settingsProvider});

  @override
  State<MusEveeApp> createState() => _MusEveeAppState();
}

class _MusEveeAppState extends State<MusEveeApp> {
  late final SettingsProvider _settingsProvider;
  late final bool _ownsSettingsProvider;
  late final LocalMusicProvider _localMusicProvider;
  late final DownloaderProvider _downloaderProvider;

  @override
  void initState() {
    super.initState();
    if (widget.settingsProvider != null) {
      _settingsProvider = widget.settingsProvider!;
      _ownsSettingsProvider = false;
    } else {
      _settingsProvider = SettingsProvider();
      _ownsSettingsProvider = true;
    }
    _localMusicProvider = LocalMusicProvider();
    _downloaderProvider = DownloaderProvider(
      settingsProvider: _settingsProvider,
    );

    // Wire 2-way instant synchronization without ChangeNotifierProxyProvider rebuild overhead
    _localMusicProvider.onLocalLibraryMutated = _downloaderProvider.syncWithLocalLibrary;
    _downloaderProvider.onLibraryChanged = () {
      _localMusicProvider.refreshLibrary();
    };
    _downloaderProvider.onFolderCreated = (folderName) {
      _localMusicProvider.registerFolder(folderName);
    };
    _downloaderProvider.onSongSaved = (savedPath) async {
      await _localMusicProvider.upsertSingleSongByPath(savedPath);
    };
    _downloaderProvider.onEnsurePlaylist = (name) async {
      final playlist = await _localMusicProvider.ensurePlaylistNamed(name);
      return playlist.id;
    };
    _downloaderProvider.onAddToPlaylist = (playlistId, filePath) async {
      await _localMusicProvider.addSongToPlaylist(playlistId, filePath);
    };
    _downloaderProvider.onFindLocalDuplicate = (track) {
      return _localMusicProvider
          .findLocalSongByIdentity(track.title, track.artist)
          ?.filePath;
    };
    _downloaderProvider.onBeforeFileMutation = (path) {
      return _localMusicProvider.prepareForExternalFileMutation(path);
    };
    _downloaderProvider.onFileMutated = ({
      required String oldPath,
      required String newPath,
      Map<String, dynamic>? snapshot,
    }) {
      return _localMusicProvider.completeExternalFileMutation(
        oldPath: oldPath,
        newPath: newPath,
        snapshot: snapshot,
      );
    };
  }

  @override
  void dispose() {
    _localMusicProvider.dispose();
    _downloaderProvider.dispose();
    if (_ownsSettingsProvider) {
      _settingsProvider.dispose();
    }
    super.dispose();
  }

  void _applySystemUiOverlayStyle(ThemeMode mode) {
    final isLight = mode == ThemeMode.light;
    final palette = isLight ? MusEveePalette.light : MusEveePalette.dark;
    final iconBrightness = isLight ? Brightness.dark : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        systemNavigationBarColor: palette.bottomBar,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: _settingsProvider,
        ),
        ChangeNotifierProvider<LocalMusicProvider>.value(
          value: _localMusicProvider,
        ),
        ChangeNotifierProvider<DownloaderProvider>.value(
          value: _downloaderProvider,
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          _applySystemUiOverlayStyle(settings.themeMode);
          return MaterialApp(
            title: 'MusEvee',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            darkTheme: _buildDarkTheme(),
            theme: _buildLightTheme(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const p = MusEveePalette.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: p.bgCanvas,
      extensions: const <ThemeExtension<dynamic>>[MusEveePalette.dark],
      colorScheme: ColorScheme.dark(
        primary: p.accent,
        onPrimary: Colors.white,
        secondary: MusEveePalette.light.accent,
        onSecondary: Colors.white,
        surface: p.surfaceCard,
        onSurface: p.textPrimary,
        error: MusEveePalette.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBar,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: p.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: p.textMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.hairline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.hairline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.surfaceSubtle,
          disabledForegroundColor: p.textMuted,
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
          foregroundColor: p.textPrimary,
          backgroundColor: p.surfaceSubtle,
          minimumSize: const Size(44, 38),
          side: BorderSide(color: p.hairline, width: 0.8),
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
        backgroundColor: p.surfaceSubtle,
        selectedColor: p.accent,
        disabledColor: p.surfaceSubtle,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MusEveePalette.snackBarBg,
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

  ThemeData _buildLightTheme() {
    const p = MusEveePalette.light;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: p.bgCanvas,
      extensions: const <ThemeExtension<dynamic>>[MusEveePalette.light],
      colorScheme: ColorScheme.light(
        primary: p.accent,
        onPrimary: Colors.white,
        secondary: p.accent,
        onSecondary: Colors.white,
        surface: p.surfaceCard,
        onSurface: p.textPrimary,
        error: MusEveePalette.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.appBar,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: p.surfaceCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: p.textMuted, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.hairline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.hairline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.surfaceSubtle,
          disabledForegroundColor: p.textMuted,
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
          foregroundColor: p.textPrimary,
          backgroundColor: p.surfaceSubtle,
          minimumSize: const Size(44, 38),
          side: BorderSide(color: p.hairline, width: 0.8),
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
        backgroundColor: p.surfaceSubtle,
        selectedColor: p.accent,
        disabledColor: p.surfaceSubtle,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: p.hairline, width: 0.8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MusEveePalette.snackBarBg,
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
