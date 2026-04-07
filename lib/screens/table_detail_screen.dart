import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../services/connection_manager.dart';
import '../services/database_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart'; // <--- ADD THIS

import 'dart:io';
// import 'package:flutter/material.dart'; // Already imported at top

class TableDetailScreen extends StatefulWidget {
  final String tableName;
  final String? tableComment;

  const TableDetailScreen({super.key, required this.tableName, this.tableComment});

  @override
  State<TableDetailScreen> createState() => _TableDetailScreenState();
}

class _TableDetailScreenState extends State<TableDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Schema Data
  List<PlutoColumn> schemaColumns = [];
  List<PlutoRow> schemaRows = [];
  bool isSchemaLoading = true;
  String? schemaError;
  String? _pkColumn; // Primary Key Name

  // Table Data
  List<PlutoColumn> dataColumns = [];
  List<PlutoRow> dataRows = [];
  bool isDataLoading = true;
  String? dataError;
  
  // Tracking Changes
  final Set<Key> _dirtyRowKeys = {};

  // Pagination & Infinite Scroll
  int _offset = 0;
  final int _limit = 200;
  PlutoGridStateManager? _stateManager;
  bool _isFetchingMore = false;
  
  // Refresh Tracking
  ConnectionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSchema();
    _loadData();

    // Listen to connection changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cp = Provider.of<ConnectionProvider>(context, listen: false);
      _lastStatus = cp.status;
      cp.addListener(_onConnectionChanged);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Remove listener
    final cp = Provider.of<ConnectionProvider>(context, listen: false);
    cp.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    final cp = Provider.of<ConnectionProvider>(context, listen: false);
    final currentStatus = cp.status;

    // Trigger refresh when transitioning from 'connecting' to 'connected'
    if (_lastStatus == ConnectionStatus.connecting && currentStatus == ConnectionStatus.connected) {
       _loadSchema();
       _loadData();
    }
    _lastStatus = currentStatus;
  }
  
  void _scrollListener() {
    if (_stateManager == null || _isFetchingMore || isDataLoading) return;
    if (_stateManager!.scroll.bodyRowsVertical!.offset >= 
        (_stateManager!.scroll.bodyRowsVertical!.position.maxScrollExtent - 50)) {
          _loadData(append: true);
    }
  }

  Future<void> _loadSchema() async {
    try {
      final schema = await DatabaseService().getTableSchema(widget.tableName);
      
      String? pk;
      final cols = [
        PlutoColumn(title: 'Field', field: 'Field', type: PlutoColumnType.text(), width: 150, enableContextMenu: false, readOnly: true),
        PlutoColumn(title: 'Type', field: 'Type', type: PlutoColumnType.text(), width: 150, enableContextMenu: false, readOnly: true),
        PlutoColumn(title: 'Null', field: 'Null', type: PlutoColumnType.text(), width: 80, enableContextMenu: false, readOnly: true),
        PlutoColumn(title: 'Key', field: 'Key', type: PlutoColumnType.text(), width: 80, enableContextMenu: false, readOnly: true),
        PlutoColumn(title: 'Default', field: 'Default', type: PlutoColumnType.text(), width: 100, enableContextMenu: false, readOnly: true),
        PlutoColumn(title: 'Extra', field: 'Extra', type: PlutoColumnType.text(), width: 150, enableContextMenu: false, readOnly: true),
      ];

      final rows = schema.map((row) {
        if (row['Key'] == 'PRI') {
          pk = row['Field'];
        }
        return PlutoRow(cells: {
          'Field': PlutoCell(value: row['Field'] ?? ''),
          'Type': PlutoCell(value: row['Type'] ?? ''),
          'Null': PlutoCell(value: row['Null'] ?? ''),
          'Key': PlutoCell(value: row['Key'] ?? ''),
          'Default': PlutoCell(value: row['Default'] ?? ''),
          'Extra': PlutoCell(value: row['Extra'] ?? ''),
        });
      }).toList();

      if (mounted) {
        setState(() {
          schemaColumns = cols;
          schemaRows = rows;
          isSchemaLoading = false;
          _pkColumn = pk;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          schemaError = e.toString();
          isSchemaLoading = false;
        });
      }
    }
  }

  Future<void> _loadData({bool append = false}) async {
    try {
      if (append) {
        if (_isFetchingMore) return;
        _isFetchingMore = true;
      } else {
        setState(() {
          isDataLoading = true;
          dataError = null;
        });
        _offset = 0; // Reset
        _dirtyRowKeys.clear();
      }

      // Fetch with pagination
      final results = await DatabaseService().executeQuery("SELECT * FROM ${widget.tableName} LIMIT $_limit OFFSET $_offset");
      
      if (results.cols.isNotEmpty) {
        final colsList = results.cols.toList();
        
        // Initialize max width map with header length
        final Map<String, double> colWidths = {};
        for(var col in colsList) {
           // Base width on header string length * estimated font width (~10px) + padding
           colWidths[col.name] = (col.name.length * 10.0) + 20; 
        }

        // Iterate rows to find max length
        // We only scan the first batch (up to 200) for performance
        for (var row in results.rows) {
           for (int i = 0; i < colsList.length; i++) {
              final colName = colsList[i].name;
              final val = row.colAt(i)?.toString() ?? '';
              final len = val.length;
              final estimatedWidth = (len * 8.0) + 20; // Approx 8px per char for data
              if (estimatedWidth > colWidths[colName]!) {
                 colWidths[colName] = estimatedWidth;
              }
           }
        }
        
        // Define columns (only on first load)
        final cols = [
           PlutoColumn(
             title: 'No', 
             field: 'no_column_index', 
             type: PlutoColumnType.number(), 
             width: 45, 
             minWidth: 45,
             enableContextMenu: false, 
             enableSorting: false,
             enableColumnDrag: false,
             enableRowDrag: false,
             readOnly: true,
             frozen: PlutoColumnFrozen.start,
           ),
           ...colsList.map((col) {
            // Cap max width to prevent huge columns
            final calculatedWidth = colWidths[col.name] ?? 100.0;
            final finalWidth = calculatedWidth > 300 ? 300.0 : calculatedWidth;
            
            return PlutoColumn(
              title: col.name,
              field: col.name,
              type: PlutoColumnType.text(),
              width: finalWidth,
              minWidth: 80, // Increased min width to match sql_screen
              enableContextMenu: false,
              readOnly: false, // Enable editing
            );
        })];

        final rows = <PlutoRow>[];
        int rowIndex = _offset;
        
        for (var row in results.rows) {
          rowIndex++;
          final cells = <String, PlutoCell>{
            'no_column_index': PlutoCell(value: rowIndex),
          };
          for (int i = 0; i < colsList.length; i++) {
             final col = colsList[i];
             final val = row.colAt(i);
             cells[col.name] = PlutoCell(value: val?.toString() ?? '');
          }
          rows.add(PlutoRow(cells: cells));
        }

        if (mounted) {
          if (append) {
             _offset += _limit;
             if (rows.isNotEmpty) {
               await PlutoGridStateManager.initializeRowsAsync(
                  dataColumns,
                  rows,
                ).then((value) {
                  _stateManager?.appendRows(value);
                  _stateManager?.notifyListeners();
                });
             }
             _isFetchingMore = false;
          } else {
             _offset += _limit;
             setState(() {
              dataColumns = cols;
              dataRows = rows;
              isDataLoading = false;
            });
          }
        }
      } else {
         if (mounted) {
           if (!append) {
            setState(() {
              dataError = "No columns found";
              isDataLoading = false;
            });
           } else {
             _isFetchingMore = false; // No more data to append
           }
        }
      }

    } catch (e) {
      if (mounted) {
        if (!append) {
          setState(() {
            dataError = e.toString();
            isDataLoading = false;
          });
        } else {
          _isFetchingMore = false; 
        }
      }
    }
  }

  void _handleAddRow() {
    if (_stateManager == null) return;
    
    final cells = <String, PlutoCell>{
      'no_column_index': PlutoCell(value: 0), // New row marker
    };
    
    // Initialize other cells with empty strings
    for (var col in dataColumns) {
      if (col.field != 'no_column_index') {
        cells[col.field] = PlutoCell(value: '');
      }
    }
    
    // Insert at top
    _stateManager!.insertRows(0, [PlutoRow(cells: cells)]);
  }

  Future<void> _handleDeleteRow() async {
    if (!Provider.of<ConnectionProvider>(context, listen: false).isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Database connection is lost.')),
      );
      return;
    }
    if (_stateManager == null) return;
    final currentRow = _stateManager!.currentRow;
    
    if (currentRow == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a row to delete.')),
      );
      return;
    }

    // Check if it's a new row (not saved yet)
    final isNewRow = currentRow.cells['no_column_index']?.value == 0;
    
    if (isNewRow) {
       _stateManager!.removeRows([currentRow]);
       return;
    }

    // Existing Row logic
    if (_pkColumn == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete: Table has no Primary Key.')),
      );
      return; 
    }

    final pkValue = currentRow.cells[_pkColumn]?.value;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Row'),
        content: Text('Are you sure you want to delete?\n$_pkColumn: $pkValue'),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
           TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm == true) {
      try {
        await DatabaseService().deleteRow(widget.tableName, _pkColumn!, pkValue);
        _stateManager!.removeRows([currentRow]);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted.')),
        );
      } catch(e) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _handleSave() async {
     if (!Provider.of<ConnectionProvider>(context, listen: false).isConnected) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Error: Database connection is lost.')),
       );
       return;
     }
     if (_stateManager == null) return;
     
     // 1. Identify New Rows (no_column_index == 0)
     final newRows = _stateManager!.rows.where((r) => r.cells['no_column_index']?.value == 0).toList();
     
     // 2. Identify Modified Rows (in _dirtyRowKeys AND not new)
     final modifiedRows = _stateManager!.rows.where((r) => 
       _dirtyRowKeys.contains(r.key) && r.cells['no_column_index']?.value != 0
     ).toList();

     if (newRows.isEmpty && modifiedRows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No changes.')),
        );
        return;
     }

     int successCount = 0;
     List<String> errors = [];

     // Process Inserts
     for (var row in newRows) {
        try {
           final data = <String, dynamic>{};
           row.cells.forEach((key, cell) {
             if (key != 'no_column_index') {
               data[key] = cell.value;
             }
           });
           
           await DatabaseService().insertRow(widget.tableName, data);
           successCount++;
        } catch(e) {
           errors.add('Insert Error: $e');
        }
     }

     // Process Updates
     for (var row in modifiedRows) {
       if (_pkColumn == null) {
         errors.add('Update Error: PK missing');
         continue; 
       }
       
       try {
         final pkValue = row.cells[_pkColumn]?.value;
         final data = <String, dynamic>{};
           row.cells.forEach((key, cell) {
             if (key != 'no_column_index' && key != _pkColumn) {
               data[key] = cell.value;
             }
           });
           
         await DatabaseService().updateRow(widget.tableName, _pkColumn!, pkValue, data);
         successCount++;
       } catch(e) {
         errors.add('Update Error: $e');
       }
     }

     if (mounted) {
       if (errors.isNotEmpty) {
           showDialog(
             context: context,
             builder: (ctx) => AlertDialog(
               title: const Text('Save Error'),
               content: SingleChildScrollView(child: Text(errors.join('\n'))),
               actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
             )
           );
       } else {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Saved $successCount rows')),
           );
       }
       
       // Reload to reflect clean state and IDs
       _loadData(); 
     }
  }

  Future<void> _handleExportCsv() async {
    final fileName = await _showFileDialog('Export CSV', '${widget.tableName}.csv');
    if (fileName != null && fileName.isNotEmpty && mounted) {
      try {
        final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final path = '${directory.path}/$fileName';

        final csv = await DatabaseService().exportTableToCsv(widget.tableName);
        final file = File(path);
        await file.writeAsString(csv);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV Saved to: ${file.absolute.path}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to export CSV: $e')),
          );
        }
      }
    }
  }

  Future<String?> _showFileDialog(String title, String defaultName) {
    final TextEditingController controller = TextEditingController(text: defaultName);
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

  Future<void> _handleShowDDL() async {
    try {
      final ddl = await DatabaseService().getTableDDL(widget.tableName);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('DDL Information'),
            content: SingleChildScrollView(
              child: SelectableText(ddl),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ddl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get DDL: $e')),
        );
      }
    }
  }

  Future<void> _handleTruncateTable() async {
    if (!Provider.of<ConnectionProvider>(context, listen: false).isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Database connection is lost.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Truncate Table'),
        content: Text('Are you sure you want to TRUNCate ${widget.tableName}?\nThis will delete ALL data in this table and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
             child: const Text('Truncate')
          ),
        ],
      )
    );

    if (confirm == true) {
      try {
        await DatabaseService().truncateTable(widget.tableName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Table Truncated successfully')),
          );
          _loadData(); 
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Truncate failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleDropTable() async {
     if (!Provider.of<ConnectionProvider>(context, listen: false).isConnected) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Error: Database connection is lost.')),
       );
       return;
     }
     final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drop Table'),
        content: Text('Are you sure you want to DROP ${widget.tableName}?\nThis will PERMANENTLY DELETE the table and all its data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
             onPressed: () => Navigator.pop(ctx, true), 
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             child: const Text('DROP')
          ),
        ],
      )
    );

    if (confirm == true) {
       if (!mounted) return;
       final confirm2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Final Confirmation'),
          content: Text('Please confirm again. DROP ${widget.tableName}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
               onPressed: () => Navigator.pop(ctx, true), 
               style: TextButton.styleFrom(foregroundColor: Colors.red),
               child: const Text('YES, DROP IT')
            ),
          ],
        )
      );
      
      if (confirm2 == true) {
        try {
          await DatabaseService().dropTable(widget.tableName);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Table Dropped')),
            );
            Navigator.of(context).pop(); 
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Drop failed: $e')),
            );
          }
        }
      }
    }
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connection lost.')),
            );
          }
       });
       return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (connectionProvider.status == ConnectionStatus.connecting) {
       return const Scaffold(
         body: Center(
           child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               CircularProgressIndicator(),
               SizedBox(height: 16),
               Text('Re-connecting to database...'),
             ],
           ),
         ),
       );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.tableName),
            if (widget.tableComment != null && widget.tableComment!.isNotEmpty)
              Text(
                widget.tableComment!, 
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70)
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Information'),
            Tab(text: 'Data'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: [
              // Tab 1: Schema
              isSchemaLoading
                ? const Center(child: CircularProgressIndicator())
                : schemaError != null
                  ? Center(child: Text('Error: $schemaError', style: const TextStyle(color: Colors.red)))
                  : Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: PlutoGrid(
                              columns: schemaColumns,
                              rows: schemaRows,
                              configuration: const PlutoGridConfiguration(
                                  style: PlutoGridStyleConfig.dark(
                                    rowHeight: 25,
                                    columnHeight: 30,
                                    cellTextStyle: TextStyle(fontSize: 12),
                                    defaultCellPadding: EdgeInsets.symmetric(horizontal: 2),
                                    defaultColumnTitlePadding: EdgeInsets.symmetric(horizontal: 2),
                                  ),
                               ),
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.all(8.0),
                            color: Theme.of(context).colorScheme.surface,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                 ElevatedButton.icon(
                                  onPressed: _handleShowDDL,
                                  icon: const Icon(Icons.description, size: 16),
                                  label: const Text('DDL'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _handleTruncateTable,
                                  icon: const Icon(Icons.delete_sweep, size: 16),
                                  label: const Text('Truncate'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _handleDropTable,
                                  icon: const Icon(Icons.delete_forever, size: 16),
                                  label: const Text('Drop'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    
              // Tab 2: Data
              isDataLoading
                ? const Center(child: CircularProgressIndicator())
                : dataError != null
                  ? Center(child: Text('Error: $dataError', style: const TextStyle(color: Colors.red)))
                  : Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: dataColumns.isEmpty 
                              ? const Center(child: Text('No columns found'))
                              : PlutoGrid(
                                  columns: dataColumns,
                                  rows: dataRows,
                                  onChanged: (PlutoGridOnChangedEvent event) {
                                    // Track modified rows
                                    _dirtyRowKeys.add(event.row.key);
                                  },
                                  onRowSecondaryTap: (PlutoGridOnRowSecondaryTapEvent event) {
                                    _handleExportCsv();
                                  },
                                  onLoaded: (PlutoGridOnLoadedEvent event) {
                                    _stateManager = event.stateManager;
                                    // Listen to vertical scroll
                                    event.stateManager.scroll.bodyRowsVertical!.addListener(_scrollListener);
                                    
                                    // Auto-fit override removed for better performance and consistency
                                  },
                                  configuration: const PlutoGridConfiguration(
                                      style: PlutoGridStyleConfig.dark(
                                        rowHeight: 25,
                                        columnHeight: 30,
                                        cellTextStyle: TextStyle(fontSize: 12),
                                        defaultCellPadding: const EdgeInsets.symmetric(horizontal: 1),
                                        defaultColumnTitlePadding: const EdgeInsets.symmetric(horizontal: 1),
                                        iconSize: 12,
                                      ),
                                      columnSize: const PlutoGridColumnSizeConfig(
                                        autoSizeMode: PlutoAutoSizeMode.none, // Or scale, but usually compact means reducing fixed widths
                                      ),
                                   ),
                                ),
                          ),
                        ),
                        // No manual pagination controls here
                        // Bottom Controls (Add, Delete, Save)
                        if (!isDataLoading && dataError == null)
                          SafeArea(
                            top: false,
                            child: Container(
                              padding: const EdgeInsets.all(8.0),
                              color: Theme.of(context).colorScheme.surface,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _handleAddRow,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _handleDeleteRow,
                                    icon: const Icon(Icons.remove, size: 16),
                                    label: const Text('Delete'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _handleSave,
                                    icon: const Icon(Icons.save, size: 16),
                                    label: const Text('Save'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ],
          ),
          if (connectionProvider.status == ConnectionStatus.connecting)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Re-connecting to database...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
