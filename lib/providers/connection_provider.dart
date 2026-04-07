import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/connection_manager.dart';
import '../models/ssh_config.dart';
import '../models/db_config.dart';

class ConnectionProvider extends ChangeNotifier {
  final ConnectionManager _connectionManager = ConnectionManager();
  
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _error;
  // Removed state for reconnection


  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isLoading => _status == ConnectionStatus.connecting;
  String? get error => _error;

  ConnectionProvider() {
    // Listen to manager updates
    _connectionManager.statusNotifier.addListener(() {
      _status = _connectionManager.statusNotifier.value;
      notifyListeners();
    });
    
    _connectionManager.errorNotifier.addListener(() {
      _error = _connectionManager.errorNotifier.value;
      notifyListeners();
    });
  }

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required String databaseName,
    bool useSsh = false,
    String? sshHost,
    int? sshPort,
    String? sshUsername,
    String? sshPassword,
    String? sshKeyPath,
  }) async {
    _error = null;
    notifyListeners();


    try {
      final dbConfig = DBConfig(
        host: host,
        port: port,
        username: username,
        password: password,
        databaseName: databaseName,
      );

      SSHConfig? sshConfig;
      if (useSsh && sshHost != null && sshUsername != null) {
          String? privateKeyContent;
          if (sshKeyPath != null && sshKeyPath.isNotEmpty) {
             try {
               final file = File(sshKeyPath);
               if (await file.exists()) {
                 privateKeyContent = await file.readAsString();
               } else {
                 // Treat as content if not file? Or just ignore/fail?
                 // For now, assume if it looks like a key (starts with ----) it is content
                 if (sshKeyPath.trim().startsWith('-----BEGIN')) {
                    privateKeyContent = sshKeyPath;
                 }
               }
             } catch (e) {
               // Ignore file error, maybe it is content
                if (sshKeyPath.trim().startsWith('-----BEGIN')) {
                    privateKeyContent = sshKeyPath;
                 }
             }
          }

          sshConfig = SSHConfig(
            host: sshHost,
            port: sshPort ?? 22,
            username: sshUsername,
            password: sshPassword,
            privateKey: privateKeyContent, 
          );
      }
      
      await _connectionManager.connect(sshConfig, dbConfig);
      
    } catch (e) {
      // Errors are handled via the notifier usually, but initial connect might throw
      _error = e.toString();
      notifyListeners();
      rethrow; // Rethrow so UI can catch it
    }
  }



  Future<void> disconnect() async {
    await _connectionManager.disconnect();
  }
  
  
  @override
  void dispose() {
    // Clean up listeners if needed, though provider usually lives long
    super.dispose();
  }
}
