enum DownloadStatus { queued, downloading, paused, error, done }

class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  String? batchId;
  String? batchName;
  DownloadStatus status;
  int totalBytes;
  int downloadedBytes;
  double speedBytesPerSec;
  int etaSeconds;
  int retryCount;
  String? errorMessage;
  DateTime addedAt;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.batchId,
    this.batchName,
    this.status = DownloadStatus.queued,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds = 0,
    this.retryCount = 0,
    this.errorMessage,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get statusLabel {
    switch (status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.error:
        return 'Error';
      case DownloadStatus.done:
        return 'Done';
    }
  }

  DownloadItem copyWith({
    DownloadStatus? status,
    int? totalBytes,
    int? downloadedBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    int? retryCount,
    String? errorMessage,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        fileName: fileName,
        savePath: savePath,
        batchId: batchId,
        batchName: batchName,
        status: status ?? this.status,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        retryCount: retryCount ?? this.retryCount,
        errorMessage: errorMessage ?? this.errorMessage,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'savePath': savePath,
    'batchId': batchId,
    'batchName': batchName,
    'status': status.index,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'retryCount': retryCount,
    'errorMessage': errorMessage,
    'addedAt': addedAt.toIso8601String(),
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'],
      url: json['url'],
      fileName: json['fileName'],
      savePath: json['savePath'],
      batchId: json['batchId'],
      batchName: json['batchName'],
      status: DownloadStatus.values[json['status'] ?? 0],
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
      retryCount: json['retryCount'] ?? 0,
      errorMessage: json['errorMessage'],
      addedAt: json['addedAt'] != null ? DateTime.parse(json['addedAt']) : null,
    );
  }
}
