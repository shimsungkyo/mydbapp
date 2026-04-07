import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../providers/connection_provider.dart';
import '../services/connection_manager.dart';
import '../services/database_service.dart';

import 'sql_execution_screen.dart';
import 'table_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  String? _currentDatabase;
  List<String> _databases = [];
  bool _isLoadingDatabases = true;
  
  // To trigger future builder refresh
  int _refreshKey = 0;
  Future<List<Map<String, String>>>? _tablesFuture;

  // Refresh Tracking
  ConnectionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _loadDatabases();
    _refreshTables();

    // Listen to connection changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cp = Provider.of<ConnectionProvider>(context, listen: false);
      _lastStatus = cp.status;
      cp.addListener(_onConnectionChanged);
    });
  }

  void _refreshTables() {
    setState(() {
      _tablesFuture = DatabaseService().getTables();
      _refreshKey++;
    });
  }

  @override
  void dispose() {
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
       _loadDatabases();
       _refreshTables();
    }
    _lastStatus = currentStatus;
  }



  Future<void> _loadDatabases() async {
    try {
      final dbs = await DatabaseService().getDatabases();
      
      if (mounted) {
         setState(() {
           _databases = dbs;
           _isLoadingDatabases = false;
         });
         
         // Fetch current DB Name
         _fetchCurrentDbName();
      }
    } catch (e) {
      print('Error loading databases: $e');
      if (mounted) {
        setState(() {
          _isLoadingDatabases = false;
        });
      }
    }
  }

  Future<void> _fetchCurrentDbName() async {
     try {
       final result = await DatabaseService().executeQuery('SELECT DATABASE()');
       if (result.rows.isNotEmpty) {
         final current = result.rows.first.colAt(0);
         if (mounted && current != null) {
           setState(() {
             _currentDatabase = current;
           });
         }
       }
     } catch (e) {
       print('Error fetching current db: $e');
     }
  }

  Future<void> _switchDatabase(String? dbName) async {
    if (dbName == null || dbName == _currentDatabase) return;

    try {
      await DatabaseService().changeDatabase(dbName);
      setState(() {
        _currentDatabase = dbName;
      });
      _refreshTables(); // Properly refresh tables using the new Future storage
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to database: $dbName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to switch database: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);

    // Redirect if disconnected
    // If disconnected, just pop back to connection screen
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

    return Scaffold(
      appBar: AppBar(
        title: _isLoadingDatabases 
          ? const Text('Loading...')
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _databases.contains(_currentDatabase) ? _currentDatabase : null,
                hint: const Text('Select Database', style: TextStyle(color: Colors.white70)),
                dropdownColor: Theme.of(context).primaryColor,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontSize: 18),
                items: _databases.map((String db) {
                  return DropdownMenuItem<String>(
                    value: db,
                    child: Text(db),
                  );
                }).toList(),
                onChanged: _switchDatabase,
              ),
            ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Provider.of<ConnectionProvider>(context, listen: false).disconnect();
            Navigator.pop(context);
          },
        ),
        bottom: connectionProvider.status == ConnectionStatus.connecting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, String>>>(
               future: _tablesFuture,
               builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting) {
                   return const Center(
                     child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         CircularProgressIndicator(),
                         SizedBox(height: 16),
                         Text('Loading tables...'),
                       ],
                     ),
                   );
                 } else if (snapshot.hasError) {
                   return Center(child: Text('Error loading tables: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                 } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                   return const Center(child: Text('No tables found in this database.'));
                 }
    
                 final tables = snapshot.data!;
                 
                 // Column Width Configuration
                 const double widthName = 250;
                 const double widthComment = 250;
                 const double widthRows = 180;
                 
                 final columns = [
                   PlutoColumn(
                     title: 'Table Name', 
                     field: 'name', 
                     type: PlutoColumnType.text(),
                     width: widthName,
                      renderer: (rendererContext) {
                        return GestureDetector(
                          onTap: () {
                             final tableName = rendererContext.cell.value.toString();
                             final comment = rendererContext.row.cells['comment']?.value.toString();
                             Navigator.push(
                               context, 
                               MaterialPageRoute(builder: (_) => TableDetailScreen(
                                 tableName: tableName,
                                 tableComment: comment,
                               ))
                             );
                          },
                          child: Text(
                            rendererContext.cell.value.toString(),
                            // style removed to match other columns
                          ),
                        );
                      },
                    ),
                   PlutoColumn(
                     title: 'Comment', 
                     field: 'comment', 
                     type: PlutoColumnType.text(),
                     width: widthComment,
                     enableContextMenu: false,
                     enableSorting: false,
                     enableColumnDrag: false,
                   ),
                   PlutoColumn(
                     title: 'Rows', 
                     field: 'rows', 
                     type: PlutoColumnType.number(),
                     width: widthRows,
                     enableContextMenu: false,
                     textAlign: PlutoColumnTextAlign.right,
                     enableSorting: false,
                     enableColumnDrag: false,
                   ),
    
                 ];
    
                 final rows = tables.map((table) {
                   return PlutoRow(cells: {
                     'name': PlutoCell(value: table['name'] ?? ''),
                     'comment': PlutoCell(value: table['comment'] ?? ''),
                     'rows': PlutoCell(value: table['rows'] ?? '0'),
    
                   });
                 }).toList();
    
                 return Column(
                   children: [
    
                     Expanded(
                       child: PlutoGrid(
                         columns: columns,
                         rows: rows,
                         onLoaded: (PlutoGridOnLoadedEvent event) {
                           event.stateManager.setShowColumnFilter(false);
                         },
                         onRowDoubleTap: (PlutoGridOnRowDoubleTapEvent event) {
                            final tableName = event.row.cells['name']?.value;
                            if (tableName != null) {
                              Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (_) => TableDetailScreen(tableName: tableName))
                              );
                            }
                         },
                         configuration: const PlutoGridConfiguration(
                            style: PlutoGridStyleConfig.dark(
                              rowHeight: 30,
                              columnHeight: 35,
                              cellTextStyle: const TextStyle(fontSize: 12),
                              columnTextStyle: const TextStyle(fontSize: 12),
                              iconSize: 0, // Hide any header icons
                            ),
                            columnSize: const PlutoGridColumnSizeConfig(
                               autoSizeMode: PlutoAutoSizeMode.scale,
                            ),
                         ),
                       ),
                     ),
                     SafeArea(
                       top: false,
                       child: Padding(
                         padding: const EdgeInsets.all(16.0),
                         child: Row(
                           children: [
                             Expanded(
                               child: ElevatedButton.icon(
                                 onPressed: () {
                                   Navigator.push(
                                     context,
                                     MaterialPageRoute(builder: (context) => const SqlExecutionScreen()),
                                   );
                                 },
                                 icon: const Icon(Icons.terminal),
                                 label: const Text('Open SQL Console'),
                                 style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                               ),
                             ),
                             const SizedBox(width: 8),
    
                           ],
                         ),
                       ),
                     ),
                   ],
                 );
               },
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
