import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../services/connection_manager.dart';
import '../services/database_service.dart';
import '../services/database_helper.dart';
import '../models/query_history.dart';
import '../models/saved_query.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/highlight.dart' show highlight;

class SqlExecutionScreen extends StatefulWidget {
  const SqlExecutionScreen({super.key});

  @override
  State<SqlExecutionScreen> createState() => _SqlExecutionScreenState();
}

class _SqlExecutionScreenState extends State<SqlExecutionScreen> {
  late CodeController _sqlController;

  @override
  void initState() {
    super.initState();
    _sqlController = CodeController(text: "select 1 ", language: sql);
  }

  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  bool isLoading = false;
  String? errorMessage;

  // Use a key to force rebuild grid when columns change completely
  Key _gridKey = UniqueKey();

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _runQuery() async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    // Only block if explicitly disconnected or in error.
    // Allow 'connecting' for transparent background reconnects.
    if (connectionProvider.status == ConnectionStatus.disconnected ||
        connectionProvider.status == ConnectionStatus.error) {
      setState(() {
        errorMessage = 'Error: Database connection is lost.';
      });
      return;
    }

    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    final startTime = DateTime.now();

    setState(() {
      isLoading = true;
      errorMessage = null;
      columns = [];
      rows = [];
    });

    try {
      final dbService = DatabaseService();
      final results = await dbService.executeQuery(sql);

      if (results.cols.isNotEmpty) {
        final colsList = results.cols.toList();
        final rowsList = results.rows
            .toList(); // Cache rows for multiple iterations

        // Calculate max width for each column
        final Map<String, double> colWidths = {};
        for (var col in colsList) {
          // Initial width based on header length (approx 10px per char + padding)
          colWidths[col.name] = (col.name.length * 10.0) + 20;
        }

        for (var row in rowsList) {
          for (int i = 0; i < colsList.length; i++) {
            final colName = colsList[i].name;
            final val = row.colAt(i);
            if (val != null) {
              final len = val.toString().length;
              final estimatedWidth =
                  (len * 8.0) +
                  20; // Approx 8px per char for data (smaller font)
              if (estimatedWidth > (colWidths[colName] ?? 0)) {
                colWidths[colName] = estimatedWidth;
              }
            }
          }
        }

        // 1. Generate PlutoColumns from metadata
        final newColumns = [
          PlutoColumn(
            title: 'No',
            field: 'no_column_index',
            type: PlutoColumnType.number(),
            width: 45,
            enableRowDrag: false,
            enableRowChecked: false,
            enableEditingMode: false,
            enableContextMenu: false,
            enableSorting: false,
            frozen: PlutoColumnFrozen.start,
          ),
          ...colsList.map((col) {
            final calculatedWidth = colWidths[col.name] ?? 100;
            // Cap width to avoid extremely wide columns, optional but recommended
            final finalWidth = calculatedWidth > 300 ? 300.0 : calculatedWidth;

            return PlutoColumn(
              title: col.name,
              field: col.name,
              type: PlutoColumnType.text(),
              width: finalWidth,
              minWidth: 80,
              enableRowDrag: false,
              enableRowChecked: false,
              enableEditingMode: false,
              enableContextMenu: false,
            );
          }),
        ];

        // 2. Generate PlutoRows from data
        int rowIndex = 0;
        final newRows = rowsList.map((row) {
          rowIndex++;
          final cells = <String, PlutoCell>{
            'no_column_index': PlutoCell(value: rowIndex),
          };

          for (int i = 0; i < colsList.length; i++) {
            final col = colsList[i];
            final val = row.colAt(i);
            cells[col.name] = PlutoCell(value: val ?? '');
          }

          return PlutoRow(cells: cells);
        }).toList();

        setState(() {
          columns = newColumns;
          rows = newRows;
          _gridKey = UniqueKey();
        });
      } else {
        // Handle non-SELECT queries
        setState(() {
          errorMessage =
              'Query executed successfully. No rows returned (Affected rows: ${results.affectedRows})';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
      // Log failed query too? Optional.
      // For now only logging validation/execution attempts
    } finally {
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      // Save to History
      try {
        await DatabaseHelper().addToHistory(
          QueryHistory(
            query: sql,
            executedAt: startTime,
            success: errorMessage == null || !errorMessage!.startsWith('Error'),
            executionTimeMs: duration,
          ),
        );
      } catch (e) {
        // print('Failed to save history: $e');
      }

      setState(() {
        isLoading = false;
      });
    }
  }

  void _saveSql() {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a query.')));
      return;
    }

    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Query'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter name to save',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              await DatabaseHelper().insertSavedQuery(
                SavedQuery(name: name, query: sql, createdAt: DateTime.now()),
              );

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Saved.')));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _loadSql() {
    showDialog(
      context: context,
      builder: (context) => _LoadQueryDialog(
        onSelect: (query) {
          setState(() {
            _sqlController.text = query;
          });
        },
      ),
    );
  }

  Future<void> _exportResult() async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }

