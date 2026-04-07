import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ssh_config.dart';
import '../models/db_config.dart';
import 'database_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class ConnectionManager {
    static final ConnectionManager _instance = ConnectionManager._internal();
    factory ConnectionManager() => _instance;
    ConnectionManager._internal();

    final DatabaseService _dbService = DatabaseService();
    
    // Removed SSHConfig and DBConfig for reconnection
    
    // bool _isExplicitDisconnect = false; // Kept if needed for other logic, but let's see
    // Actually, let's keep it simple.


    final ValueNotifier<ConnectionStatus> statusNotifier = ValueNotifier(ConnectionStatus.disconnected);
    final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

    Future<void> connect(SSHConfig? sshConfig, DBConfig dbConfig) async {
        
        statusNotifier.value = ConnectionStatus.connecting;
        errorNotifier.value = null;

        try {
            await _dbService.connect(sshConfig, dbConfig);
            statusNotifier.value = ConnectionStatus.connected;
        } catch (e) {
            statusNotifier.value = ConnectionStatus.error;
            errorNotifier.value = e.toString();
            // Optional: Auto-retry on initial failure? Usually better to let user retry.
        }
    }

    Future<void> disconnect() async {
        await _dbService.disconnect(clearCredentials: true);
        statusNotifier.value = ConnectionStatus.disconnected;
    }


}
