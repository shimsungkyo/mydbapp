class DBConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String databaseName;

  DBConfig({
    required this.host,
    this.port = 3306,
    required this.username,
    required this.password,
    this.databaseName = '',
  });
}
