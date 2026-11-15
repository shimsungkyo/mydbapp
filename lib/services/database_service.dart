import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:mysql_client/mysql_client.dart';

import '../models/ssh_config.dart';
import '../models/db_config.dart';
// import 'connection_manager.dart';
import '../utils/logger.dart';

class DatabaseService {
  // Singleton instance
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  SSHClient? _sshClient;
  MySQLConnection? _dbConnection;
  ServerSocket? _forwardingServer;

  bool get isConnected => _dbConnection != null && _dbConnection!.connected;

  Future<void> connect(
    SSHConfig? sshConfig,
    DBConfig dbConfig, {
    int localForwardPort = 3307,
  }) async {
    // Determine connection candidates
    final candidates = <String>[dbConfig.host];

    if (sshConfig != null) {
      // If tunneling, we might want to try loopback addresses on the remote server
      if (dbConfig.host != '127.0.0.1' && !candidates.contains('127.0.0.1')) {
        candidates.add('127.0.0.1');
      }
      if (dbConfig.host != 'localhost' && !candidates.contains('localhost')) {
        candidates.add('localhost');
      }
    }

    Object? lastError; // Keep track of the last error to throw if all fail

    for (final hostCandidate in candidates) {
      try {
        Log.info('Attempting connection to DB host: $hostCandidate ...');
        final configToUse = DBConfig(
          host: hostCandidate,
          port: dbConfig.port,
          username: dbConfig.username,
          password: dbConfig.password,
          databaseName: dbConfig.databaseName,
        );

        await _attemptConnection(sshConfig, configToUse, localForwardPort);
        Log.info('Connected successfully using host: $hostCandidate');
        return; // Success!
      } catch (e) {
        Log.error('Failed to connect to $hostCandidate: $e');
        lastError = e;

        // Cleanup before next attempt
        try {
          await _dbConnection?.close();
        } catch (_) {}
        try {
          await _forwardingServer?.close();
        } catch (_) {}
        try {
          _sshClient?.close();
        } catch (_) {} // Also reset SSH between attempts to be safe?
        // Actually _attemptConnection re-creates SSH Client so we should close it.
        _sshClient = null;
      }
    }

    // If we get here, all attempts failed
    Log.error('All connection attempts failed. Last error: $lastError');
    if (lastError != null) throw lastError;
  }

  Future<void> _attemptConnection(
    SSHConfig? sshConfig,
    DBConfig dbConfig,
    int localForwardPort,
  ) async {
    if (sshConfig != null) {
      Log.info('Connecting to SSH Jump Host: ${sshConfig.host}...');

      final socket = await SSHSocket.connect(sshConfig.host, sshConfig.port);

      _sshClient = SSHClient(
        socket,
        username: sshConfig.username,
        onPasswordRequest: () {
          return sshConfig.password;
        },
        identities: sshConfig.privateKey != null
            ? [...SSHKeyPair.fromPem(sshConfig.privateKey!)]
            : [],
      );

      Log.info('SSH Connected. Setting up tunnel...');

      if (_forwardingServer != null) {
        try {
          await _forwardingServer!.close();
        } catch (_) {}
      }

      try {
        _forwardingServer = await ServerSocket.bind(
          '127.0.0.1',
          localForwardPort,
        );
      } catch (e) {
        Log.error(
          'Failed to bind local port $localForwardPort, trying random port...',
        );
        _forwardingServer = await ServerSocket.bind('127.0.0.1', 0);
        localForwardPort = _forwardingServer!.port;
      }

      _forwardingServer!.listen((clientSocket) async {
        Log.debug('Tunnel: Client connected to local port $localForwardPort');
        try {
          Log.debug(
            'Tunnel: Requesting forwarding to ${dbConfig.host}:${dbConfig.port}...',
          );
          final channel = await _sshClient!.forwardLocal(
            dbConfig.host,
            dbConfig.port,
          );
          Log.debug('Tunnel: Forwarding channel accepted by remote SSH server.');

          clientSocket.listen(
            (data) {
              Log.debug('Tunnel: Client -> Remote (${data.length} bytes)');
              channel.sink.add(data);
            },
            onDone: () {
              Log.debug('Tunnel: Client connection closed');
              channel.close();
            },
            onError: (e) {
              Log.error('Tunnel: Client socket error: $e');
              channel.close();
            },
          );

          channel.stream.listen(
            (data) {
              Log.debug('Tunnel: Remote -> Client (${data.length} bytes)');
              clientSocket.add(data);
            },
            onDone: () {
              Log.debug('Tunnel: Remote channel closed');
              clientSocket.destroy(); // Force release
            },
            onError: (e) {
              Log.error('Tunnel: Remote channel error: $e');
              clientSocket.destroy(); // Force release
            },
          );
        } catch (e) {
          Log.error('Tunnel forwarding error: $e');
          clientSocket.destroy();
        }
      });

      Log.info(
        'Tunnel established on 127.0.0.1:$localForwardPort -> ${dbConfig.host}:${dbConfig.port}',
      );
    } else {
      Log.info('SSH Config not provided. Connecting directly to database...');
    }

    Log.info('Connecting to Database${sshConfig != null ? ' via Tunnel' : ''}...');

    final targetHost = sshConfig != null ? '127.0.0.1' : dbConfig.host;
    final targetPort = sshConfig != null ? localForwardPort : dbConfig.port;

    // Delay to ensure tunnel is ready
    await Future.delayed(const Duration(milliseconds: 500));

    Log.info('Connecting to DatabaseClient...');
    _dbConnection = await MySQLConnection.createConnection(
      host: targetHost,
      port: targetPort,
      userName: dbConfig.username,
      password: dbConfig.password,
      databaseName: dbConfig.databaseName.trim().isNotEmpty ? dbConfig.databaseName.trim() : null,
      secure: false,
    );

    await _dbConnection!.connect(timeoutMs: 10000);

    Log.info('Database Connected successfully!');
  }

