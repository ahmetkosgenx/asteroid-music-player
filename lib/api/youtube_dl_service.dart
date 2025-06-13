import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeDLService {
  static final Logger _logger = Logger('YoutubeDLService');
  static final YoutubeDLService _instance = YoutubeDLService._internal();
  
  factory YoutubeDLService() => _instance;
  
  YoutubeDLService._internal();
  
  // Only use youtube_explode_dart for extraction
  final YoutubeExplode _yt = YoutubeExplode();
  
  // Always ready (no initialization needed)
  Future<bool> isReady() async => true;
  
  // Simple in-memory cache for recent videoId→URL mappings
  final Map<String, String> _streamUrlCache = {};
  static const int _cacheSize = 20;

  // Get streaming URL for YouTube video ID using youtube_explode_dart
  Future<String?> getStreamUrl(String videoId) async {
    // Check cache first
    if (_streamUrlCache.containsKey(videoId)) {
      _logger.info('Returning cached stream URL for $videoId');
      return _streamUrlCache[videoId];
    }
    try {
      // Try the default client first, then fall back to alternative client profiles that often bypass 403 errors.
      final List<List<YoutubeApiClient>> clientFallbacks = [
        const [], // Default behaviour (TVHTML5 client)
        [YoutubeApiClient.android],
        [YoutubeApiClient.safari],
      ];

      for (final clients in clientFallbacks) {
        try {
          final manifest = clients.isEmpty
              ? await _yt.videos.streamsClient.getManifest(videoId)
              : await _yt.videos.streamsClient.getManifest(
                  videoId,
                  ytClients: clients,
                );

          // 1. Prefer HLS stream if available
          final hlsStreams = manifest.hls;
          if (hlsStreams.isNotEmpty) {
            final url = hlsStreams.first.url.toString();
            _cacheAndReturn(videoId, url);
            _logger.info('Got HLS stream (client=${_clientNames(clients)})');
            return url;
          }

          // 2. Fallback to audio-only streams, sorted by bitrate descending
          final audioStreams = manifest.audioOnly.toList()
            ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

          for (final stream in audioStreams) {
            final mimeType = stream.codec.mimeType.toLowerCase();
            final codecString = stream.codec.toString().toLowerCase();
            if (!(mimeType.contains('audio') &&
                  (codecString.contains('opus') || codecString.contains('aac') || codecString.contains('mp4a')))) {
              continue;
            }
            final url = stream.url.toString();
            _cacheAndReturn(videoId, url);
            _logger.info('Got audio stream (client=${_clientNames(clients)})');
            return url;
          }

          // If no streams usable, continue to next client profile.
          _logger.fine('No usable streams with client=${_clientNames(clients)}');
        } on YoutubeExplodeException catch (e) {
          // Only break if the error is not a 403; otherwise try the next fallback.
          if (!e.message.contains('403')) {
            rethrow;
          }
          _logger.fine('Client ${_clientNames(clients)} returned 403, trying next fallback');
        }
      }

      _logger.warning('All client fallbacks exhausted; no stream found for $videoId');
      return null;
    } on YoutubeExplodeException catch (e, stackTrace) {
      _logger.severe('YoutubeExplodeException: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    } catch (e, stackTrace) {
      _logger.severe('Error getting stream URL: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    }
  }

  // Helper that stores URL in cache and trims cache size
  void _cacheAndReturn(String videoId, String url) {
    _streamUrlCache[videoId] = url;
    if (_streamUrlCache.length > _cacheSize) {
      _streamUrlCache.remove(_streamUrlCache.keys.first);
    }
  }

  // Helper to print nice client names for logs
  String _clientNames(List<YoutubeApiClient> clients) {
    if (clients.isEmpty) return 'default';
    return clients
        .map((c) => c.toString().split('.').last)
        .join('+');
  }
}