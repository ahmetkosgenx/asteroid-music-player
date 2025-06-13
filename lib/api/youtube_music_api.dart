import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;

class YoutubeMusicVideo {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String duration;
  final int? viewCount;
  String? trackingParams;
  String? playlistId;
  String? params;

  YoutubeMusicVideo({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.viewCount,
    this.trackingParams,
    this.playlistId,
    this.params,
  });
}

class YouTubeMusicApi {
  static final Logger _logger = Logger('YouTubeMusicApi');
  
  // Define proper base domains for different endpoints
  static const String _musicDomain = 'music.youtube.com';
  static const String _apiPath = '/youtubei/v1';
  static const String _searchEndpoint = '/search';
  
  // User agent for requests
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';
  
  // API key for YouTube Music
  static const String _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  
  // Common headers for YouTube Music API requests
  static const Map<String, String> _headers = {
    'User-Agent': _userAgent,
    'Accept-Language': 'en-US,en;q=0.9',
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': _apiKey,
    'Origin': 'https://$_musicDomain',
    'Referer': 'https://$_musicDomain/',
    'X-Youtube-Client-Name': '67',
    'X-Youtube-Client-Version': '1.20250602.03.00',
    'X-Origin': 'https://$_musicDomain',
  };
  
  // Store last continuation token from last fetch
  static String? _lastContinuationToken;
  static String? get lastContinuationToken => _lastContinuationToken;
  
  // Store last search continuation token
  static String? _lastSearchContinuationToken;
  static String? get lastSearchContinuationToken => _lastSearchContinuationToken;
  