  Future<void> disconnect({bool clearCredentials = true}) async {
    Log.info('Disconnecting...');
    try {
      await _dbConnection?.close();
    } catch (e) {
      Log.error('Error closing DB: $e');
    }
    _dbConnection = null;

    try {
      await _forwardingServer?.close();
    } catch (e) {
      Log.error('Error closing Server: $e');
    }
    _forwardingServer = null;

    try {
      _sshClient?.close();
    } catch (e) {
      Log.error('Error closing SSH: $e');
    }
    _sshClient = null;

    Log.info('Disconnected.');
  }

  // Wrapper for database operations
  Future<T> _executeWithRetry<T>(Future<T> Function() operation) async {
    if (_dbConnection == null || !_dbConnection!.connected) {
      throw Exception('Database is not connected. Please connect first.');
    }
    return await operation();
  }

  Future<IResultSet> executeQuery(
    String query, [
    Map<String, dynamic>? params,
  ]) async {
    return await _executeWithRetry(() => _dbConnection!.execute(query, params));
  }

  Future<List<Map<String, String>>> getTables() async {
    return await _executeWithRetry(() async {
      final query = """
        SELECT 
          TABLE_NAME,
          TABLE_COMMENT,
          ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS SIZE_MB,
          TABLE_ROWS,
          CREATE_TIME
        FROM 
          information_schema.TABLES
        WHERE 
          TABLE_SCHEMA = DATABASE()
        ORDER BY 
          TABLE_NAME ASC
      """;

      final results = await _dbConnection!.execute(query);
      final tables = <Map<String, String>>[];

      for (var row in results.rows) {
        tables.add({
          'name': row.colAt(0) ?? '',
          'comment': row.colAt(1) ?? '',
          'size_mb': row.colAt(2) ?? '0',
          'rows': row.colAt(3) ?? '0',
          'created': row.colAt(4) ?? '',
        });
      }
      return tables;
    });
  }

  Future<List<Map<String, String>>> getTableSchema(String tableName) async {
    return await _executeWithRetry(() async {
      final query = "DESCRIBE $tableName";
      final results = await _dbConnection!.execute(query);

      final schema = <Map<String, String>>[];
      for (var row in results.rows) {
        schema.add({
          'Field': row.colAt(0) ?? '',
          'Type': row.colAt(1) ?? '',
          'Null': row.colAt(2) ?? '',
          'Key': row.colAt(3) ?? '',
          'Default': row.colAt(4) ?? '',
          'Extra': row.colAt(5) ?? '',
        });
      }
      return schema;
    });
  }

  Future<List<String>> getDatabases() async {
    return await _executeWithRetry(() async {
      final results = await _dbConnection!.execute("SHOW DATABASES");
      final databases = <String>[];
      for (var row in results.rows) {
        databases.add(row.colAt(0) ?? '');
      }
      return databases;
    });
  }

  Future<void> changeDatabase(String dbName) async {
    await _executeWithRetry(() => _dbConnection!.execute("USE $dbName"));
  }

  Future<String> getCurrentDatabase() async {
    return await _executeWithRetry(() async {
      final results = await _dbConnection!.execute("SELECT DATABASE()");
      if (results.rows.isNotEmpty) {
        return results.rows.first.colAt(0) ?? '';
      }
      return '';
    });
  }

