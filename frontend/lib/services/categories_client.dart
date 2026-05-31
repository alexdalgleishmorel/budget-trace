import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';

/// Backend-shaped category row. We keep this as a thin DTO and convert to
/// the in-app `BudgetCategory` tree in AppShell.
class CategoryDto {
  CategoryDto({
    required this.id,
    required this.name,
    required this.parentId,
    required this.path,
    required this.isLeaf,
    required this.isUnknown,
    required this.color,
    this.description,
  });

  final int id;
  final String name;
  final int? parentId;
  final String path;
  final bool isLeaf;
  final bool isUnknown;
  final String? description;
  final String color;

  factory CategoryDto.fromJson(Map<String, dynamic> j) => CategoryDto(
        id: j['id'] as int,
        name: j['name'] as String,
        parentId: j['parent_id'] as int?,
        path: j['path'] as String,
        isLeaf: j['is_leaf'] as bool,
        isUnknown: j['is_unknown'] as bool,
        description: j['description'] as String?,
        color: j['color'] as String,
      );
}

class CategoriesClient {
  CategoriesClient({http.Client? client}) : _client = client ?? makeHttpClient();

  final http.Client _client;

  Future<List<CategoryDto>> list() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/categories'));
    final body = decodeOrThrow(resp) as List;
    return body.map((j) => CategoryDto.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<CategoryDto> create({
    required String name,
    String? description,
    int? parentId,
    String? color,
  }) async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/categories'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'description': ?description,
        'parent_id': ?parentId,
        'color': ?color,
      }),
    );
    return CategoryDto.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  /// Pass `descriptionExplicit: true` if you want `description: null` to mean
  /// "clear it" (omitting `description` always means "no change"). `color`
  /// is non-nullable on the server; omitting it means "no change".
  Future<CategoryDto> update(
    int id, {
    String? name,
    String? description,
    int? parentId,
    String? color,
    bool descriptionExplicit = false,
    bool parentExplicit = false,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (descriptionExplicit) body['description'] = description;
    if (parentExplicit) body['parent_id'] = parentId;
    if (color != null) body['color'] = color;
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/categories/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return CategoryDto.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  Future<void> delete(int id) async {
    final resp = await _client.delete(Uri.parse('$apiBaseUrl/categories/$id'));
    decodeOrThrow(resp);
  }

  /// Bulk-create the backend's `DEFAULT_CATEGORY_TREE` under the existing
  /// Budget root. The backend refuses with 409 (`categories_exist`) if any
  /// non-root category already exists — strictly a "from scratch" affordance.
  Future<List<CategoryDto>> seedDefaults() async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/categories/seed_defaults'),
    );
    final body = decodeOrThrow(resp) as List;
    return body.map((j) => CategoryDto.fromJson(j as Map<String, dynamic>)).toList();
  }

  void dispose() => _client.close();
}
