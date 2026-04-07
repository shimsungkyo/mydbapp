class SavedConnection {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String databaseName;
  final bool useSsh;
  final String? sshHost;
  final int? sshPort;
  final String? sshUsername;
  final String? sshPassword;
  final String? sshKeyPath;

  SavedConnection({
    this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.databaseName,
    this.useSsh = false,
    this.sshHost,
    this.sshPort,
    this.sshUsername,
    this.sshPassword,
    this.sshKeyPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'database_name': databaseName,
      'use_ssh': useSsh ? 1 : 0,
      'ssh_host': sshHost,
      'ssh_port': sshPort,
      'ssh_username': sshUsername,
      'ssh_password': sshPassword,
      'ssh_key_path': sshKeyPath,
    };
  }

  factory SavedConnection.fromMap(Map<String, dynamic> map) {
    return SavedConnection(
      id: map['id'],
      name: map['name'],
      host: map['host'],
      port: map['port'],
      username: map['username'],
      password: map['password'],
      databaseName: map['database_name'],
      useSsh: map['use_ssh'] == 1,
      sshHost: map['ssh_host'],
      sshPort: map['ssh_port'],
      sshUsername: map['ssh_username'],
      sshPassword: map['ssh_password'],
      sshKeyPath: map['ssh_key_path'],
    );
  }
}
