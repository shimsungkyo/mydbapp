class SSHConfig {
  final String host;
  final int port;
  final String username;
  final String? privateKey; 
  final String? password;

  SSHConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.privateKey,
    this.password,
  }) : assert(privateKey != null || password != null, 'Either privateKey or password must be provided');
}
