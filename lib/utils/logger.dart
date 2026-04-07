import 'dart:developer' as developer;

class Log {
  static const String prefix = '[DbApp]';

  static void info(String message, {String? tag}) {
    _log(message, name: tag ?? 'INFO');
  }

  static void debug(String message, {String? tag}) {
    _log(message, name: tag ?? 'DEBUG');
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(
      message,
      name: tag ?? 'ERROR',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _log(String message, {required String name, Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: '$prefix $name',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
