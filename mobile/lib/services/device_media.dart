import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../app_state.dart';

class PickedMedia {
  PickedMedia(
    this.path,
    this.name,
    this.mime,
    this.size, {
    this.thumbnailPath,
    this.duration,
  });
  final String path, name, mime;
  final int size;
  final String? thumbnailPath;
  final int? duration;
  bool get video => mime.startsWith('video/');
  static Future<PickedMedia?> pick({String kind = 'media'}) async {
    final result = await const MethodChannel(
      'app/media',
    ).invokeMapMethod<String, dynamic>('pick', {'kind': kind});
    if (result == null) return null;
    return PickedMedia(
      result['path'] as String,
      result['name'] as String,
      result['mime'] as String,
      (result['size'] as num).toInt(),
      thumbnailPath: result['thumbnail_path'] as String?,
      duration: (result['duration_s'] as num?)?.toInt(),
    );
  }
}

Future<void> uploadMedia(
  AppState state,
  String bucket,
  String key,
  PickedMedia file,
  void Function(double) progress,
) async {
  if (file.size > 50 * 1024 * 1024) throw StateError('50 MB maximum per file');
  final uri = Uri.parse('$backendUrl/storage/v1/object/$bucket/$key');
  final request = http.StreamedRequest('POST', uri);
  request.headers.addAll({
    'apikey': backendKey,
    'Authorization': 'Bearer ${state.db.auth.currentSession!.accessToken}',
    'Content-Type': file.mime,
    'x-upsert': 'false',
  });
  request.contentLength = file.size;
  final client = state.uploadClient;
  try {
    final response = client.send(request);
    var sent = 0;
    await for (final chunk in File(file.path).openRead()) {
      request.sink.add(chunk);
      sent += chunk.length;
      progress(file.size == 0 ? 1 : sent / file.size);
    }
    await request.sink.close();
    final result = await response;
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw StateError('Upload failed');
    }
    await result.stream.drain<void>();
    progress(1);
  } finally {
    /* The app owns the shared HTTP client. */
  }
}

Future<void> openOtherFile(String url, String name, String mime) =>
    const MethodChannel(
      'app/files',
    ).invokeMethod<void>('open', {'url': url, 'name': name, 'mime': mime});
