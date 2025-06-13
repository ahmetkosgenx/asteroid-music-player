import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class AudioCacheService {
  final Dio _dio = Dio();

  Future<String> _getAudioFilePath(String songId) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return '${cacheDir.path}/$songId.mp3';
  }

  Future<bool> isAudioCached(String songId) async {
    final path = await _getAudioFilePath(songId);
    return File(path).exists();
  }

  Future<File> downloadAudio(String url, String songId) async {
    final path = await _getAudioFilePath(songId);
    final file = File(path);
    if (await file.exists()) return file;
    await _dio.download(url, path);
    return file;
  }
} 