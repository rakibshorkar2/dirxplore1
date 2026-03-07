import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import '../providers/app_state.dart';
import '../services/github_updater.dart';
import 'security_setup_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background gradient or image could go here
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: appState.trueAmoledDark &&
                        Theme.of(context).brightness == Brightness.dark
                    ? Colors.black
                    : null,
                gradient: appState.trueAmoledDark &&
                        Theme.of(context).brightness == Brightness.dark
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.8),
                        ],
                      ),
              ),
            ),
          ),
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
              bottom: 120,
            ),
            children: [
              _buildGlassSection(
                context,
                'UI & APPEARANCE',
                [
                  _buildGlassTile(
                    title: const Text('Theme'),
                    trailing: DropdownButton<ThemeMode>(
                      value: appState.themeMode,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: ThemeMode.system, child: Text('System')),
                        DropdownMenuItem(
                            value: ThemeMode.light, child: Text('Light')),
                        DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Material Dark')),
                      ],
                      onChanged: (val) {
                        if (val != null) appState.setThemeMode(val);
                      },
                    ),
                  ),
                  _buildGlassSwitchTile(
                    title: 'True AMOLED Black',
                    subtitle: 'Pure black background for OLED screens',
                    value: appState.trueAmoledDark,
                    onChanged: (val) => appState.setTrueAmoledDark(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'DOWNLOAD SETTINGS',
                [
                  _buildGlassTile(
                    title: const Text('Default Save Directory'),
                    subtitle: Text(appState.defaultSavePath,
                        style: const TextStyle(fontSize: 10)),
                    trailing: IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        String? selectedDirectory =
                            await FilePicker.platform.getDirectoryPath();
                        if (selectedDirectory != null) {
                          appState.setDefaultSavePath(selectedDirectory);
                        }
                      },
                    ),
                  ),
                  _buildGlassTile(
                    title: const Text('Max Concurrent Downloads'),
                    subtitle: Text(
                        '${appState.maxConcurrentDownloads} files at once'),
                    trailing: DropdownButton<int>(
                      value: appState.maxConcurrentDownloads,
                      underline: const SizedBox(),
                      items: [1, 2, 3, 4, 5, 10]
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(e.toString())))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          appState.setMaxConcurrentDownloads(val);
                        }
                      },
                    ),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Show Download Notifications',
                    subtitle: 'Display progress in notification panel',
                    value: appState.showDownloadNotifications,
                    onChanged: (val) =>
                        appState.setShowDownloadNotifications(val),
                  ),
                  _buildGlassTile(
                    title: const Text('Speed Limiter (Per Download)'),
                    subtitle: appState.speedLimitCap == 0
                        ? const Text('Unlimited')
                        : Text('${appState.speedLimitCap} KB/s'),
                    trailing: SizedBox(
                      width: 120,
                      child: Slider(
                        value: appState.speedLimitCap.toDouble(),
                        min: 0,
                        max: 10000,
                        divisions: 20,
                        onChanged: (val) =>
                            appState.setSpeedLimitCap(val.toInt()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'SMART AUTOMATION',
                [
                  _buildGlassSwitchTile(
                    title: 'Smart Folder Routing',
                    subtitle: 'Auto-sort by extension',
                    value: appState.smartFolderRouting,
                    onChanged: (val) => appState.setSmartFolderRouting(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Download on Wi-Fi Only',
                    value: appState.downloadOnWifiOnly,
                    onChanged: (val) => appState.setDownloadOnWifiOnly(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Pause If Battery < 15%',
                    value: appState.pauseLowBattery,
                    onChanged: (val) => appState.setPauseLowBattery(val),
                  ),
                  _buildGlassSwitchTile(
                    title: 'Keep Screen Awake',
                    subtitle: 'Prevent sleep while downloading',
                    value: appState.keepScreenAwake,
                    onChanged: (val) => appState.setKeepScreenAwake(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'SECURITY & PRIVACY',
                [
                  _buildGlassTile(
                    title: const Text('App Lock Type'),
                    subtitle: Text(appState.lockType == 'none'
                        ? 'Disabled'
                        : appState.lockType == 'device'
                            ? 'Device (Fingerprint/PIN/Pattern)'
                            : 'Custom App PIN'),
                    trailing: DropdownButton<String>(
                      value: appState.lockType,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('None')),
                        DropdownMenuItem(
                            value: 'device', child: Text('Device')),
                        DropdownMenuItem(
                            value: 'custom', child: Text('Custom PIN')),
                      ],
                      onChanged: (val) {
                        if (val == 'custom' && appState.customPinHash.isEmpty) {
                          _showSecuritySetup(context);
                        } else {
                          if (val != null) appState.setLockType(val);
                        }
                      },
                    ),
                  ),
                  _buildGlassTile(
                    title: const Text('Inactivity Auto-Lock'),
                    subtitle: Text(appState.autoLockSeconds == 0
                        ? 'Immediate'
                        : appState.autoLockSeconds == 30
                            ? '30 Seconds'
                            : '${appState.autoLockSeconds ~/ 60} Minute(s)'),
                    trailing: DropdownButton<int>(
                      value: appState.autoLockSeconds,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Immediate')),
                        DropdownMenuItem(value: 30, child: Text('30s')),
                        DropdownMenuItem(value: 60, child: Text('1m')),
                        DropdownMenuItem(value: 120, child: Text('2m')),
                      ],
                      onChanged: (val) {
                        if (val != null) appState.setAutoLockSeconds(val);
                      },
                    ),
                  ),
                  if (appState.lockType == 'custom')
                    _buildGlassTile(
                      title: const Text('Configure Custom PIN'),
                      subtitle: const Text('Change PIN or security question'),
                      leading: const Icon(Icons.security),
                      onTap: () => _showSecuritySetup(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _buildGlassSection(
                context,
                'ABOUT',
                [
                  _buildGlassTile(
                    title: const Text('Version'),
                    subtitle: Text(appState.appVersion),
                  ),
                  _buildGlassTile(
                    title: const Text('Check for Updates'),
                    subtitle: const Text('Check GitHub for new releases'),
                    leading: const Icon(Icons.system_update),
                    onTap: () => _checkForUpdates(context),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Center(
                child: Text(
                  'Created by RAKIB',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          // Blurred Header Container
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: MediaQuery.of(context).padding.top + kToolbarHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.8),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSection(
      BuildContext context, String title, List<Widget> children) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12)),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.15), // Optimized "Faux Glass"
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassTile({
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildGlassSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  void _checkForUpdates(BuildContext context) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
                content: Row(children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Checking GitHub...'),
            ])));

    final updateInfo = await GithubUpdater.checkUpdate();
    if (context.mounted) {
      Navigator.pop(context);
    }

    if (updateInfo != null) {
      if (context.mounted) {
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: Text('Update Available: ${updateInfo.version}'),
                  content: SingleChildScrollView(
                    child: Text(updateInfo.releaseNotes ?? 'No release notes.'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Later')),
                    ElevatedButton(
                      onPressed: () {
                        launchUrl(Uri.parse(updateInfo.downloadUrl),
                            mode: LaunchMode.externalApplication);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Download APK'),
                    )
                  ],
                ));
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are on the latest version!')),
        );
      }
    }
  }

  void _showSecuritySetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SecuritySetupScreen()),
    );
  }
}