  // Check network connectivity
  static Future<bool> isNetworkAvailable() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _logger.severe('Error checking network connectivity: $e');
      return false;
    }
  }
  
  // Search for music videos using POST request to music.youtube.com/youtubei/v1/search
  static Future<List<YoutubeMusicVideo>> search(String query) async {
    try {
      // Check network connectivity first
      if (!await isNetworkAvailable()) {
        _logger.warning('Network not available for search');
        return [];
      }
      
      // Construct the URL for POST request
      final url = Uri.https(_musicDomain, '$_apiPath$_searchEndpoint');
      
      // Create the request body
      final requestBody = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250602.03.00',
            'hl': 'en',
            'gl': 'US',
            'userAgent': _userAgent,
            'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
            'browserName': 'Chrome',
            'browserVersion': '137.0.0.0',
            'osName': 'Windows',
            'osVersion': '10.0',
            'platform': 'DESKTOP',
          },
          'user': {
            'lockedSafetyMode': false
          },
          'request': {
            'useSsl': true,
            'internalExperimentFlags': [],
            'consistencyTokenJars': []
          },
        },
        'query': query,
      };
      
      _logger.info('Sending search request to: $url');
      
      final response = await http.post(
        url,
        headers: _headers,
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        _logger.info('Received search response with status code 200');
        
        // Parse the response JSON
        final jsonResponse = json.decode(response.body);
        
        // Extract videos from the response
        final videos = _parseSearchResponse(jsonResponse);
        
        // Store the tracking parameters to use for player requests
        for (var video in videos) {
          if (jsonResponse['contents'] != null && 
              jsonResponse['trackingParams'] != null) {
            // Store the tracking params in the video for later use
            video.trackingParams = jsonResponse['trackingParams'];
          }
        }
        
        // Attempt to capture continuation token for further paging
        try {
          String? token;
          // Look in first occurrence of continuations within section list
          final tabbedResultsCont = jsonResponse['contents']?['tabbedSearchResultsRenderer']?['tabs'];
          if (tabbedResultsCont is List) {
            for (final tab in tabbedResultsCont) {
              final cont = tab?['tabRenderer']?['content']?['sectionListRenderer']?['continuations']?[0]?
                  ['nextContinuationData']?['token'];
              if (cont != null && cont is String && cont.isNotEmpty) {
                token = cont;
                break;
              }
            }
          }
          _lastSearchContinuationToken = token;
        } catch (_) {}
        
        return videos;
      } else {
        _logger.warning('Search failed with status code: ${response.statusCode}');
        _logger.warning('Response body: ${response.body}');
      }
    } catch (e, stackTrace) {
      _logger.severe('Error searching YouTube Music: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
    
    return [];
  }
  
  // Parse the search response to extract video information
  static List<YoutubeMusicVideo> _parseSearchResponse(Map<String, dynamic> response) {
    final List<YoutubeMusicVideo> videos = [];
    
    try {
      // Check if the contents section exists
      if (response['contents'] == null) {
        _logger.warning('Response missing contents section');
        return videos;
      }
      
      // Navigate to the section containing search results
      final tabbedResults = response['contents']['tabbedSearchResultsRenderer'];
      if (tabbedResults == null || tabbedResults['tabs'] == null) {
        _logger.warning('Response missing tabbedSearchResultsRenderer or tabs');
        return videos;
      }
      
      final tabs = tabbedResults['tabs'] as List;
      for (final tab in tabs) {
        if (tab['tabRenderer'] == null || tab['tabRenderer']['content'] == null) {
          continue;
        }
        
        final sectionListRenderer = tab['tabRenderer']['content']['sectionListRenderer'];
        if (sectionListRenderer == null || sectionListRenderer['contents'] == null) {
          continue;
        }
        
        final contents = sectionListRenderer['contents'] as List;
        for (final section in contents) {
          // Look for musicShelfRenderer (contains the music results)
          if (section['musicShelfRenderer'] != null && 
              section['musicShelfRenderer']['contents'] != null) {
            
            final items = section['musicShelfRenderer']['contents'] as List;
            for (final item in items) {
              if (item['musicResponsiveListItemRenderer'] != null) {
                final renderer = item['musicResponsiveListItemRenderer'];
                
                // Try to extract a YoutubeMusicVideo from this renderer
                try {
                  final video = _extractVideoFromRenderer(renderer);
                  if (video != null) {
                    videos.add(video);
                  }
                } catch (e) {
                  _logger.warning('Error extracting video from renderer: $e');
                }
              }
            }
          }
        }
      }
      
      _logger.info('Extracted ${videos.length} videos from search response');
    } catch (e, stackTrace) {
      _logger.severe('Error parsing search response: $e');
      _logger.severe('Stack trace: $stackTrace');
    }
    
    return videos;
  }
  
  // Extract a single video from a renderer object
  static YoutubeMusicVideo? _extractVideoFromRenderer(Map<String, dynamic> renderer) {
    try {
      // Extract video ID
      String videoId = '';
      String? playlistId;
      String? params;
      if (renderer['overlay'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer']['content'] != null &&
          renderer['overlay']['musicItemThumbnailOverlayRenderer']['content']['musicPlayButtonRenderer'] != null) {
        final playButtonRenderer = renderer['overlay']['musicItemThumbnailOverlayRenderer']['content']['musicPlayButtonRenderer'];
        if (playButtonRenderer['playNavigationEndpoint'] != null &&
            playButtonRenderer['playNavigationEndpoint']['watchEndpoint'] != null) {
          final watchEndpoint = playButtonRenderer['playNavigationEndpoint']['watchEndpoint'];
          videoId = watchEndpoint['videoId'] ?? '';
          playlistId = watchEndpoint['playlistId'];
          params = watchEndpoint['params'];
        }
      }
      
      if (videoId.isEmpty) {
        _logger.warning('Failed to extract videoId from renderer');
        return null;
      }
      
      // Extract title
      String title = '';
      if (renderer['flexColumns'] != null && renderer['flexColumns'].isNotEmpty) {
        final firstColumn = renderer['flexColumns'][0];
        if (firstColumn['musicResponsiveListItemFlexColumnRenderer'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] != null &&
            firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'].isNotEmpty) {
          
          title = firstColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'][0]['text'] ?? '';
        }
      }
      
      if (title.isEmpty) {
        _logger.warning('Failed to extract title for video $videoId');
        return null;
      }
      
      // Extract artist and other metadata
      String artist = '';
      String duration = '';
      
      if (renderer['flexColumns'] != null && renderer['flexColumns'].length > 1) {
        final secondColumn = renderer['flexColumns'][1];
        if (secondColumn['musicResponsiveListItemFlexColumnRenderer'] != null &&
            secondColumn['musicResponsiveListItemFlexColumnRenderer']['text'] != null &&
            secondColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] != null) {
          
          final runs = secondColumn['musicResponsiveListItemFlexColumnRenderer']['text']['runs'] as List;
          
          // Typically artist is the first or second run
          if (runs.isNotEmpty) {
            artist = runs[0]['text'] ?? '';
            
            // Look for duration (usually formatted as MM:SS)
            for (final run in runs) {
              final text = run['text'] ?? '';
              if (text.contains(':') && RegExp(r'^\d+:\d+$').hasMatch(text)) {
                duration = text;
                break;
              }
            }
          }
        }
      }
      
      // Extract thumbnail URL
      String thumbnailUrl = '';
      if (renderer['thumbnail'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer']['thumbnail'] != null &&
          renderer['thumbnail']['musicThumbnailRenderer']['thumbnail']['thumbnails'] != null) {
        
        final thumbnails = renderer['thumbnail']['musicThumbnailRenderer']['thumbnail']['thumbnails'] as List;
        if (thumbnails.isNotEmpty) {
          // Get the highest quality thumbnail
          thumbnailUrl = thumbnails.last['url'] ?? '';
        }
      }
      
      return YoutubeMusicVideo(
        videoId: videoId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        duration: duration,
        playlistId: playlistId,
        params: params,
      );
    } catch (e, stackTrace) {
      _logger.severe('Error extracting video from renderer: $e');
      _logger.severe('Stack trace: $stackTrace');
      return null;
    }
  }

  static Future<List<YoutubeMusicVideo>> fetchSimilarSongs(
    String videoId, {
    String? playlistId,
    String? params,
    String language = 'en',
    String region = 'US',
    String tunerSettingValue = 'AUTOMIX_SETTING_NORMAL',
    Map<String, dynamic>? loggingContext,
    Map<String, dynamic>? watchEndpointMusicSupportedConfigs,
    Map<String, dynamic>? responsiveSignals,
    String queueContextParams = '',
    Map<String, dynamic>? clickTracking,
    Map<String, dynamic>? adSignalsInfo,
  }) async {
    // Always attempt live call first; fall back to bundled example for offline/dev
    final List<YoutubeMusicVideo> relatedVideos = [];
    try {
      if (await isNetworkAvailable()) {
        final url = Uri.https(_musicDomain, '$_apiPath/next', { 'key': _apiKey, 'prettyPrint': 'false' });
        // Build request body
        final body = {
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20250602.03.00',
              'hl': language,
              'gl': region,
              'userAgent': _userAgent,
              'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
              'platform': 'DESKTOP',
            },
            'request': { 'useSsl': true }
          },
          'videoId': videoId,
          'isAudioOnly': true,
        };
        if (playlistId != null && playlistId.isNotEmpty) {
          body['playlistId'] = playlistId;
        } else {
          body['playlistId'] = 'RDAMVM$videoId';
        }
        if (params != null && params.isNotEmpty) {
          body['params'] = params;
        }
        // _logger.info('[NEXT API] Requesting similar songs for videoId=$videoId');
        final response = await http
            .post(url, headers: _headers, body: json.encode(body))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          relatedVideos.addAll(_parseNextResponse(jsonResponse, videoId));
        } else {
          _logger.warning('[NEXT API] Non-200 response: ${response.statusCode}');
        }
      } else {
        _logger.warning('[NEXT API] Network not available; using local example.json');
      }
    } catch (e, stack) {
      _logger.warning('[NEXT API] Error during live fetch: $e');
      _logger.fine(stack);
    }

    // Fallback to bundled example if live call failed or returned empty
    if (relatedVideos.isEmpty) {
      try {
        final jsonStr = await rootBundle.loadString('assets/example.json');
        final jsonResponse = json.decode(jsonStr);
        relatedVideos.addAll(_parseNextResponse(jsonResponse, videoId));
      } catch (e) {
        _logger.severe('Error loading fallback example.json: $e');
      }
    }

    return relatedVideos;
  }

  // Helper to parse /next or bundled example response
  static List<YoutubeMusicVideo> _parseNextResponse(Map<String, dynamic> jsonResponse, String currentVideoId) {
    final List<YoutubeMusicVideo> list = [];
    try {
      // extract token too
      _lastContinuationToken = jsonResponse['contents']?['singleColumnMusicWatchNextResultsRenderer']?
          ['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['continuations']?[0]?['nextContinuationData']?['token'];
      final contents = jsonResponse['contents']?['singleColumnMusicWatchNextResultsRenderer']?
          ['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?
          ['musicQueueRenderer']?['content']?['playlistPanelRenderer']?['contents'] as List?;
      if (contents == null) return list;
      for (final item in contents) {
        final videoRenderer = item['playlistPanelVideoRenderer'];
        if (videoRenderer == null) continue;
        final id = videoRenderer['videoId'] as String?;
        if (id == null || id == currentVideoId) continue;
        final title = videoRenderer['title']?['runs']?[0]?['text'] as String? ?? '';
        // Artist / album / year in longBylineText.runs separated by " • " runs
        String artist = '';
        final bylineRuns = videoRenderer['longBylineText']?['runs'] as List?;
        if (bylineRuns != null && bylineRuns.isNotEmpty) {
          artist = bylineRuns.firstWhere(
                  (r) => (r['text'] as String?)?.trim() != '•',
                  orElse: () => {'text': ''})['text'] ?? '';
        }
        // Thumbnail
        String thumbnailUrl = '';
        final thumbList = videoRenderer['thumbnail']?['thumbnails'] as List?;
        if (thumbList != null && thumbList.isNotEmpty) {
          thumbnailUrl = thumbList.last['url'] ?? '';
        }
        // Duration
        final duration = videoRenderer['lengthText']?['runs']?[0]?['text'] as String? ?? '';
        // playlistId / params for chaining
        String? plId;
        String? prm;
        final navEndpoint = videoRenderer['navigationEndpoint']?['watchEndpoint'];
        if (navEndpoint != null) {
          plId = navEndpoint['playlistId'] as String?;
          prm = navEndpoint['params'] as String?;
        }
        list.add(YoutubeMusicVideo(
          videoId: id,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          duration: duration,
          playlistId: plId,
          params: prm,
        ));
      }
      // _logger.info('[NEXT API] Parsed \\${list.length} related videos');
    } catch (e) {
      _logger.warning('Error parsing next response: $e');
    }
    return list;
  }

  static Future<List<YoutubeMusicVideo>> fetchContinuation(String token) async {
    final List<YoutubeMusicVideo> videos = [];
    try {
      final url = Uri.https(_musicDomain, '$_apiPath/next', {'key': _apiKey, 'prettyPrint': 'false'});
      final body = {
        'continuation': token,
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250602.03.00',
            'hl': 'en',
            'gl': 'US'
          }
        }
      };
      final res = await http.post(url, headers: _headers, body: json.encode(body)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final jsonResp = json.decode(res.body);
        videos.addAll(_parseNextResponse(jsonResp, ''));
      }
    } catch (e) {
      _logger.warning('Error fetchContinuation: $e');
    }
    return videos;
  }

  // Fetch next page of search results using a continuation token
  static Future<List<YoutubeMusicVideo>> searchContinuation(String token) async {
    final List<YoutubeMusicVideo> videos = [];
    try {
      if (!await isNetworkAvailable()) return videos;

      final url = Uri.https(_musicDomain, '$_apiPath$_searchEndpoint');
      final body = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250602.03.00',
            'hl': 'en',
            'gl': 'US',
            'userAgent': _userAgent,
            'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
            'platform': 'DESKTOP',
          }
        },
        'continuation': token,
      };

      final res = await http.post(url, headers: _headers, body: json.encode(body)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final jsonResp = json.decode(res.body);
        videos.addAll(_parseSearchResponse(jsonResp));

        // Update continuation token for further paging
        try {
          String? nextToken;
          final tabs = jsonResp['contents']?['tabbedSearchResultsRenderer']?['tabs'];
          if (tabs is List) {
            for (final tab in tabs) {
              final cont = tab?['tabRenderer']?['content']?['sectionListRenderer']?['continuations']?[0]?
                  ['nextContinuationData']?['token'];
              if (cont != null && cont is String && cont.isNotEmpty) {
                nextToken = cont;
                break;
              }
            }
          }
          _lastSearchContinuationToken = nextToken;
        } catch (_) {}
      }
    } catch (e) {
      _logger.warning('Error searchContinuation: $e');
    }
    return videos;
  }
} 