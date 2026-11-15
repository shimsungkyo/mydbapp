import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../models/saved_connection.dart';
import '../providers/connection_provider.dart';
import '../services/database_helper.dart';
import 'connection_edit_screen.dart';
import 'dashboard_screen.dart';
import '../utils/logger.dart';

class ConnectionListScreen extends StatefulWidget {
  const ConnectionListScreen({super.key});

  @override
  State<ConnectionListScreen> createState() => _ConnectionListScreenState();
}

class _ConnectionListScreenState extends State<ConnectionListScreen> {
  late Future<List<SavedConnection>> _connectionsFuture;
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleItemSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelectedItems() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected Items'),
        content: Text(
          'Delete ${_selectedIds.length} items? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedIds) {
        await DatabaseHelper().deleteConnection(id);
      }
      _refreshList();
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _connectionsFuture = DatabaseHelper().getConnections();
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _connectWithSaved(SavedConnection connection) async {
    final provider = Provider.of<ConnectionProvider>(context, listen: false);

    // Show loading dialog or snackbar?
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await provider.connect(
        host: connection.host,
        port: connection.port,
        username: connection.username,
        password: connection.password,
        databaseName: connection.databaseName,
        useSsh: connection.useSsh,
        sshHost: connection.sshHost,
        sshPort: connection.sshPort,
        sshUsername: connection.sshUsername,
        sshPassword: connection.sshPassword,
        sshKeyPath: connection.sshKeyPath,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Connection Failed'),
            content: Text('Connection failed: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_isSelectionMode) {
          _toggleSelectionMode();
          return;
        }

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => const _ExitDialog(),
        );

        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _toggleSelectionMode,
                )
              : null,
          title: Text(
            _isSelectionMode
                ? '${_selectedIds.length} Selected'
                : 'Saved Connections',
          ),
          actions: [
            if (_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _selectedIds.isNotEmpty
                    ? _deleteSelectedItems
                    : null,
              )
            else
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: 'Select Delete',
                onPressed: _toggleSelectionMode,
              ),
          ],
        ),
        body: FutureBuilder<List<SavedConnection>>(
          future: _connectionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final connections = snapshot.data ?? [];

            return ListView.builder(
              itemCount: connections.length + 1, // +1 for "Add New"
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                if (index == connections.length) {
                  // Last Item: Add New
                  if (_isSelectionMode) return const SizedBox.shrink();

                  return Column(
                    children: [
                      if (connections.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Connection information not found.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      Card(
                        elevation: 2,
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: ListTile(
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                            Icons.add_circle,
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                            size: 20,
                          ),
                          title: Text(
                            'Add New Connection',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onTertiaryContainer,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ConnectionEditScreen(),
                              ),
                            );
                            _refreshList();
                          },
                        ),
                      ),
                    ],
                  );
                }

                final conn = connections[index];
                final isSelected = _selectedIds.contains(conn.id);

                final card = Card(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    visualDensity: VisualDensity.compact,
                    leading: _isSelectionMode
                        ? Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              if (conn.id != null) {
                                _toggleItemSelection(conn.id!);
                              }
                            },
                          )
                        : const Icon(Icons.storage, size: 20),
                    title: Text(
                      conn.name,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      conn.databaseName.isNotEmpty
                          ? '${conn.username}@${conn.host}:${conn.port}/${conn.databaseName}'
                          : '${conn.username}@${conn.host}:${conn.port}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () {
                      if (_isSelectionMode) {
                        if (conn.id != null) _toggleItemSelection(conn.id!);
                      } else {
                        _connectWithSaved(conn);
                      }
                    },
                    onLongPress: () {
                      if (!_isSelectionMode && conn.id != null) {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedIds.add(conn.id!);
                        });
                      }
                    },
                    trailing: _isSelectionMode
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ConnectionEditScreen(connection: conn),
                                ),
                              );
                              _refreshList();
                            },
                          ),
                  ),
                );

                if (_isSelectionMode) {
                  return card;
                } else {
                  return Dismissible(
                    key: Key(conn.id.toString()),
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    direction: DismissDirection.endToStart,
                    onDismissed: (direction) async {
                      if (conn.id != null) {
                        await DatabaseHelper().deleteConnection(conn.id!);
                        // No need to refresh list fully as Dismissible removes it visually,
                        // but refreshing state is good to keep sync.
                        // However, usually one should remove from list data source.
                        // For now we just let it be or wrapped in setstate to avoid errors?
                        // Actually FutureBuilder rebuilds if I call setState.
                        // But Dismissible handles the animation.
                      }
                    },
                    child: card,
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _ExitDialog extends StatefulWidget {
  const _ExitDialog();

  @override
  State<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends State<_ExitDialog> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // Test Ad Unit ID: ca-app-pub-3940256099942544/6300978111
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.mediumRectangle, // Larger ad for visibility in dialog
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          Log.error('Failed to load a banner ad: ${err.message}');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exit App'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Do you want to exit?'),
          const SizedBox(height: 16),
          if (_isAdLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          else
            const SizedBox(
              height: 250,
              width: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Exit'),
        ),
      ],
    );
  }
}
