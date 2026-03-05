import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppState with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _defaultSavePath = '/storage/emulated/0/Download/DirXplore';
  int _maxConcurrentDownloads = 1;
  String _appVersion = 'Unknown';
  bool _initialized = false;

  // Added Phase 1-4 Toggles
  bool _trueAmoledDark = false;
  bool _showDownloadNotifications = true;
  int _speedLimitCap = 0; // 0 means no limit (in KB/s)
  bool _keepScreenAwake = false;
  bool _smartFolderRouting = false;
  bool _downloadOnWifiOnly = false;
  bool _pauseLowBattery = false;
  bool _requireBiometrics = false;

  ThemeMode get themeMode => _themeMode;
  String get defaultSavePath => _defaultSavePath;
  int get maxConcurrentDownloads => _maxConcurrentDownloads;
  String get appVersion => _appVersion;
  bool get isInitialized => _initialized;

  // Added Getters
  bool get trueAmoledDark => _trueAmoledDark;
  bool get showDownloadNotifications => _showDownloadNotifications;
  int get speedLimitCap => _speedLimitCap;
  bool get keepScreenAwake => _keepScreenAwake;
  bool get smartFolderRouting => _smartFolderRouting;
  bool get downloadOnWifiOnly => _downloadOnWifiOnly;
  bool get pauseLowBattery => _pauseLowBattery;
  bool get requireBiometrics => _requireBiometrics;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Theme
    final tIdx = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[tIdx];

    // Load Settings
    _defaultSavePath =
        prefs.getString('savePath') ?? '/storage/emulated/0/Download/DirXplore';
    _maxConcurrentDownloads = prefs.getInt('maxConcurrent') ?? 1;

    // Load Added Feature Toggles
    _trueAmoledDark = prefs.getBool('trueAmoledDark') ?? false;
    _showDownloadNotifications =
        prefs.getBool('showDownloadNotifications') ?? true;
    _speedLimitCap = prefs.getInt('speedLimitCap') ?? 0;
    _keepScreenAwake = prefs.getBool('keepScreenAwake') ?? false;
    _smartFolderRouting = prefs.getBool('smartFolderRouting') ?? false;
    _downloadOnWifiOnly = prefs.getBool('downloadOnWifiOnly') ?? false;
    _pauseLowBattery = prefs.getBool('pauseLowBattery') ?? false;
    _requireBiometrics = prefs.getBool('requireBiometrics') ?? false;

    // Load App Version
    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;

    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setDefaultSavePath(String path) async {
    _defaultSavePath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('savePath', path);
  }

  Future<void> setMaxConcurrentDownloads(int max) async {
    _maxConcurrentDownloads = max;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxConcurrent', max);
  }

  // --- Added Setters ---

  Future<void> setTrueAmoledDark(bool val) async {
    _trueAmoledDark = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trueAmoledDark', val);
  }

  Future<void> setShowDownloadNotifications(bool val) async {
    _showDownloadNotifications = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showDownloadNotifications', val);
  }

  Future<void> setSpeedLimitCap(int val) async {
    _speedLimitCap = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speedLimitCap', val);
  }

  Future<void> setKeepScreenAwake(bool val) async {
    _keepScreenAwake = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keepScreenAwake', val);
  }

  Future<void> setSmartFolderRouting(bool val) async {
    _smartFolderRouting = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smartFolderRouting', val);
  }

  Future<void> setDownloadOnWifiOnly(bool val) async {
    _downloadOnWifiOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloadOnWifiOnly', val);
  }

  Future<void> setPauseLowBattery(bool val) async {
    _pauseLowBattery = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pauseLowBattery', val);
  }

  Future<void> setRequireBiometrics(bool val) async {
    _requireBiometrics = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('requireBiometrics', val);
  }
}
