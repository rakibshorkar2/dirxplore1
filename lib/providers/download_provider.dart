import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../models/download_item.dart';
import '../services/dio_client.dart';
import '../services/html_parser.dart';

class DownloadProvider with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.example.nexus/downloads');
  final List<DownloadItem> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  int _maxConcurrent = 3;
  int _activeCount = 0;

  // Selection State
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  List<DownloadItem> get queue => _queue;
  Set<String> get selectedIds => _selectedIds;
  bool get isSelectionMode => _isSelectionMode;

  Future<void> init() async {
    await _loadQueue();
    _channel.setMethodCallHandler(_handleNotificationAction);
  }

  Future<void> _handleNotificationAction(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final String action = call.arguments['action'];
      // final int notificationId = call.arguments['id']; // Unused for now as we use fixed ID 1001

      // For now, we assume 1001 is the active download.
      // In a multi-notification setup, we'd map notificationId to download ID.
      // Since currently startForegroundService uses a fixed ID 1001:
      final activeItem = _queue.firstWhere(
        (i) => i.status == DownloadStatus.downloading,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
      );

      if (activeItem.id.isNotEmpty) {
        if (action == 'pause') {
          pause(activeItem.id);
        } else if (action == 'resume') {
          resume(activeItem.id);
        } else if (action == 'cancel') {
          stop(activeItem.id);
        }
      }
    }
  }

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('download_queue');
    if (jsonStr != null) {
      final List<dynamic> list = jsonDecode(jsonStr);
      _queue.clear();
      _queue.addAll(list.map((item) => DownloadItem.fromJson(item)).toList());
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_queue.map((item) => item.toJson()).toList());
    await prefs.setString('download_queue', jsonStr);
  }

  void setMaxConcurrent(int max) {
    _maxConcurrent = max;
    _processQueue();
  }

  Future<void> addDownload(String url, String fileName, String saveDir,
      {String? batchId, String? batchName}) async {
    // Check if exactly identical item exists in queue
    if (_queue.any((i) => i.url == url)) {
      final existing = _queue.firstWhere((i) => i.url == url);
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.error) {
        resume(existing.id);
      }
      return;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}';

    // Apply Smart Folder Routing if enabled
    String finalSaveDir = saveDir;
    final prefs = await SharedPreferences.getInstance();
    final bool smartRouting = prefs.getBool('smartFolderRouting') ?? false;

    if (smartRouting) {
      final ext = fileName.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Movies');
      } else if (['iso', 'rar', 'zip', '7z'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Games');
      } else if (['apk'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Apps');
      } else if (['mp3', 'flac', 'wav'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Music');
      } else {
        finalSaveDir = p.join(saveDir, 'Others');
      }
    }

    final savePath = p.join(finalSaveDir, fileName);

    _queue.add(DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      batchId: batchId,
      batchName: batchName,
    ));

    _saveQueue();
    notifyListeners();
    _processQueue();
  }

  void addRecursiveDownload(
      String folderUrl, String folderName, String baseSaveDir) {
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    _crawlAndQueue(
        folderUrl, p.join(baseSaveDir, folderName), batchId, folderName);
  }

  Future<void> _crawlAndQueue(String folderUrl, String targetDir,
      String batchId, String batchName) async {
    try {
      final dio = DioClient().dio;
      final response = await dio.get(folderUrl);
      final htmlStr = response.data.toString();
      final items =
          await HtmlParserService.parseApacheDirectoryAsync(htmlStr, folderUrl);

      for (var item in items) {
        if (item.isDirectory) {
          await _crawlAndQueue(
              item.url, p.join(targetDir, item.name), batchId, batchName);
        } else {
          // Filter to only download movies and subtitles automatically
          final ext = item.name.split('.').last.toLowerCase();
          const allowedExtensions = [
            'mp4',
            'mkv',
            'avi',
            'mov',
            'webm',
            'srt',
            'vtt',
            'sub'
          ];
          if (allowedExtensions.contains(ext)) {
            addDownload(item.url, item.name, targetDir,
                batchId: batchId, batchName: batchName);
          }
        }
      }
    } catch (e) {
      debugPrint("Error crawling $folderUrl: $e");
    }
  }

  void pause(String id) {
    _cancelTokens[id]?.cancel('Paused by user');
    _cancelTokens.remove(id);

    final item = _queue.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.paused;
    item.speedBytesPerSec = 0;

    // Stop foreground service if this was the last active
    _stopForegroundIfNoActive();

    _activeCount--;
    _saveQueue();
    notifyListeners();
    _processQueue();
  }

  void _stopForegroundIfNoActive() {
    if (_activeCount <= 1) {
      // 1 because we are about to decrement
      _channel.invokeMethod(
          'stopForegroundService', {'id': 1001}).catchError((_) {});
    }
  }

  void resume(String id) {
    final item = _queue.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.queued;
    item.errorMessage = null;
    _saveQueue();
    notifyListeners();
    _processQueue();
  }

  void stop(String id) {
    _cancelTokens[id]?.cancel('Stopped by user');
    _cancelTokens.remove(id);
    _queue.removeWhere((i) => i.id == id);
    if (_activeCount > 0) {
      _stopForegroundIfNoActive();
      _activeCount--;
    }
    _saveQueue();
    notifyListeners();
    _processQueue();
  }

  void clearDone() {
    _queue.removeWhere((i) =>
        i.status == DownloadStatus.done || i.status == DownloadStatus.error);
    _saveQueue();
    notifyListeners();
  }

  void clearAll() {
    for (final token in _cancelTokens.values) {
      token.cancel('Cleared');
    }
    _cancelTokens.clear();
    _queue.clear();
    _activeCount = 0;
    _isSelectionMode = false;
    _selectedIds.clear();
    _saveQueue();
    notifyListeners();
  }

  // --- Selection Features ---

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.clear();
    _selectedIds.addAll(_queue.map((e) => e.id));
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  void deleteSelected({bool deleteFiles = false}) {
    for (String id in _selectedIds) {
      _cancelTokens[id]?.cancel('Deleted by user');
      _cancelTokens.remove(id);

      if (deleteFiles) {
        final itemIndex = _queue.indexWhere((i) => i.id == id);
        if (itemIndex != -1) {
          final f = File(_queue[itemIndex].savePath);
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      }

      _queue.removeWhere((i) => i.id == id);
    }

    // Recalculate active count if we deleted running items
    _activeCount =
        _queue.where((i) => i.status == DownloadStatus.downloading).length;
    if (_activeCount == 0) {
      _stopForegroundIfNoActive();
    }

    _selectedIds.clear();
    _isSelectionMode = false;
    _saveQueue();
    notifyListeners();
    _processQueue();
  }

  void pauseAll() {
    // 1. Cancel all active transfers
    for (final id in _cancelTokens.keys.toList()) {
      _cancelTokens[id]?.cancel('Paused by user');
      _cancelTokens.remove(id);
    }

    // 2. Set all queued items to paused
    for (final item in _queue) {
      if (item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.paused;
        item.speedBytesPerSec = 0;
      }
    }

    _activeCount = 0;
    _stopForegroundIfNoActive();
    _saveQueue();
    notifyListeners();
  }

  void resumeAll() {
    for (final item in _queue) {
      if (item.status == DownloadStatus.paused ||
          item.status == DownloadStatus.error) {
        resume(item.id);
      }
    }
  }

  Future<void> _processQueue() async {
    while (_activeCount < _maxConcurrent) {
      final nextItem = _queue.firstWhere(
        (i) => i.status == DownloadStatus.queued,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
      );

      if (nextItem.id.isEmpty) break; // Nothing to download

      // Check Smart Conditions before starting
      final prefs = await SharedPreferences.getInstance();

      // 1. Wi-Fi Check
      if (prefs.getBool('downloadOnWifiOnly') == true) {
        var connectivityResult = await (Connectivity().checkConnectivity());
        if (!connectivityResult.contains(ConnectivityResult.wifi)) {
          // Pause it automatically
          nextItem.status = DownloadStatus.paused;
          nextItem.errorMessage = 'Paused: Waiting for Wi-Fi';
          _saveQueue();
          notifyListeners();
          continue; // Skips to next item
        }
      }

      // 2. Battery Check
      if (prefs.getBool('pauseLowBattery') == true) {
        final battery = Battery();
        final level = await battery.batteryLevel;
        if (level < 15) {
          nextItem.status = DownloadStatus.paused;
          nextItem.errorMessage = 'Paused: Battery below 15%';
          _saveQueue();
          notifyListeners();
          continue;
        }
      }

      _startDownload(nextItem);
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    _activeCount++;
    item.status = DownloadStatus.downloading;
    notifyListeners();

    // Start Foreground Service
    _channel.invokeMethod('startForegroundService', {
      'url': item.url,
      'filename': item.fileName,
      'id': 1001, // Use non-zero ID for Android foreground service compliance
    }).catchError((_) {});

    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    final file = File(item.savePath);
    int existingBytes = 0;

    if (await file.exists()) {
      existingBytes = await file.length();
    }

    item.downloadedBytes = existingBytes;

    DateTime lastUpdate = DateTime.now();
    int bytesSinceLastUpdate = 0;

    try {
      final dio = DioClient().dio;

      final response = await dio.get<ResponseBody>(
        item.url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers:
              existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
        ),
      );

      final totalHeader =
          response.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
      final total = int.tryParse(totalHeader) ?? -1;

      if (response.statusCode == 416) {
        // Server responded Range Not Satisfiable: We already have the complete file!
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = existingBytes;
        item.totalBytes = existingBytes;
        _cancelTokens.remove(item.id);
        return; // finally block will cleanup concurrency
      }

      if (total != -1) {
        if (response.statusCode == 206) {
          item.totalBytes = existingBytes + total;
        } else {
          // Server ignored range request
          item.totalBytes = total;
          existingBytes = 0; // The file will be overwritten
        }
      }

      final dir = Directory(p.dirname(item.savePath));
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          // OS Error: A file exists with the exact same name as the target directory.
          // This happens if the user clicked the folder "as a file" before updates.
          final fileInWay = File(dir.path);
          if (await fileInWay.exists()) {
            await fileInWay.delete();
            await dir.create(recursive: true);
          } else {
            rethrow;
          }
        }
      }

      final raf = file.openSync(
          mode: existingBytes > 0 && response.statusCode == 206
              ? FileMode.append
              : FileMode.write);
      final stream = response.data!.stream;
      final completer = Completer<void>();
      late StreamSubscription subscription;

      subscription = stream.listen(
        (chunk) async {
          // Make it async to allow delay for throttling
          if (cancelToken.isCancelled) {
            subscription.cancel();
            raf.closeSync();
            if (!completer.isCompleted) {
              completer.completeError(
                  DioException.requestCancelled(
                      requestOptions: response.requestOptions,
                      reason: "Cancelled"),
                  StackTrace.current);
            }
            return;
          }
          try {
            // ----------------- SPEED LIMITER THROTTLING -----------------
            final prefs = await SharedPreferences.getInstance();
            final speedLimitCapKB = prefs.getInt('speedLimitCap') ?? 0;
            if (speedLimitCapKB > 0) {
              // If limit is active, calculate how long downloading this chunk SHOULD take
              // chunk.length is bytes. speedLimitCapKB is kilobytes.
              final targetMillisForChunk =
                  (chunk.length / (speedLimitCapKB * 1024)) * 1000;

              // Track time manually for this small chunk
              // If we downloaded it way faster than targetMillisForChunk, sleep to throttle.
              // Simple naive sleep for the whole duration since last block (real algorithm would track moving average)
              await Future.delayed(
                  Duration(milliseconds: targetMillisForChunk.toInt()));
            }
            // -------------------------------------------------------------

            raf.writeFromSync(chunk);
            item.downloadedBytes += chunk.length;
            bytesSinceLastUpdate += chunk.length;

            final now = DateTime.now();
            final diff = now.difference(lastUpdate).inMilliseconds;

            if (diff > 1000) {
              item.speedBytesPerSec =
                  (bytesSinceLastUpdate / (diff / 1000)).toDouble();
              if (item.speedBytesPerSec > 0 && item.totalBytes > 0) {
                final remaining = item.totalBytes - item.downloadedBytes;
                item.etaSeconds = (remaining / item.speedBytesPerSec).round();
              }

              int progressPercent = 0;
              if (item.totalBytes > 0) {
                progressPercent =
                    ((item.downloadedBytes / item.totalBytes) * 100).toInt();
              }
              _channel.invokeMethod('updateProgress', {
                'id': 1001,
                'progress': progressPercent,
                'speed':
                    '${(item.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
                'filename': item.fileName,
              }).catchError((_) {});

              lastUpdate = now;
              bytesSinceLastUpdate = 0;
              notifyListeners();
            }
          } catch (e) {
            subscription.cancel();
            raf.closeSync();
            if (!completer.isCompleted) {
              completer.completeError(e, StackTrace.current);
            }
          }
        },
        onDone: () {
          raf.closeSync();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e, st) {
          raf.closeSync();
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        cancelOnError: true,
      );

      await completer.future;

      item.status = DownloadStatus.done;
      item.speedBytesPerSec = 0;
      item.etaSeconds = 0;
      item.downloadedBytes = item.totalBytes;
      _cancelTokens.remove(item.id);
      _saveQueue();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Paused intentionally, status already updated
      } else if (e.response?.statusCode == 416) {
        // Catches strictly HTTP 416 Range Not Satisfiable inside Dio validation exceptions
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes =
            item.totalBytes > 0 ? item.totalBytes : existingBytes;
        _cancelTokens.remove(item.id);
        _saveQueue();
      } else {
        if (item.retryCount < 3) {
          item.retryCount++;
          item.status = DownloadStatus.queued;
        } else {
          item.status = DownloadStatus.error;
          item.errorMessage = e.message;
        }
        _cancelTokens.remove(item.id);
        _saveQueue();
      }
    } catch (e) {
      item.status = DownloadStatus.error;
      item.errorMessage = e.toString();
      _cancelTokens.remove(item.id);
      _saveQueue();
    } finally {
      if (_activeCount > 0) {
        _stopForegroundIfNoActive();
        _activeCount--;
      }
      _saveQueue();
      notifyListeners();
      _processQueue();
      _processQueue();
    }
  }

  // --- Integrity Checker (Isolate) ---
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    expectedHash = expectedHash.trim().toLowerCase();
    if (expectedHash.isEmpty) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // Use Isolate to prevent UI freezing on multi-GB files
      final String calculatedHash = await Isolate.run(() async {
        final f = File(filePath);
        // Determine algorithm by length
        // We use ProxySink because startChunkedConversion expects a Sink<Digest>, but we just want the final value.
        // Actually, crypto's cleaner way in an isolate:
        final stream = f.openRead();
        if (expectedHash.length == 32) {
          final digest = await md5.bind(stream).first;
          return digest.toString();
        } else {
          final digest = await sha256.bind(stream).first;
          return digest.toString();
        }
      });

      return calculatedHash.toLowerCase() == expectedHash;
    } catch (e) {
      debugPrint('Hash verification error: $e');
      return false;
    }
  }

  // --- Export / Import Queue ---
  Future<void> exportQueue() async {
    try {
      final jsonStr = jsonEncode(_queue.map((item) => item.toJson()).toList());
      // Create a temporary file
      final directory = Directory.systemTemp;
      final file = File(p.join(directory.path, 'dirxplore_queue_backup.json'));
      await file.writeAsString(jsonStr);

      // Share it
      await Share.shareXFiles([XFile(file.path)],
          text: 'DirXplore Download Queue Backup');
    } catch (e) {
      debugPrint('Export error: $e');
    }
  }

  Future<bool> importQueue() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonStr = await file.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr);

        // Merge with existing queue or replace? Let's merge (avoiding duplicates by URL)
        int importedCount = 0;
        for (var itemJson in list) {
          final newItem = DownloadItem.fromJson(itemJson);
          if (!_queue.any((i) => i.url == newItem.url)) {
            // Reset status of imported items that were downloading/queued to paused
            // so they don't all start at once unexpectedly.
            if (newItem.status == DownloadStatus.downloading ||
                newItem.status == DownloadStatus.queued) {
              newItem.status = DownloadStatus.paused;
              newItem.speedBytesPerSec = 0;
            }
            _queue.add(newItem);
            importedCount++;
          }
        }

        if (importedCount > 0) {
          _saveQueue();
          notifyListeners();
          _processQueue();
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Import error: $e');
      return false;
    }
  }
}

// Helper for older dart runtimes if bind() isn't available, but bind() is standard.
class ProxySink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}
