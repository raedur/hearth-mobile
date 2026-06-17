import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/wiki_screen.dart';
import 'package:native_geofence/native_geofence.dart';

import 'services/auth_service.dart';
import 'services/geofence_service.dart';
import 'services/trigger_notifications.dart';
import 'widgets/flame_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Geofence init doesn't need to block the first frame
  unawaited(
    NativeGeofenceManager.instance.initialize()
        .then((_) => GeofenceService().reRegisterAfterReboot())
        .catchError((_) {}),
  );
  runApp(const HearthApp());
}

class HearthApp extends StatelessWidget {
  const HearthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hearth',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const AuthGate(),
    );
  }

  ThemeData _buildTheme() {
    // Dark theme matching hearth-core landing page colour palette
    const bg = Color(0xFF0D0D0D);
    const surface = Color(0xFF111111);
    const amber = Color(0xFFC2731E);
    const amberLight = Color(0xFFF97316);
    const textPrimary = Color(0xFFE8E4DF);
    const textMuted = Color(0xFF6B6460);
    const borderColor = Color(0xFF1E1E1E);

    final colorScheme = ColorScheme.dark(
      primary: amber,
      onPrimary: Colors.white,
      secondary: amberLight,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: const Color(0xFF1A1A1A),
      outline: borderColor,
      error: const Color(0xFFCF6679),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: amber.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: amberLight);
          }
          return const IconThemeData(color: textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: amberLight, fontSize: 12);
          }
          return const TextStyle(color: textMuted, fontSize: 12);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: amber),
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textMuted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderColor),
        ),
      ),
      dividerColor: borderColor,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w400),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: textMuted),
        bodySmall: TextStyle(color: textMuted),
        labelSmall: TextStyle(color: textMuted, letterSpacing: 0.05),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  bool _checking = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final ok = await _auth.hasValidToken();
    if (mounted) {
      setState(() {
        _authenticated = ok;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authenticated) {
      return LoginScreen(
        onAuthenticated: () => setState(() => _authenticated = true),
      );
    }

    return MainShell(onSignedOut: () => setState(() => _authenticated = false));
  }
}

class MainShell extends StatefulWidget {
  final VoidCallback onSignedOut;
  const MainShell({super.key, required this.onSignedOut});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Request notification permission after login on both Android 13+ and iOS
    requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const WikiScreen(),
      SettingsScreen(onSignedOut: widget.onSignedOut),
    ];

    final titles = ['Wiki', 'Settings'];

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: FlameLogo(size: 28),
        ),
        title: Text(titles[_selectedIndex]),
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Wiki',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
