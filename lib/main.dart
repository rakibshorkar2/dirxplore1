import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'dart:ui'; // Added for ImageFilter
import 'package:local_auth/local_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workmanager/workmanager.dart';

import 'providers/app_state.dart';
import 'providers/proxy_provider.dart';
import 'providers/download_provider.dart';
import 'providers/browser_provider.dart';
import 'services/proxy_tunnel.dart';
import 'models/download_item.dart';

import 'screens/browser_tab.dart';
import 'screens/download_tab.dart';
import 'screens/proxy_tab.dart';
import 'screens/settings_tab.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // This runs in an isolate, we need to initialize bindings again
    WidgetsFlutterBinding.ensureInitialized();

    if (task == 'autoResumeDownloads') {
      // Just a dummy initialization of DownloadProvider to trigger its queue processing
      // Since it's a new isolate, it will load SharedPreferences, see what's paused,
      // and if it was paused due to no-wifi/battery, and conditions are met now,
      // it will resume them when _processQueue is called.

      final dummyProvider = DownloadProvider();
      await dummyProvider.init();

      // Wait a bit to ensure async processing starts
      await Future.delayed(const Duration(seconds: 10));
      return true;
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit initialization failed: $e');
  }

  Workmanager().initialize(
    callbackDispatcher,
  );

  // Register the task to run periodically (e.g., every 15 mins when network is connected)
  Workmanager().registerPeriodicTask(
    "auto-resume-task",
    "autoResumeDownloads",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected, // Only run if we have network
      requiresBatteryNotLow: true, // Don't run if battery is low
    ),
  );

  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (e) {
    debugPrint('Failed to set high refresh rate: $e');
  }

  final appState = AppState();
  await appState.init();

  final proxyProvider = AppProxyProvider();
  await proxyProvider.init();

  final dlProvider = DownloadProvider();
  await dlProvider.init();
  dlProvider.setMaxConcurrent(appState.maxConcurrentDownloads);

  // Start the localhost proxy tunnel for external video players
  await ProxyTunnel().start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: proxyProvider),
        ChangeNotifierProvider.value(value: dlProvider),
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
      ],
      child: const OpenDirAppWrapper(),
    ),
  );
}

class OpenDirAppWrapper extends StatefulWidget {
  const OpenDirAppWrapper({super.key});

  @override
  State<OpenDirAppWrapper> createState() => _OpenDirAppWrapperState();
}

class _OpenDirAppWrapperState extends State<OpenDirAppWrapper> {
  @override
  void initState() {
    super.initState();
    // Initially check wakelock
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWakelock();
    });
  }

  void _updateWakelock() {
    final state = Provider.of<AppState>(context, listen: false);
    WakelockPlus.toggle(enable: state.keepScreenAwake);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes to toggle wakelock live
    final state = context.watch<AppState>();
    WakelockPlus.toggle(enable: state.keepScreenAwake);

    return const OpenDirApp();
  }
}

class OpenDirApp extends StatelessWidget {
  const OpenDirApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightScheme;
        ColorScheme darkScheme;

        if (lightDynamic != null && darkDynamic != null) {
          // On Android 12+, use Material You / Dynamic Colors
          lightScheme = lightDynamic.harmonized();
          darkScheme = darkDynamic.harmonized();
        } else {
          // Fallback to default colors
          lightScheme = ColorScheme.fromSeed(seedColor: Colors.blueAccent);
          darkScheme = ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          );
        }

        // Apply True AMOLED Black if requested
        if (appState.trueAmoledDark) {
          darkScheme = darkScheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow:
                const Color(0xFF0D1117), // Slightly lighter for containers
            surfaceContainer: const Color(0xFF161B22),
          );
        }

        return MaterialApp(
          title: 'DirXplore',
          themeMode: appState.themeMode,
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: lightScheme,
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: darkScheme,
            scaffoldBackgroundColor:
                appState.trueAmoledDark ? Colors.black : null,
            appBarTheme: AppBarTheme(
              backgroundColor: appState.trueAmoledDark ? Colors.black : null,
            ),
          ),
          home: const BiometricLockWrapper(child: MainLayout()),
        );
      },
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const BrowserTab(),
    const DownloadTab(),
    const ProxyTab(),
    const SettingsTab(),
  ];

  DateTime? _lastPressedAt;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final now = DateTime.now();
        const maxDuration = Duration(seconds: 2);
        final isWarning = _lastPressedAt == null ||
            now.difference(_lastPressedAt!) > maxDuration;

        if (isWarning) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        // Exit app
        Navigator.pop(
            context); // Optional depending on router but generally system channel is better:
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _tabs,
            ),
            const FloatingDownloadBubble(),
            _buildFloatingNavBar(context),
          ],
        ),
        bottomNavigationBar: null,
      ),
    );
  }

  Widget _buildFloatingNavBar(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 65,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(icon: Icons.explore, label: 'Browser', index: 0),
                _buildNavItem(
                    icon: Icons.download, label: 'Downloads', index: 1),
                _buildNavItem(icon: Icons.security, label: 'Proxy', index: 2),
                _buildNavItem(
                    icon: Icons.settings, label: 'Settings', index: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      {required IconData icon, required String label, required int index}) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: isSelected ? 26 : 24),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class BiometricLockWrapper extends StatefulWidget {
  final Widget child;
  const BiometricLockWrapper({super.key, required this.child});

  @override
  State<BiometricLockWrapper> createState() => _BiometricLockWrapperState();
}

class _BiometricLockWrapperState extends State<BiometricLockWrapper>
    with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.requireBiometrics && _isAuthenticated) {
        setState(() => _isAuthenticated = false);
        _checkAuth();
      }
    } else if (state == AppLifecycleState.paused) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.requireBiometrics) {
        setState(() => _isAuthenticated = false);
      }
    }
  }

  Future<void> _checkAuth() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!appState.requireBiometrics) {
      setState(() => _isAuthenticated = true);
      return;
    }

    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        setState(() => _isAuthenticated = true);
        return;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to access DirXplore',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (mounted) {
        setState(() => _isAuthenticated = didAuthenticate);
      }
    } catch (e) {
      debugPrint('Biometric Error: $e');
      if (mounted) {
        setState(
            () => _isAuthenticated = true); // Fallback to let user in if error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.requireBiometrics || _isAuthenticated) {
      return widget.child;
    }

    // Locked Screen
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 100, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text('App Locked',
                style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _checkAuth,
              child: const Text('Unlock'),
            )
          ],
        ),
      ),
    );
  }
}

class FloatingDownloadBubble extends StatelessWidget {
  const FloatingDownloadBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(builder: (context, provider, child) {
      final activeItems = provider.queue
          .where((i) => i.status == DownloadStatus.downloading)
          .toList();
      if (activeItems.isEmpty) return const SizedBox.shrink();

      final totalActive = activeItems.length;
      double totalProgress = 0;
      for (var item in activeItems) {
        totalProgress += item.progress;
      }
      final avgProgress =
          totalActive > 0 ? (totalProgress / totalActive) / 100 : 0.0;

      return Positioned(
        bottom: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            customBorder: const CircleBorder(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4))
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: avgProgress,
                      backgroundColor: Colors.transparent,
                      color: Theme.of(context).colorScheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                  const Icon(Icons.downloading, size: 28),
                  if (totalActive > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$totalActive',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
