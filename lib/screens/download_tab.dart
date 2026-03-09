import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import '../services/thumbnail_service.dart';

class DownloadTab extends StatefulWidget {
  const DownloadTab({super.key});

  @override
  State<DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<DownloadTab> {
  final Set<String> _expandedBatchIds = {};

  @override
  Widget build(BuildContext context) {
    final dlProvider = context.watch<DownloadProvider>();
    final queue = dlProvider.queue;

    // Grouping logic
    final Map<String?, List<DownloadItem>> grouped = {};
    for (var item in queue) {
      grouped.putIfAbsent(item.batchId, () => []).add(item);
    }

    final batchIds = grouped.keys.toList();
    batchIds.sort((a, b) {
      if (a == null) return -1;
      if (b == null) return 1;
      return a.compareTo(b);
    });

    final isSelectionMode = dlProvider.isSelectionMode;

    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${dlProvider.selectedIds.length} Selected')
            : const Text('Downloads'),
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: dlProvider.clearSelection,
              )
            : null,
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select All',
                  onPressed: dlProvider.selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete Selected',
                  onPressed: () => _confirmDeleteSelected(context, dlProvider),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Select Items',
                  onPressed: dlProvider.toggleSelectionMode,
                ),
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Pause All',
                  onPressed: dlProvider.pauseAll,
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: 'Resume All',
                  onPressed: dlProvider.resumeAll,
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear Done',
                  onPressed: () => _confirmClearDone(context, dlProvider),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'export') {
                      await dlProvider.exportQueue();
                    } else if (value == 'import') {
                      final success = await dlProvider.importQueue();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(success
                                  ? 'Queue imported successfully!'
                                  : 'Import cancelled or failed.')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, size: 20),
                          SizedBox(width: 8),
                          Text('Export Queue')
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Import Queue')
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          _buildStorageAnalyzer(),
          Expanded(
            child: queue.isEmpty
                ? const Center(child: Text('Download queue is empty.'))
                : ListView.builder(
                    itemCount: batchIds.length + 1,
                    itemBuilder: (context, index) {
                      if (index == batchIds.length) {
                        return const SizedBox(height: 140);
                      }
                      final bId = batchIds[index];
                      final items = grouped[bId]!;

                      if (bId == null) {
                        return Column(
                          children: items
                              .asMap()
                              .entries
                              .map((entry) => _buildDownloadCard(
                                  context, dlProvider, entry.value,
                                  index: entry.key + 1))
                              .toList(),
                        );
                      } else {
                        return _buildBatchTile(context, dlProvider, items,
                            index: index + 1);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageAnalyzer() {
    final dlProvider = context.watch<DownloadProvider>();
    final totalMB = dlProvider.totalStorage;
    final freeMB = dlProvider.freeStorage;

    if (totalMB <= 0) return const SizedBox.shrink();

    final usedMB = totalMB - freeMB;
    final progress = totalMB > 0 ? (usedMB / totalMB) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Device Storage',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                'Free: ${(freeMB / 1024).toStringAsFixed(1)} GB / ${(totalMB / 1024).toStringAsFixed(1)} GB',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: progress > 0.9
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearDone(BuildContext context, DownloadProvider dlProvider) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Clear Finished Tasks?'),
                content: const Text(
                    'This will remove completed and failed tasks from the list.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () {
                        dlProvider.clearDone();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Clear List',
                          style: TextStyle(color: Colors.red))),
                ]));
  }

  Widget _buildBatchTile(BuildContext context, DownloadProvider dlProvider,
      List<DownloadItem> items,
      {int? index}) {
    final batchName = items.first.batchName ?? 'Folder Download';
    final String batchId = items.first.batchId!;
    final bool isExpanded = _expandedBatchIds.contains(batchId);

    final int totalItems = items.length;
    final int doneItems =
        items.where((i) => i.status == DownloadStatus.done).length;
    final double avgProgress =
        items.fold(0.0, (sum, i) => sum + i.progress) / totalItems;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            ListTile(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedBatchIds.remove(batchId);
                  } else {
                    _expandedBatchIds.add(batchId);
                  }
                });
              },
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.folder, color: Colors.white, size: 20),
              ),
              title: Text('${index != null ? "$index. " : ""}$batchName',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$doneItems / $totalItems files complete (${(avgProgress * 100).toInt()}%)',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: avgProgress,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () =>
                        _showBatchOptions(context, dlProvider, batchId, items),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  children: items
                      .asMap()
                      .entries
                      .map((entry) => _buildDownloadCard(
                          context, dlProvider, entry.value,
                          isNested: true, index: entry.key + 1))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBatchOptions(BuildContext context, DownloadProvider dlProvider,
      String batchId, List<DownloadItem> items) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle),
              title: const Text('Resume All in Batch'),
              onTap: () {
                dlProvider.resumeBatch(batchId);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.pause_circle),
              title: const Text('Pause All in Batch'),
              onTap: () {
                dlProvider.pauseBatch(batchId);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('Remove Batch',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context); // close bottom sheet
                _confirmRemoveBatch(context, dlProvider, batchId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveBatch(
      BuildContext context, DownloadProvider dlProvider, String batchId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Batch?'),
        content: const Text(
            'Are you sure you want to remove all items in this batch?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              dlProvider.stopBatch(batchId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item,
      {bool isNested = false, int? index}) {
    final bool isSelected = dlProvider.selectedIds.contains(item.id);
    final bool isSelectionMode = dlProvider.isSelectionMode;

    Widget card = Container(
      margin: isNested
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index != null ? "$index. " : ""}${item.fileName}',
                    style: TextStyle(
                        fontWeight:
                            isNested ? FontWeight.normal : FontWeight.bold,
                        fontSize: isNested ? 13 : 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 6,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)} (${(item.progress * 100).toInt()}%)',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _formatSpeedAndETA(item),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          item.statusLabel,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 10,
                            color: item.status == DownloadStatus.error
                                ? Colors.red
                                : (item.status == DownloadStatus.done
                                    ? Colors.green
                                    : Colors.blue),
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.errorMessage != null)
                    Text(item.errorMessage!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 10)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.status == DownloadStatus.done)
                        TextButton.icon(
                          icon: const Icon(Icons.verified_user, size: 14),
                          label: const Text('Verify',
                              style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              _showVerifyHashDialog(context, dlProvider, item),
                        ),
                      _buildActionButtons(context, dlProvider, item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isSelectionMode) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) => dlProvider.toggleSelection(item.id),
            ),
            Expanded(
                child: GestureDetector(
              onTap: () => dlProvider.toggleSelection(item.id),
              child: AbsorbPointer(child: card),
            )),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () {
          dlProvider.toggleSelection(item.id);
        },
        child: card,
      ),
    );
  }

  Widget _buildThumbnail(DownloadItem item) {
    return FutureBuilder<String?>(
      future: ThumbnailService().getThumbnail(item.savePath),
      builder: (context, snapshot) {
        final hasThumb = snapshot.hasData && snapshot.data != null;
        return Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            image: hasThumb
                ? DecorationImage(
                    image: FileImage(File(snapshot.data!)), fit: BoxFit.cover)
                : null,
          ),
          child: !hasThumb
              ? Icon(Icons.description,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.5))
              : null,
        );
      },
    );
  }

  Widget _buildActionButtons(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.queued)
          IconButton(
            icon: const Icon(Icons.pause, color: Colors.orange, size: 18),
            onPressed: () => dlProvider.pause(item.id),
          ),
        if (item.status == DownloadStatus.paused ||
            item.status == DownloadStatus.error)
          IconButton(
            icon: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
            onPressed: () => dlProvider.resume(item.id),
          ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red, size: 18),
          onPressed: () => _confirmSafeDelete(context, dlProvider, item),
        ),
      ],
    );
  }

  void _confirmSafeDelete(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    bool deleteFile = false;
    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
                title: const Text('Delete Task?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        'Are you sure you want to remove "${item.fileName}" from the queue?'),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      title: const Text('Delete file from storage as well',
                          style: TextStyle(fontSize: 13)),
                      value: deleteFile,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setState(() => deleteFile = val ?? false);
                      },
                    )
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  TextButton(
                    onPressed: () {
                      dlProvider.stop(item.id);
                      if (deleteFile) {
                        final f = File(item.savePath);
                        if (f.existsSync()) f.deleteSync();
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  )
                ]);
          });
        });
  }

  void _confirmDeleteSelected(
      BuildContext context, DownloadProvider dlProvider) {
    bool deleteFile = false;
    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: const Text('Delete Selected?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Are you sure you want to remove ${dlProvider.selectedIds.length} items?'),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    title: const Text('Delete files from storage as well',
                        style: TextStyle(fontSize: 13)),
                    value: deleteFile,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setState(() => deleteFile = val ?? false);
                    },
                  )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () {
                    dlProvider.deleteSelected(deleteFiles: deleteFile);
                    Navigator.pop(ctx);
                  },
                  child:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                )
              ],
            );
          });
        });
  }

  void _showVerifyHashDialog(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item) {
    final ctrl = TextEditingController();
    bool isVerifying = false;
    bool? isValid;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: const Text('Verify File Hash'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Check MD5 or SHA256 for: ${item.fileName}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: 'Expected Hash',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isVerifying) const CircularProgressIndicator(),
                  if (!isVerifying && isValid != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isValid! ? Icons.check_circle : Icons.cancel,
                            color: isValid! ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(isValid! ? 'Hash Matches!' : 'Hash Mismatch!',
                            style: TextStyle(
                                color: isValid! ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold))
                      ],
                    )
                ],
              ),
              actions: [
                if (!isVerifying)
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close')),
                if (!isVerifying)
                  ElevatedButton(
                    onPressed: () async {
                      if (ctrl.text.trim().isEmpty) return;
                      setState(() {
                        isVerifying = true;
                        isValid = null;
                      });

                      final result = await dlProvider.verifyFileHash(
                          item.savePath, ctrl.text);

                      if (context.mounted) {
                        setState(() {
                          isVerifying = false;
                          isValid = result;
                        });
                      }
                    },
                    child: const Text('Verify'),
                  )
              ],
            );
          });
        });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatSpeedAndETA(DownloadItem item) {
    if (item.status == DownloadStatus.done) return 'Completed';
    if (item.status == DownloadStatus.error) return 'Failed';
    if (item.speedBytesPerSec == 0) return '0 B/s | ETA: --';

    String speedStr = '';
    if (item.speedBytesPerSec > 1024 * 1024) {
      speedStr =
          '${(item.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (item.speedBytesPerSec > 1024) {
      speedStr = '${(item.speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      speedStr = '${item.speedBytesPerSec.toStringAsFixed(0)} B/s';
    }

    int mm = item.etaSeconds ~/ 60;
    int ss = item.etaSeconds % 60;
    int hh = mm ~/ 60;
    mm = mm % 60;

    String etaStr = hh > 0 ? '${hh}h ${mm}m ${ss}s' : '${mm}m ${ss}s';

    return '$speedStr | ETA: $etaStr';
  }
}
