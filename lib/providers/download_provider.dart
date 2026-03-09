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
import 'package:disk_space_2/disk_space_2.dart';
import '../models/download_item.dart';
import '../services/dio_client.dart';
import '../services/html_parser.dart';
import '../services/database_helper.dart';
import '../models/directory_item.dart';

class DownloadProvider with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.example.nexus/downloads');
  final List<DownloadItem> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  int _maxConcurrent = 3;
  int _activeCount = 0;
  DateTime _lastNotifyTime = DateTime.now();
  DateTime _lastSaveTime = DateTime.now();
  double _totalStorage = 0;
  double _freeStorage = 0;
  bool _isProcessingQueue = false;

  double get totalStorage => _totalStorage;
  double get freeStorage => _freeStorage;

  Future<void> updateStorageInfo() async {
    try {
      _totalStorage = await DiskSpace.getTotalDiskSpace ?? 0;
      _freeStorage = await DiskSpace.getFreeDiskSpace ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Storage update error: $e');
    }
  }

  // Selection State
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  List<DownloadItem> get queue => _queue;
  Set<String> get selectedIds => _selectedIds;
  bool get isSelectionMode => _isSelectionMode;

  Future<void> init() async {
    await _loadQueue();
    await updateStorageInfo();
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
    _queue.clear();
    _queue.addAll(await DatabaseHelper().getDownloads());
    notifyListeners();
    _processQueue();
  }

  Future<void> _saveQueue() async {
    // With SQLite, we update items individually.
    // This method can remain as a legacy call or trigger bulk sync if needed.
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

    // NEW: Create subfolder if batchName is provided
    if (batchName != null && batchName.trim().isNotEmpty) {
      finalSaveDir = p.join(finalSaveDir, batchName.trim());
    }

    final savePath = p.join(finalSaveDir, fileName);

    // Resume logic: if file already exists on disk (even if not in queue),
    // we want to attempt resuming. Wait, addDownload just adds to queue.
    // We will handle existing bytes in `_startDownload` where we actually check the disk.

    _queue.add(DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      batchId: batchId,
      batchName: batchName,
    ));

    await DatabaseHelper().insertDownload(_queue.last);
    await updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  Future<List<DirectoryItem>> crawlFolder(
      String folderUrl, String folderName) async {
    final List<DirectoryItem> allItems = [];
    await _crawlRecursive(folderUrl, allItems);
    return allItems;
  }

  Future<void> _crawlRecursive(
      String folderUrl, List<DirectoryItem> results) async {
    try {
      final dio = DioClient().dio;
      final response = await dio.get(folderUrl);
      final htmlStr = response.data.toString();
      final items =
          await HtmlParserService.parseApacheDirectoryAsync(htmlStr, folderUrl);

      for (var item in items) {
        if (item.isDirectory) {
          await _crawlRecursive(item.url, results);
        } else {
          results.add(item);
        }
      }
    } catch (e) {
      debugPrint("Crawl error: $e");
    }
  }

  void addRecursiveDownload(
      String folderUrl, String folderName, String baseSaveDir) async {
    // Legacy support: auto-queueing movies/subs
    final items = await crawlFolder(folderUrl, folderName);
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    for (var item in items) {
      final ext = item.name.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'srt', 'vtt', 'sub']
          .contains(ext)) {
        addDownload(item.url, item.name, baseSaveDir,
            batchId: batchId, batchName: folderName);
      }
    }
  }

  void pause(String id) {
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Paused by user');
      _cancelTokens.remove(id);
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      notifyListeners();
      // _startDownload's finally block will handle _activeCount--, saving, and _processQueue()
    } else {
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      _saveQueue();
      updateStorageInfo();
      notifyListeners();
    }
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
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      _cancelTokens[id]?.cancel('Stopped by user');
      _cancelTokens.remove(id);
      // Let the finally block handle _activeCount-- gracefully
    }

    _queue.removeWhere((i) => i.id == id);
    DatabaseHelper().deleteDownload(id);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
  }

  void resumeBatch(String batchId) {
    bool hasResumed = false;
    for (var i in _queue) {
      if (i.batchId == batchId &&
          (i.status == DownloadStatus.paused ||
              i.status == DownloadStatus.error)) {
        i.status = DownloadStatus.queued;
        i.errorMessage = null;
        DatabaseHelper().updateDownload(i);
        hasResumed = true;
      }
    }
    if (hasResumed) {
      _saveQueue();
      notifyListeners();
      _processQueue();
    }
  }

  void pauseBatch(String batchId) {
    bool hasPaused = false;
    for (var i in _queue) {
      if (i.batchId == batchId) {
        if (i.status == DownloadStatus.downloading) {
          _cancelTokens[i.id]?.cancel('Paused by user');
          _cancelTokens.remove(i.id);
          i.status = DownloadStatus.paused;
          i.speedBytesPerSec = 0;
          hasPaused = true;
        } else if (i.status == DownloadStatus.queued) {
          i.status = DownloadStatus.paused;
          hasPaused = true;
        }
        DatabaseHelper().updateDownload(i);
      }
    }
    if (hasPaused) {
      _saveQueue();
      notifyListeners();
    }
  }

  void stopBatch(String batchId) {
    final batchItems = _queue.where((i) => i.batchId == batchId).toList();
    for (var i in batchItems) {
      if (i.status == DownloadStatus.downloading) {
        _cancelTokens[i.id]?.cancel('Stopped by user');
        _cancelTokens.remove(i.id);
      }
      DatabaseHelper().deleteDownload(i.id);
    }
    _queue.removeWhere((i) => i.batchId == batchId);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
  }

  void clearDone() {
    _queue.removeWhere((i) =>
        i.status == DownloadStatus.done || i.status == DownloadStatus.error);
    _saveQueue();
    updateStorageInfo();
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
    updateStorageInfo();
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
    updateStorageInfo();
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
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final wifiOnly = prefs.getBool('downloadOnWifiOnly') == true;
      final lowBatteryPause = prefs.getBool('pauseLowBattery') == true;
      _maxConcurrent = prefs.getInt('maxConcurrent') ?? 1;

      while (_activeCount < _maxConcurrent) {
        final nextItem = _queue.firstWhere(
          (i) => i.status == DownloadStatus.queued,
          orElse: () =>
              DownloadItem(id: '', url: '', fileName: '', savePath: ''),
        );

        if (nextItem.id.isEmpty) break; // Nothing to download

        // 1. Wi-Fi Check
        if (wifiOnly) {
          var connectivityResult = await (Connectivity().checkConnectivity());
          if (!connectivityResult.contains(ConnectivityResult.wifi)) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Waiting for Wi-Fi';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        // 2. Battery Check
        if (lowBatteryPause) {
          final battery = Battery();
          final level = await battery.batteryLevel;
          if (level < 15) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Battery below 15%';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        _startDownload(nextItem);
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    _activeCount++;
    item.status = DownloadStatus.downloading;
    notifyListeners();
    await DatabaseHelper().updateDownload(item);

    // Start Foreground Service
    _channel.invokeMethod('startForegroundService', {
      'url': item.url,
      'filename': item.fileName,
      'id': 1001,
    }).catchError((_) {});

    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    final file = File(item.savePath);
    // Ensure parent directory exists for organized downloads
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // TRUST PERSISTED PROGRESS: file.length() is unreliable due to pre-allocation
    // Actually, if file exists and we are starting, we can check its size to resume.
    if (!await file.exists()) {
      item.downloadedBytes = 0;
    } else {
      // If the file exists but downloadedBytes in queue is 0 (e.g., added a new link for an existing file),
      // we check the file size on disk and use it to resume.
      if (item.downloadedBytes == 0) {
        item.downloadedBytes = await file.length();
      }
    }
    int existingBytes = item.downloadedBytes;

    try {
      final dio = DioClient().dio;
      final headResponse = await dio.head(item.url);
      final totalHeader =
          headResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
      final total = int.tryParse(totalHeader) ?? -1;
      item.totalBytes = total;

      // Check if already fully downloaded based on disk size
      if (existingBytes > 0 && total > 0 && existingBytes >= total) {
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = total;
        item.totalBytes = total;
        _cancelTokens.remove(item.id);
        await updateStorageInfo();

        _channel.invokeMethod('stopForegroundService', {
          'id': 1001,
          'filename': item.fileName,
          'success': true,
        }).catchError((_) {});

        // Finalize state
        if (_activeCount > 0) {
          _stopForegroundIfNoActive();
          _activeCount--;
        }
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return; // Early return for completed file
      }

      // --- NATIVE DISK PRE-ALLOCATION ---
      // Disabled to ensure file size on disk matches actual downloaded bytes
      // if (total > 0) {
      //   NativeHashService().preAllocateDisk(item.savePath, total);
      // }
      // ---------------------------------

      // To strictly guarantee file size on disk matches downloaded bytes
      // and prevent visual anomalies with sparse files during chunks,
      // we gracefully fall back to a robust single-connection stream.
      // This also fixes the erratic speed reporting from parallel segments.
      await _downloadSingle(item, existingBytes, cancelToken);

      item.status = DownloadStatus.done;
      item.speedBytesPerSec = 0;
      item.etaSeconds = 0;
      item.downloadedBytes = item.totalBytes;
      _cancelTokens.remove(item.id);
      await updateStorageInfo();

      _channel.invokeMethod('stopForegroundService', {
        'id': 1001,
        'filename': item.fileName,
        'success': true,
      }).catchError((_) {});
    } catch (e) {
      _handleDownloadError(item, e);
    } finally {
      if (_activeCount > 0) {
        _stopForegroundIfNoActive();
        _activeCount--;
      }
      await DatabaseHelper().updateDownload(item);
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> _downloadSingle(
      DownloadItem item, int existingBytes, CancelToken cancelToken) async {
    final dio = DioClient().dio;
    final file = File(item.savePath);
    item.downloadedBytes = existingBytes; // SYNC WITH DISK START

    final response = await dio.get<ResponseBody>(
      item.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
      ),
    );

    // CRITICAL: For pre-allocated files, FileMode.append is WRONG.
    // It will append to the END of the pre-allocated (full size) file.
    // We must use 'write' or 'r+' and set position manually.
    final raf = file.openSync(mode: FileMode.append);
    if (existingBytes > 0) {
      raf.setPositionSync(existingBytes);
    }
    final stream = response.data!.stream;

    DateTime lastUpdate = DateTime.now();
    int bytesSinceUpdate = 0;

    await for (final chunk in stream) {
      if (cancelToken.isCancelled) break;
      raf.writeFromSync(chunk);
      item.downloadedBytes += chunk.length;
      bytesSinceUpdate += chunk.length;

      final now = DateTime.now();
      if (now.difference(lastUpdate).inMilliseconds >= 500) {
        _updateProgress(
            item, bytesSinceUpdate, now.difference(lastUpdate).inMilliseconds);
        lastUpdate = now;
        bytesSinceUpdate = 0;
      }
    }
    raf.closeSync();
  }

  void _updateProgress(
      DownloadItem item, int bytesSinceLastUpdate, int diffMs) {
    if (diffMs == 0) return;

    // Smooth out speed calculation
    double currentSpeed = (bytesSinceLastUpdate / (diffMs / 1000)).toDouble();
    if (item.speedBytesPerSec == 0) {
      item.speedBytesPerSec = currentSpeed;
    } else {
      item.speedBytesPerSec =
          (item.speedBytesPerSec * 0.7) + (currentSpeed * 0.3);
    }

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
      'eta': _formatDuration(item.etaSeconds),
      'size':
          '${_formatSize(item.downloadedBytes)} / ${_formatSize(item.totalBytes)}',
    }).catchError((_) {});

    final now = DateTime.now();
    if (now.difference(_lastNotifyTime).inMilliseconds > 250) {
      _lastNotifyTime = now;
      notifyListeners();
      // Periodically persist to DB in case of crash (every 5 seconds)
      if (now.difference(_lastSaveTime).inSeconds > 5) {
        _lastSaveTime = now;
        DatabaseHelper().updateDownload(item);
      }
    }
  }

  void _handleDownloadError(DownloadItem item, dynamic e) {
    if (e is DioException && CancelToken.isCancel(e)) return;

    if (item.retryCount < 3) {
      item.retryCount++;
      item.status = DownloadStatus.queued;
    } else {
      item.status = DownloadStatus.error;
      item.errorMessage = e.toString();
    }
    DatabaseHelper().updateDownload(item);
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

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String _formatSize(int bytes) {
  if (bytes < 0) return "Unknown";
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