  Future<String> exportTableToSql(String tableName) async {
    return await _executeWithRetry(() async {
      final sb = StringBuffer();
      sb.writeln('-- SQL Dump for table: $tableName');
      sb.writeln('-- Generated by Database Dashboard');
      sb.writeln('SET FOREIGN_KEY_CHECKS=0;');
      sb.writeln();

      // 1. Get Create Table
      try {
        final createResult = await _dbConnection!.execute(
          "SHOW CREATE TABLE $tableName",
        );
        if (createResult.rows.isNotEmpty) {
          sb.writeln('DROP TABLE IF EXISTS `$tableName`;');
          sb.writeln(createResult.rows.first.colAt(1));
          sb.writeln(';');
          sb.writeln();
        }
      } catch (e) {
        sb.writeln('-- Error getting create table: $e');
      }

      // 2. Get Data
      try {
        final dataResult = await _dbConnection!.execute(
          "SELECT * FROM $tableName",
        );
        if (dataResult.rows.isNotEmpty) {
          sb.writeln('LOCK TABLES `$tableName` WRITE;');
          sb.writeln('/*!40000 ALTER TABLE `$tableName` DISABLE KEYS */;');

          for (var row in dataResult.rows) {
            final values = <String>[];
            for (var val in row.assoc().values) {
              if (val == null) {
                values.add('NULL');
              } else {
                final escaped = val
                    .replaceAll("'", "''")
                    .replaceAll(r'\', r'\\');
                values.add("'$escaped'");
              }
            }
            sb.writeln(
              "INSERT INTO `$tableName` VALUES (${values.join(', ')});",
            );
          }

          sb.writeln('/*!40000 ALTER TABLE `$tableName` ENABLE KEYS */;');
          sb.writeln('UNLOCK TABLES;');
        }
      } catch (e) {
        sb.writeln('-- Error getting data: $e');
      }

      sb.writeln('SET FOREIGN_KEY_CHECKS=1;');
      return sb.toString();
    });
  }

  Future<String> exportTableToCsv(String tableName) async {
    return await _executeWithRetry(() async {
      final sb = StringBuffer();
      final dataResult = await _dbConnection!.execute(
        "SELECT * FROM $tableName",
      );

      if (dataResult.cols.isNotEmpty) {
        sb.writeln(dataResult.cols.map((c) => '"${c.name}"').join(','));
        for (var row in dataResult.rows) {
          final values = <String>[];
          for (var val in row.assoc().values) {
            if (val == null) {
              values.add('');
            } else {
              final escaped = val.replaceAll('"', '""');
              values.add('"$escaped"');
            }
          }
          sb.writeln(values.join(','));
        }
      }
      return sb.toString();
    });
  }

  Future<void> deleteRow(
    String tableName,
    String pkColumn,
    dynamic pkValue,
  ) async {
    await _executeWithRetry(() async {
      final query = "DELETE FROM `$tableName` WHERE `$pkColumn` = :pk";
      await _dbConnection!.execute(query, {'pk': pkValue});
    });
  }

  Future<void> insertRow(String tableName, Map<String, dynamic> data) async {
    await _executeWithRetry(() async {
      final columns = data.keys.map((k) => "`$k`").join(', ');
      final placeholders = data.keys.map((k) => ":$k").join(', ');
      final query =
          "INSERT INTO `$tableName` ($columns) VALUES ($placeholders)";
      await _dbConnection!.execute(query, data);
    });
  }

  Future<void> updateRow(
    String tableName,
    String pkColumn,
    dynamic pkValue,
    Map<String, dynamic> data,
  ) async {
    await _executeWithRetry(() async {
      final setClause = data.keys.map((k) => "`$k` = :$k").join(', ');
      final query =
          "UPDATE `$tableName` SET $setClause WHERE `$pkColumn` = :pkValue";
      final params = Map<String, dynamic>.from(data);
      params['pkValue'] = pkValue;
      await _dbConnection!.execute(query, params);
    });
  }

  Future<String> getTableDDL(String tableName) async {
    return await _executeWithRetry(() async {
      final createResult = await _dbConnection!.execute(
        "SHOW CREATE TABLE `$tableName`",
      );
      if (createResult.rows.isNotEmpty) {
        return createResult.rows.first.colAt(1) ?? '-- DDL not found';
      }
      return '-- DDL not found';
    });
  }

  Future<void> truncateTable(String tableName) async {
    await _executeWithRetry(
      () => _dbConnection!.execute("TRUNCATE TABLE `$tableName`"),
    );
  }

  Future<void> dropTable(String tableName) async {
    await _executeWithRetry(
      () => _dbConnection!.execute("DROP TABLE `$tableName`"),
    );
  }
}
