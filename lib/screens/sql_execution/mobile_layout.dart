import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:pluto_grid/pluto_grid.dart';
// import '../../providers/connection_provider.dart';
import '../../services/connection_manager.dart';

class MobileLayout extends StatelessWidget {
  final CodeController sqlController;
  final bool isLoading;
  final String? errorMessage;
  final List<PlutoColumn> columns;
  final List<PlutoRow> rows;
  final Key gridKey;
  final VoidCallback onRunQuery;
  final VoidCallback onSaveSql;
  final VoidCallback onLoadSql;
  final VoidCallback onExportResult;
  final ConnectionStatus connectionStatus;

  const MobileLayout({
    super.key,
    required this.sqlController,
    required this.isLoading,
    this.errorMessage,
    required this.columns,
    required this.rows,
    required this.gridKey,
    required this.onRunQuery,
    required this.onSaveSql,
    required this.onLoadSql,
    required this.onExportResult,
    required this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
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
                      controller: sqlController,
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
                          onPressed: isLoading ? null : onRunQuery,
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
                          onPressed: onSaveSql,
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
                          onPressed: onLoadSql,
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
                          onPressed: onExportResult,
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
                      key: gridKey,
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
        if (connectionStatus == ConnectionStatus.connecting)
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
    );
  }
}
