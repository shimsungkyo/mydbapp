class SavedQuery {
  final int? id;
  final String name;
  final String query;
  final DateTime createdAt;

  SavedQuery({
    this.id,
    required this.name,
    required this.query,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'query': query,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SavedQuery.fromMap(Map<String, dynamic> map) {
    return SavedQuery(
      id: map['id'],
      name: map['name'],
      query: map['query'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
