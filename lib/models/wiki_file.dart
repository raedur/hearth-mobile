class WikiFile {
  final String path;
  final String name;
  final String? lastModified;

  const WikiFile({required this.path, required this.name, this.lastModified});

  factory WikiFile.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String;
    return WikiFile(
      path: path,
      name: json['name'] as String? ?? path.split('/').last,
      lastModified: json['last_modified'] as String?,
    );
  }
}
