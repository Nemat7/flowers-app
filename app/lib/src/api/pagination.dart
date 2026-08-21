/// Пагинация списков спеки: `{count, next, previous, results}`.
class Paginated<T> {
  const Paginated({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> json) parse,
  ) =>
      Paginated(
        count: json['count'] as int? ?? 0,
        next: json['next'] as String?,
        previous: json['previous'] as String?,
        results: (json['results'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(parse)
            .toList(),
      );

  final int count;
  final String? next;
  final String? previous;
  final List<T> results;
}