    // Permission Check
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }

      // For Android 11+ (API 30+), Manage External Storage might be needed for broad access,
      // but for Downloads folder, standard storage permission or just writing if targeting < 30 (or scoped storage logic)
      if (await Permission.manageExternalStorage.status.isDenied) {
        // This permission is special, usually user has to go to settings.
        // For now, let's try to proceed. If it fails, we guide user?
        // Actually, for writing to public Downloads, we might not need strict MANAGE_EXTERNAL_STORAGE if we use MediaStore,
        // but we are using File IO.
        // Let's request it if it's not granted, just in case.
        // await Permission.manageExternalStorage.request();
      }
    }

    final fileName = await _showFileDialog('Export CSV', 'result.csv');
    if (fileName != null && fileName.isNotEmpty) {
      try {
        final sb = StringBuffer();

        // Headers
        sb.writeln(columns.map((c) => '"${c.title}"').join(','));

        // Rows
        for (var row in rows) {
          final values = <String>[];
          for (var col in columns) {
            final cell = row.cells[col.field];
            final val = cell?.value?.toString() ?? '';
            final escaped = val.replaceAll('"', '""');
            values.add('"$escaped"');
          }
          sb.writeln(values.join(','));
        }

        String? directoryPath;
        if (Platform.isAndroid) {
          directoryPath = '/storage/emulated/0/Download';
        } else {
          final dir = await getDownloadsDirectory();
          directoryPath = dir?.path;
        }

        if (directoryPath == null) {
          directoryPath = (await getApplicationDocumentsDirectory()).path;
        }

        // 2. Create the full path
        final path = '$directoryPath/$fileName';

        final file = File(path);
        print(path);
        await file.writeAsString(sb.toString());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to: ${file.absolute.path}')),
          );
        }
      } catch (e) {
        print(e);
        if (mounted) {
          // Check if permission error
          if (e.toString().contains('Permission denied')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Save failed: Permission denied. Please allow in settings.',
                ),
              ),
            );
            // Open settings
            openAppSettings();
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
          }
        }
      }
    }
  }

  Future<String?> _showFileDialog(String title, String defaultName) {
    final TextEditingController controller = TextEditingController(
      text: defaultName,
    );
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'File Name',
              hintText: 'Enter file name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);

    // Redirect ONLY if truly disconnected or in error state.
    // Allow 'connecting' status for background re-connections.
    if (connectionProvider.status == ConnectionStatus.disconnected ||
        connectionProvider.status == ConnectionStatus.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Connection lost.')));
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('SQL Console')),
      body: Stack(
        children: [
          Column(
            children: [
              // Top: SQL Input
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter SQL query (e.g. SELECT * FROM users)',
                        contentPadding: EdgeInsets.all(8),
                      ),
                      child: CodeField(
                        controller: _sqlController,
                        minLines: 6,
                        maxLines: 6,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 30,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _runQuery,
                            style: ElevatedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Run'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          height: 30,
                          child: OutlinedButton(
                            onPressed: _saveSql,
                            style: OutlinedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          height: 30,
                          child: OutlinedButton(
                            onPressed: _loadSql,
                            style: OutlinedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Load'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          height: 30,
                          child: OutlinedButton(
                            onPressed: _exportResult,
                            style: OutlinedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              padding: EdgeInsets.zero,
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Export'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Error / Info Area
              if (errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  color: errorMessage!.startsWith('Error')
                      ? Theme.of(context).colorScheme.errorContainer
                      : Colors.green.shade900,
                  child: Text(
                    errorMessage!,
                    style: TextStyle(
                      color: errorMessage!.startsWith('Error')
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Colors.green.shade100,
                    ),
                  ),
                ),

              // Bottom: Grid
              Expanded(
                child: columns.isEmpty
                    ? const Center(child: Text('No results to display'))
                    : PlutoGrid(
                        key: _gridKey,
                        columns: columns,
                        rows: rows,
                        onLoaded: (PlutoGridOnLoadedEvent event) {
                          event.stateManager.setShowColumnFilter(false);
                        },
                        configuration: const PlutoGridConfiguration(
                          style: PlutoGridStyleConfig.dark(
                            rowHeight: 25, // Compact row height
                            columnHeight: 30, // Compact header height
                            cellTextStyle: TextStyle(
                              fontSize: 12,
                            ), // Smaller text
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (connectionProvider.status == ConnectionStatus.connecting)
            Container(
              color: Colors.black.withAlpha(76),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Re-connecting to database...',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadQueryDialog extends StatefulWidget {
  final Function(String) onSelect;

  const _LoadQueryDialog({required this.onSelect});

  @override
  State<_LoadQueryDialog> createState() => _LoadQueryDialogState();
}

class _LoadQueryDialogState extends State<_LoadQueryDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SavedQuery> _savedQueries = [];
  List<QueryHistory> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final saved = await DatabaseHelper().getSavedQueries();
    final hist = await DatabaseHelper().getQueryHistory();
    if (mounted) {
      setState(() {
        _savedQueries = saved;
        _history = hist;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSaved(int id) async {
    await DatabaseHelper().deleteSavedQuery(id);
    _loadData();
  }

  // Optional: Add history cleanup if needed, but not requested.

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Saved Queries'),
                Tab(text: 'History'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Saved Queries Tab
                        _savedQueries.isEmpty
                            ? const Center(child: Text('No saved queries.'))
                            : ListView.separated(
                                itemCount: _savedQueries.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _savedQueries[index];
                                  return ListTile(
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.query,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      onPressed: () => _deleteSaved(item.id!),
                                    ),
                                    onTap: () {
                                      widget.onSelect(item.query);
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),

                        // History Tab
                        _history.isEmpty
                            ? const Center(child: Text('No execution history.'))
                            : ListView.separated(
                                itemCount: _history.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _history[index];
                                  return ListTile(
                                    title: Text(
                                      item.query,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      item.executedAt.toString().substring(
                                        0,
                                        19,
                                      ),
                                    ), // Show timestamp
                                    leading: Icon(
                                      item.success
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: item.success
                                          ? Colors.green
                                          : Colors.red,
                                      size: 16,
                                    ),
                                    onTap: () {
                                      widget.onSelect(item.query);
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
                      ],
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
