import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/saved_connection.dart';
import '../providers/connection_provider.dart';
import '../services/database_helper.dart';
import 'dashboard_screen.dart';

class ConnectionEditScreen extends StatefulWidget {
  final SavedConnection? connection; // If null, it's a new connection

  const ConnectionEditScreen({super.key, this.connection});

  @override
  State<ConnectionEditScreen> createState() => _ConnectionEditScreenState();
}

class _ConnectionEditScreenState extends State<ConnectionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '3306');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _dbNameController = TextEditingController();
  
  // SSH Controllers
  bool _useSsh = false;
  final _sshHostController = TextEditingController();
  final _sshPortController = TextEditingController(text: '22');
  final _sshUsernameController = TextEditingController();
  final _sshPasswordController = TextEditingController();
  final _sshKeyPathController = TextEditingController(); // Not fully UI implemented but in model

  bool _isConnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      final c = widget.connection!;
      _nameController.text = c.name;
      _hostController.text = c.host;
      _portController.text = c.port.toString();
      _usernameController.text = c.username;
      _passwordController.text = c.password;
      _dbNameController.text = c.databaseName;
      
      _useSsh = c.useSsh;
      if (_useSsh) {
        _sshHostController.text = c.sshHost ?? '';
        _sshPortController.text = c.sshPort?.toString() ?? '22';
        _sshUsernameController.text = c.sshUsername ?? '';
        _sshPasswordController.text = c.sshPassword ?? '';
        _sshKeyPathController.text = c.sshKeyPath ?? '';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _dbNameController.dispose();
    
    _sshHostController.dispose();
    _sshPortController.dispose();
    _sshUsernameController.dispose();
    _sshPasswordController.dispose();
    _sshKeyPathController.dispose();
    super.dispose();
  }

  Future<void> _connectAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final provider = Provider.of<ConnectionProvider>(context, listen: false);

    try {
      // 1. Attempt Connection
      // Note: Provider creates DBConfig/SSHConfig internally from these params or we can refactor connect to take configs.
      // For now we use the existing simple connect if no SSH, but we need SSH support in provider.
      // Wait, provider.connect currently doesn't take SSH params in the signature I saw earlier! 
      // I need to update provider to support SSH params OR handle connection manually here to test.
      // Let's assume for now we just support direct DB connect in this pass, OR 
      // I should have refactored provider first. 
      // ACTUALLY, I'll update the provider to accept optional SSH details in the next step. 
      // For now, I'll pass basic details.
      
      // Temporary check: If user wants SSH, we might fail if provider isn't updated.
      // I'll assume provider.connect will be updated to take SSH args.
      
      await provider.connect(
        host: _hostController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text,
        password: _passwordController.text,
        databaseName: _dbNameController.text,
        // TODO: Pass SSH params
        useSsh: _useSsh,
        sshHost: _sshHostController.text.isNotEmpty ? _sshHostController.text : null,
        sshPort: int.tryParse(_sshPortController.text),
        sshUsername: _sshUsernameController.text.isNotEmpty ? _sshUsernameController.text : null,
        sshPassword: _sshPasswordController.text.isNotEmpty ? _sshPasswordController.text : null,
        sshKeyPath: _sshKeyPathController.text.isNotEmpty ? _sshKeyPathController.text : null,
      );

      // 2. If successful, Save to DB
      final newConnection = SavedConnection(
        id: widget.connection?.id, // Keep ID if editing
        name: _nameController.text.isEmpty ? '${_usernameController.text}@${_hostController.text}' : _nameController.text,
        host: _hostController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text,
        password: _passwordController.text,
        databaseName: _dbNameController.text,
        useSsh: _useSsh,
        sshHost: _useSsh ? _sshHostController.text : null,
        sshPort: _useSsh ? int.tryParse(_sshPortController.text) : null,
        sshUsername: _useSsh ? _sshUsernameController.text : null,
        sshPassword: _useSsh ? _sshPasswordController.text : null,
        sshKeyPath: _useSsh ? _sshKeyPathController.text : null,
      );

      await DatabaseHelper().insertConnection(newConnection);

      if (mounted) {
        // 3. Navigate to Dashboard
        // 3. Navigate to Dashboard
        Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (_) => DashboardScreen())
        );
      }

    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Connection Failed'),
            content: Text('Connection failed: $e'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.connection == null ? 'New Connection' : 'Edit Connection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Connection Name (Optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Database Details', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(labelText: 'Host', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dbNameController,
                decoration: const InputDecoration(labelText: 'Database Name', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ), // SSH Section
              const SizedBox(height: 16),
              SwitchListTile(
                 title: const Text('Use SSH Tunnel'),
                 value: _useSsh,
                 onChanged: (val) {
                    if (val) {
                      setState(() => _useSsh = val);
                    } else {
                       setState(() => _useSsh = val);
                    }
                 },
              ),
              if (_useSsh) ...[
                 Container(
                   padding: const EdgeInsets.all(8),
                   color: Theme.of(context).colorScheme.surfaceContainerHighest,
                   child: Column(
                     children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _sshHostController,
                                decoration: const InputDecoration(labelText: 'SSH Host', border: OutlineInputBorder()),
                                validator: (v) => _useSsh && v!.isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _sshPortController,
                                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _sshUsernameController,
                          decoration: const InputDecoration(labelText: 'SSH Username', border: OutlineInputBorder()),
                          validator: (v) => _useSsh && v!.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _sshPasswordController,
                          decoration: const InputDecoration(labelText: 'SSH Password', border: OutlineInputBorder()),
                          obscureText: true,
                        ),
                        // Key path...
                     ],
                   ),
                 ),
              ],
              
              const SizedBox(height: 24),
              if (_error != null)
                Container(
                   padding: const EdgeInsets.all(8),
                   color: Theme.of(context).colorScheme.errorContainer,
                   child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isConnecting ? null : _connectAndSave,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _isConnecting 
                   ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                   : const Text('Connect & Save'),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }
}
