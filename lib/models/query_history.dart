class QueryHistory {
  final int? id;
  final String query;
  final DateTime executedAt;
  final bool success;
  final int executionTimeMs;

  QueryHistory({
    this.id,
    required this.query,
    required this.executedAt,
    required this.success,
    required this.executionTimeMs,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'query': query,
      'executed_at': executedAt.toIso8601String(),
      'success': success ? 1 : 0,
      'execution_time_ms': executionTimeMs,
    };
  }

  factory QueryHistory.fromMap(Map<String, dynamic> map) {
    return QueryHistory(
      id: map['id'],
      query: map['query'],
      executedAt: DateTime.parse(map['executed_at']),
      success: map['success'] == 1,
      executionTimeMs: map['execution_time_ms'],
    );
  }
}
