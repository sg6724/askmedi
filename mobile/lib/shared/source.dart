/// A cited web source: `{"title": "...", "url": "https://..."}`.
class Source {
  const Source({required this.title, required this.url});

  factory Source.fromJson(Map<String, dynamic> json) =>
      Source(title: (json['title'] as String?) ?? '', url: (json['url'] as String?) ?? '');

  final String title;
  final String url;

  static List<Source> listFrom(Object? json) => [
        for (final s in (json as List?) ?? const [])
          Source.fromJson(Map<String, dynamic>.from(s as Map)),
      ];
}

List<String> stringList(Object? json) =>
    [for (final s in (json as List?) ?? const []) s.toString()];
