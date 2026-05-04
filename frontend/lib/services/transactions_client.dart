import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/transaction.dart';
import 'api_base.dart';

/// Backend-shaped transaction row. Translates to/from in-app `Transaction`
/// in the screen layer.
class TransactionDto {
  TransactionDto({
    required this.id,
    required this.date,
    required this.merchant,
    required this.amount,
    this.categoryId,
    this.categoryPath,
  });

  final int id;
  final String date;        // ISO YYYY-MM-DD
  final String merchant;
  final double amount;
  final int? categoryId;
  final String? categoryPath;

  factory TransactionDto.fromJson(Map<String, dynamic> j) => TransactionDto(
        id: j['id'] as int,
        date: j['date'] as String,
        merchant: j['merchant'] as String,
        amount: (j['amount'] as num).toDouble(),
        categoryId: j['category_id'] as int?,
        categoryPath: j['category_path'] as String?,
      );

  /// Convert to the in-app `Transaction` model. The in-app model uses
  /// `category` as the *path string* (e.g. `"Living / Grocery"`); when
  /// uncategorised, it's null.
  Transaction toTransaction() => Transaction(
        id: id.toString(),
        date: date,
        merchant: merchant,
        amount: amount,
        category: categoryPath,
      );
}

class TransactionsClient {
  TransactionsClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// ISO date of the most-recent transaction, or null when the table is
  /// empty. Used by AppShell to default to a cycle that has data.
  Future<String?> latestDate() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/transactions/latest_date'));
    final json = decodeOrThrow(resp) as Map<String, dynamic>;
    return json['date'] as String?;
  }

  Future<List<TransactionDto>> list({
    String? startDate,
    String? endDate,
    int? categoryId,
    String? categoryPath,
    bool uncategorised = false,
    String? merchantQuery,
    int limit = 500,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'start_date': ?startDate,
      'end_date': ?endDate,
      'category_id': ?categoryId?.toString(),
      'category_path': ?categoryPath,
      if (uncategorised) 'uncategorised': 'true',
      'merchant_query': ?merchantQuery,
    };
    final uri = Uri.parse('$apiBaseUrl/transactions').replace(queryParameters: params);
    final resp = await _client.get(uri);
    final body = decodeOrThrow(resp) as List;
    return body.map((j) => TransactionDto.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<TransactionDto> update(
    int id, {
    String? date,
    String? merchant,
    double? amount,
    int? categoryId,
    bool categoryExplicit = false,
  }) async {
    final body = <String, dynamic>{};
    if (date != null) body['date'] = date;
    if (merchant != null) body['merchant'] = merchant;
    if (amount != null) body['amount'] = amount;
    if (categoryExplicit) body['category_id'] = categoryId;
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/transactions/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return TransactionDto.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  Future<void> delete(int id) async {
    final resp = await _client.delete(Uri.parse('$apiBaseUrl/transactions/$id'));
    decodeOrThrow(resp);
  }

  /// Bulk rename — every transaction whose merchant matches `from` exactly
  /// gets renamed to `to`. Returns the count.
  Future<int> bulkRename({required String from, required String to}) async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/transactions/bulk_rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'from_merchant': from, 'to_merchant': to}),
    );
    final body = decodeOrThrow(resp) as Map<String, dynamic>;
    return body['updated'] as int;
  }

  /// Upload a statement file. `parser` defaults to "csv"; "ai" requires the
  /// master `ai` feature flag on the server side and 403s otherwise.
  ///
  /// Sets a Content-Type per file extension so the backend can identify the
  /// payload. The default `MultipartFile.fromBytes` content-type is
  /// `application/octet-stream`, which the AI parser refuses to forward to
  /// Claude — sending unidentified bytes to the model has cost users real
  /// money in the past.
  Future<ImportResult> import({
    required List<int> bytes,
    required String filename,
    String parser = 'csv',
  }) async {
    final req = http.MultipartRequest(
      'POST', Uri.parse('$apiBaseUrl/transactions/import'),
    )
      ..fields['parser'] = parser
      ..files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: filename,
        contentType: _contentTypeFor(filename),
      ));
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    final json = decodeOrThrow(resp) as Map<String, dynamic>;
    return ImportResult.fromJson(json);
  }

  static MediaType _contentTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (lower.endsWith('.csv')) return MediaType('text', 'csv');
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('application', 'octet-stream');
  }

  void dispose() => _client.close();
}

class ImportResult {
  ImportResult({
    required this.formatDetected,
    required this.rowsParsed,
    required this.rowsInserted,
    required this.rowsSkippedDuplicate,
    required this.rowsFailed,
    required this.errors,
    this.categorization,
  });

  final String formatDetected;
  final int rowsParsed;
  final int rowsInserted;
  final int rowsSkippedDuplicate;
  final int rowsFailed;
  final List<Map<String, dynamic>> errors;
  final CategorizationResult? categorization;

  factory ImportResult.fromJson(Map<String, dynamic> j) => ImportResult(
        formatDetected: j['format_detected'] as String,
        rowsParsed: j['rows_parsed'] as int,
        rowsInserted: j['rows_inserted'] as int,
        rowsSkippedDuplicate: j['rows_skipped_duplicate'] as int,
        rowsFailed: j['rows_failed'] as int,
        errors: (j['errors'] as List? ?? [])
            .map((e) => (e as Map<String, dynamic>))
            .toList(),
        categorization: j['categorization'] is Map<String, dynamic>
            ? CategorizationResult.fromJson(j['categorization'] as Map<String, dynamic>)
            : null,
      );

  String get summary {
    final parts = <String>[
      '$rowsInserted added',
      if (rowsSkippedDuplicate > 0) '$rowsSkippedDuplicate duplicate'
                                      '${rowsSkippedDuplicate == 1 ? "" : "s"} skipped',
      if (rowsFailed > 0) '$rowsFailed failed',
    ];
    final cat = categorization;
    if (cat != null) {
      if (cat.error == null) {
        parts.add('${cat.categorized} categorized');
      } else if (cat.error == 'ai_key_missing') {
        parts.add('AI key not set — set one in Account to auto-categorize');
      } else {
        parts.add('AI categorize failed');
      }
    }
    return parts.join(' · ');
  }
}

/// Mirror of the backend's `categorization` block on `/transactions/import`.
class CategorizationResult {
  const CategorizationResult({
    required this.attempted,
    required this.categorized,
    required this.skippedNoMatch,
    this.error,
  });

  final int attempted;
  final int categorized;
  final int skippedNoMatch;
  final String? error;

  factory CategorizationResult.fromJson(Map<String, dynamic> j) =>
      CategorizationResult(
        attempted: j['attempted'] as int? ?? 0,
        categorized: j['categorized'] as int? ?? 0,
        skippedNoMatch: j['skipped_no_match'] as int? ?? 0,
        error: j['error'] as String?,
      );
}
