import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:disk_space_2/disk_space_2.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';

class DownloadTab extends StatelessWidget {
  const DownloadTab({super.key});

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
    // Move "null" (Singles) to the end or start? Let's keep them at the top if any.
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
                        // Single files
                        return Column(
                          children: items
                              .map((item) =>
                                  _buildDownloadCard(context, dlProvider, item))
                              .toList(),
                        );
                      } else {
                        // Batch / Folder
                        return _buildBatchTile(context, dlProvider, items);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageAnalyzer() {
    return FutureBuilder(
      future: Future.wait([
        DiskSpace.getTotalDiskSpace,
        DiskSpace.getFreeDiskSpace,
      ]),
      builder: (context, AsyncSnapshot<List<double?>> snapshot) {
        if (!snapshot.hasData ||
            snapshot.data![0] == null ||
            snapshot.data![1] == null) {
          return const SizedBox.shrink();
        }

        // disk_space_2 returns MB
        final totalMB = snapshot.data![0]!;
        final freeMB = snapshot.data![1]!;
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
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
      },
    );
  }

  void _confirmClearDone(BuildContext context, DownloadProvider dlProvider) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Clear Finished Tasks?'),
                content: const Text(
                    'This will remove completed and failed tasks from the list. Files will remain on disk.'),
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
      List<DownloadItem> items) {
    final batchName = items.first.batchName ?? 'Folder Download';
    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.totalBytes);
    final downloadedBytes =
        items.fold<int>(0, (sum, item) => sum + item.downloadedBytes);
    final progress = totalBytes > 0 ? (downloadedBytes / totalBytes) : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(batchName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
                '${items.where((i) => i.status == DownloadStatus.done).length} of ${items.length} files done',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        children: items
            .map((item) =>
                _buildDownloadCard(context, dlProvider, item, isNested: true))
            .toList(),
      ),
    );
  }

  Widget _buildDownloadCard(
      BuildContext context, DownloadProvider dlProvider, DownloadItem item,
      {bool isNested = false}) {
    final bool isSelected = dlProvider.selectedIds.contains(item.id);
    final bool isSelectionMode = dlProvider.isSelectionMode;

    Widget card = Slidable(
      key: ValueKey(item.id),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.queued)
            SlidableAction(
              onPressed: (_) => dlProvider.pause(item.id),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              icon: Icons.pause,
              label: 'Pause',
            ),
          if (item.status == DownloadStatus.paused ||
              item.status == DownloadStatus.error)
            SlidableAction(
              onPressed: (_) => dlProvider.resume(item.id),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              icon: Icons.play_arrow,
              label: 'Resume',
            ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _confirmSafeDelete(context, dlProvider, item),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: Card(
        elevation: isNested ? 0 : 1,
        color: isNested ? Colors.transparent : null,
        margin: isNested
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.fileName,
                style: TextStyle(
                    fontWeight: isNested ? FontWeight.normal : FontWeight.bold,
                    fontSize: isNested ? 13 : 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: item.progress),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)} (${(item.progress * 100).toInt()}%)',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatSpeedAndETA(item),
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    item.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: item.status == DownloadStatus.error
                          ? Colors.red
                          : (item.status == DownloadStatus.done
                              ? Colors.green
                              : Colors.blue),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (item.errorMessage != null)
                Text(item.errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 10)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (item.status == DownloadStatus.done)
                    TextButton.icon(
                      icon: const Icon(Icons.verified_user, size: 16),
                      label: const Text('Verify Hash',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          _showVerifyHashDialog(context, dlProvider, item),
                    ),
                  if (item.status == DownloadStatus.downloading ||
                      item.status == DownloadStatus.queued)
                    IconButton(
                      icon: const Icon(Icons.pause,
                          color: Colors.orange, size: 20),
                      onPressed: () => dlProvider.pause(item.id),
                    ),
                  if (item.status == DownloadStatus.paused ||
                      item.status == DownloadStatus.error)
                    IconButton(
                      icon: const Icon(Icons.play_arrow,
                          color: Colors.green, size: 20),
                      onPressed: () => dlProvider.resume(item.id),
                    ),
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.red, size: 20),
                    onPressed: () =>
                        _confirmSafeDelete(context, dlProvider, item),
                  ),
                ],
              ),
            ],
          ),
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

    return GestureDetector(
      onLongPress: () {
        dlProvider.toggleSelection(item.id);
      },
      child: card,
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
                      'Are you sure you want to remove ${dlProvider.selectedIds.length} items from the queue?'),
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

                      if (ctx.mounted) {
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
