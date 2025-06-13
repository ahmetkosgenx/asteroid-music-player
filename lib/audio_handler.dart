import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:asteroid/api/youtube_dl_service.dart';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/api/youtube_service.dart';

Future<AudioHandler> initAudioService() async {
  print('initAudioService called');
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.asteroid.notio.asteroid.channel.audio',
      androidNotificationChannelName: 'Asteroid Music',
      androidNotificationOngoing: true,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  final _logger = Logger('AudioHandler');
  
  // Keep track of whether we're currently processing a play request
  bool _processingPlayRequest = false;
  final _nextSongsController = StreamController<List<MediaItem>>.broadcast();
  List<MediaItem> _latestSimilarSongs = [];
  Stream<List<MediaItem>> get nextSongsStream => _nextSongsController.stream;
  List<MediaItem> get latestSimilarSongs => _latestSimilarSongs;
  final YouTubeService _youtubeService = YouTubeService();

  // Add a position stream for real-time updates
  Stream<Duration> get positionStream => _player.positionStream;

  // Add state to track last similar fetch
  String? _lastSimilarFetchVideoId;
  bool _lastSimilarFetchWasEmpty = false;

  MediaItem? _sessionFirstSong; // first track started this session
  MediaItem? get sessionFirstSong => _sessionFirstSong;

  bool _skipNextInProgress = false;

  MyAudioHandler() {
    print('MyAudioHandler initialized');
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _listenForSequenceStateChanges();
    _listenForProcessingStateChanges();
    
    // Initialize the player with the playlist
    _initializePlayer();
  }

  // Connect player events to audio handler events
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  // Listen to duration changes and update MediaItem
  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      final newQueue = queue.value;
      if (index == null || newQueue.isEmpty) return;
      final oldMediaItem = newQueue[index];
      final newMediaItem = oldMediaItem.copyWith(duration: duration);
      newQueue[index] = newMediaItem;
      queue.add(newQueue);
      mediaItem.add(newMediaItem);
    });
  }

  // Listen to current song index changes
  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      final playlist = queue.value;
      if (index == null || playlist.isEmpty) return;
      // Merely update the currently playing MediaItem – do NOT change the Up Next list.
      mediaItem.add(playlist[index]);
    });
  }

  // Listen to sequence state changes
  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);
    });
  }

  // Automatically skip to the next track when the current one finishes
  void _listenForProcessingStateChanges() {
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await skipToNext();
      }
    });
  }

  // Initialize the player with the playlist
  Future<void> _initializePlayer() async {
    try {
      await _player.setAudioSource(_playlist);
      _logger.info('Audio player initialized with playlist');
    } catch (e) {
      _logger.severe('Error initializing audio player: $e');
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem, {bool prefetchSimilarSongs = true}) async {
    try {
      _logger.info('Adding queue item: ${mediaItem.title} - ${mediaItem.id}');
      
      // Get the URL from either id or extras
      String url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      
      // If the "url" looks like a bare YouTube videoId, resolve it to a stream URL first
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        _logger.info('Detected raw videoId ($url), resolving to stream URL');
        final stream = await _youtubeService.getStreamingUrl(url);
        if (stream != null) {
          _logger.info('Resolved videoId to stream URL (${stream.substring(0, 50)}...)');
          url = stream;
          // Replace mediaItem so the queue stores the playable URL
          mediaItem = mediaItem.copyWith(
            id: stream,
            extras: {
              ...?mediaItem.extras,
              'url': stream,
              'videoId': mediaItem.extras?['videoId'] ?? url,
            },
          );
        } else {
          _logger.warning('Failed to resolve videoId=$url to stream URL');
        }
      }
      
      if (url.isEmpty) {
        _logger.severe('Empty URL for media item: ${mediaItem.title}');
        throw Exception('Empty URL for media item');
      }
      
      _logger.info('Using URL: $url');
      _logger.info('URL length: ${url.length} characters');
      
      // Log the start of the URL to help diagnose issues
      if (url.length > 100) {
        _logger.info('URL start: ${url.substring(0, 100)}...');
      } else {
        _logger.info('URL: $url');
      }
      
      try {
        // Validate URL format
        final uri = Uri.parse(url);
        _logger.info('Parsed URI - scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');
        
        // Ensure URL has a valid scheme
        if (uri.scheme.isEmpty) {
          throw Exception('Missing scheme in URL');
        }
      } catch (e) {
        _logger.severe('Error parsing URL: $e');
        
        // Try to fix common URL issues
        if (url.startsWith('//')) {
          url = 'https:$url';
          _logger.info('Fixed URL by adding https: scheme: $url');
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
          _logger.info('Fixed URL by adding https:// scheme: $url');
        } else {
          throw Exception('Invalid URL format: $url');
        }
      }
      
      // Create audio source with proper URL
      _logger.info('Creating audio source with URL');
      final audioSource = AudioSource.uri(
        Uri.parse(url),
        tag: mediaItem.copyWith(id: url), // Use URL as ID for internal player consistency
      );
      _logger.info('Audio source created successfully');
      
      // Add to playlist
      _logger.info('Adding to playlist');
      await _playlist.add(audioSource);
      _logger.info('Added to playlist successfully');
      
      // If first item, remember as session first song
      if (_sessionFirstSong == null) {
        _sessionFirstSong = mediaItem;
      }
      
      // Add to queue
      final newQueue = queue.value..add(mediaItem);
      queue.add(newQueue);
      _logger.info('Added to queue successfully, queue size: ${newQueue.length}');
      
      // If this is the first item, initialize the player
      if (_playlist.length == 1) {
        _logger.info('First item added, initializing player with playlist');
        await _player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
      }
      
      // Prefetch similar songs immediately so Up Next is ready
      if (prefetchSimilarSongs) {
        try {
          final videoId = mediaItem.extras?['videoId'] as String? ??
              _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
          if (videoId != null && videoId.isNotEmpty) {
            final playlistId = mediaItem.extras?['playlistId'] as String?;
            final params = mediaItem.extras?['params'] as String?;
            // _logger.info('[NEXT API] (addQueueItem) Fetching similar songs for videoId: ' + videoId + ', playlistId: ' + (playlistId ?? 'null') + ', params: ' + (params ?? 'null'));
            final similarVideos = await YouTubeMusicApi.fetchSimilarSongs(
              videoId,
              playlistId: playlistId,
              params: params,
            );
            final nextMediaItems = similarVideos.map((v) => _youtubeService.youtubeVideoToMediaItem(v)).toList();
            if (nextMediaItems.isNotEmpty) {
              // Prepend the currently playing song to the similar songs list
              final List<MediaItem> fullUpNextList = [mediaItem, ...nextMediaItems];
              _latestSimilarSongs = fullUpNextList;
              _nextSongsController.add(fullUpNextList);
            } else {
               // If no similar songs are found, the "Up Next" list should just contain the current song
               final List<MediaItem> fullUpNextList = [mediaItem];
               _latestSimilarSongs = fullUpNextList;
               _nextSongsController.add(fullUpNextList);
            }
            // _logger.info('[NEXT API] (addQueueItem) Similar songs found: ' + nextMediaItems.length.toString());
            for (final item in nextMediaItems) {
              // _logger.info('[NEXT API] (addQueueItem)   - ' + item.title + ' (' + item.id + ')');
            }
            if (nextMediaItems.isNotEmpty) {
              // Removed verbose console printing of similar songs
              // debug print removed
            }
            // Cache fetch result to avoid duplicate network calls when the track starts playing
            _lastSimilarFetchVideoId = videoId;
            _lastSimilarFetchWasEmpty = nextMediaItems.isEmpty;
          }
        } catch (e) {
          _logger.warning('Error prefetching similar songs: $e');
        }
      }
      
    } catch (e, stackTrace) {
      _logger.severe('Error adding queue item: $e');
      _logger.severe('Stack trace: $stackTrace');
      rethrow; // Rethrow to make sure the error is properly handled by the caller
    }
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    try {
      await _playlist.removeAt(index);
      final newQueue = queue.value..removeAt(index);
      queue.add(newQueue);
    } catch (e) {
      _logger.severe('Error removing queue item: $e');
    }
  }

  @override
  Future<void> play() async {
    if (_processingPlayRequest) {
      _logger.info('Already processing a play request, ignoring additional request');
      return;
    }
    
    _processingPlayRequest = true;
    
    try {
      // Check if we have any items in the playlist
      _logger.info('Playlist length: ${_playlist.length}');
      if (_playlist.length == 0) {
        _logger.warning('Attempted to play with empty playlist');
        return;
      }
      
      // Check if player has been properly initialized
      if (_player.audioSource == null) {
        _logger.info('Player not initialized, setting audio source');
        await _player.setAudioSource(_playlist);
        _logger.info('Player initialized with playlist');
      }
      
      // Now play
      _logger.info('Starting playback');
      await _player.play();
      _logger.info('Playback started successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error in play method: $e');
      _logger.severe('Stack trace: $stackTrace');
    } finally {
      _processingPlayRequest = false;
    }
  }

  @override
  Future<void> pause() async {
    _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.pause();
    await _player.seek(position);
    await Future.delayed(const Duration(milliseconds: 300));
    await _player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _playlist.children.length) return;
    _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> skipToNext() async {
    if (_skipNextInProgress) return;
    _skipNextInProgress = true;
    try {
      final playlist = queue.value;
      if (playlist.isEmpty) return;

      if (_player.hasNext) {
        // Fast-path: play the next track already in the just_audio playlist
        await _player.seekToNext();
        // Calling play after seekToNext seems to be the pattern used elsewhere.
        await _player.play();
      } else if (_latestSimilarSongs.isNotEmpty) {
        // Main playlist exhausted, add all similar songs to the main playlist
        _logger.info('[NEXT API] Main playlist exhausted, adding all similar songs (${_latestSimilarSongs.length}) to main playlist.');

        final songsToAdd = _latestSimilarSongs.toList(); // Create a copy
        final firstAddedIndex = _playlist.length; // Index where new songs will start

        _latestSimilarSongs = []; // Clear the similar list as it's being moved to the main queue
        _nextSongsController.add([]); // Update the 'Up Next' stream to show it's empty

        final audioSourcesToAdd = <AudioSource>[];
        final processedItems = <MediaItem>[];
        final youtubeDlService = YoutubeDLService();

        for (final item in songsToAdd) {
            String? videoId = item.extras?['videoId'] as String? ?? _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
            String? streamUrl;

            if (videoId != null) {
                 try {
                    // Get streaming URL for each similar song
                    streamUrl = await youtubeDlService.getStreamUrl(videoId);
                    if (streamUrl != null) {
                        _logger.info('Got streaming URL using YT-DLP service for video: $videoId');
                    }
                } catch (e) {
                    _logger.warning('Error using YT-DLP service for $videoId: $e');
                    // If fetching fails, skip this song.
                    continue;
                }
            } else {
               // If it's not a YouTube video ID, assume the URL is already playable
               streamUrl = item.extras?['url'] as String? ?? item.id;
               if (streamUrl == null || streamUrl.isEmpty) {
                   _logger.warning('Skipping item with no videoId or URL: ${item.title}');
                   continue;
               }
               _logger.info('Using existing URL for non-YouTube item: ${item.title}');
            }


            if (streamUrl != null) {
                 final newItem = item.copyWith(
                    id: streamUrl, // Use streamUrl as the ID for playback
                    extras: {
                        ...?item.extras,
                        'url': streamUrl,
                        'videoId': videoId, // Keep the videoId if it exists
                    },
                );
                processedItems.add(newItem);
                audioSourcesToAdd.add(AudioSource.uri(Uri.parse(streamUrl), tag: newItem));
            }
        }

        if (audioSourcesToAdd.isNotEmpty) {
            await _playlist.addAll(audioSourcesToAdd); // Add to just_audio playlist

            // Update the main queue stream with the newly added items
            final newQueue = List<MediaItem>.from(queue.value)..addAll(processedItems);
            queue.add(newQueue);

            // Seek to the first newly added song and play
            await _player.seek(Duration.zero, index: firstAddedIndex);
            await _player.play();



        } else {
            _logger.info('[NEXT API] No valid songs found in similar list to add to main playlist.');
             await _player.stop(); // If no valid songs to add, just stop
        }

      } else {
        // No more items in main playlist or similar songs, just stop playback
        _logger.info('[NEXT API] No more songs in main playlist or similar list, stopping.');
        await _player.stop();
      }
    } finally {
      _skipNextInProgress = false;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.group:
      case AudioServiceRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      _player.setShuffleModeEnabled(false);
    } else {
      _player.setShuffleModeEnabled(true);
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      await _player.dispose();
      super.customAction(name, extras);
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _player.dispose();
    await _nextSongsController.close();
    super.stop();
  }

  Future<void> clearAndPlay(MediaItem mediaItem, {bool resetSimilar = true}) async {
    try {
      _logger.info('clearAndPlay called');

      if (resetSimilar) {
        // Reset cached similar-songs information so a brand-new Up Next list is fetched for this track
        _latestSimilarSongs = [];
        _lastSimilarFetchVideoId = null;
        _lastSimilarFetchWasEmpty = false;
      }

      // Ensure we have a playable URL
      String? url = mediaItem.extras?['url'] as String? ?? mediaItem.id;
      if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
        // looks like a YouTube videoId, resolve to stream url first
        final stream = await _youtubeService.getStreamingUrl(url);
        if (stream != null) {
          mediaItem = mediaItem.copyWith(
            id: stream,
            extras: {
              ...?mediaItem.extras,
              'url': stream,
            },
          );
          url = stream;
        } else {
          _logger.warning('Could not resolve streaming URL for videoId=$url');
        }
      }

      await _player.stop();
      await _playlist.clear();
      queue.add([]);
      // Reset player source – prefetch similar songs only when we reset the list.
      await addQueueItem(mediaItem, prefetchSimilarSongs: resetSimilar);
      await play();
      // Log benzer şarkılar
      final videoId = mediaItem.extras?['videoId'] as String? ?? _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
      final playlistId = mediaItem.extras?['playlistId'] as String?;
      final params = mediaItem.extras?['params'] as String?;
      // _logger.info('[NEXT API] (clearAndPlay) Song started. videoId: ' + (videoId ?? 'null') + ', playlistId: ' + (playlistId ?? 'null') + ', params: ' + (params ?? 'null'));
      // _logger.info('[NEXT API] (clearAndPlay) Latest similar songs: ' + _latestSimilarSongs.length.toString());
      for (final item in _latestSimilarSongs) {
        // _logger.info('[NEXT API] (clearAndPlay)   - ' + item.title + ' (' + item.id + ')');
      }

      // (If we cleared at the beginning, do NOT clear again here.)
    } catch (e, st) {
      _logger.severe('Error in clearAndPlay: $e');
      _logger.severe(st);
    }
  }

  // Extract YouTube video ID from various URL formats
  String? _extractYouTubeVideoId(String? url) {
    if (url == null) return null;
    
    // Direct ID (not a URL)
    if (url.length == 11 && !url.contains('/') && !url.contains('.')) {
      return url;
    }
    
    try {
      // Standard YouTube URL patterns
      final patterns = [
        RegExp(r'youtube\.com/watch\?v=([^&]+)'),
        RegExp(r'youtu\.be/([^?]+)'),
        RegExp(r'youtube\.com/embed/([^?]+)'),
        RegExp(r'music\.youtube\.com/watch\?v=([^&]+)'),
      ];
      
      for (final pattern in patterns) {
        final match = pattern.firstMatch(url);
        if (match != null && match.groupCount >= 1) {
          return match.group(1);
        }
      }
    } catch (e) {
      _logger.warning('Error extracting YouTube ID: $e');
    }
    
    return null;
  }

  // Updates player to a new playlist
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    try {
      // Process each item for YouTube URLs
      final processedItems = <MediaItem>[];
      final audioSources = <AudioSource>[];
      
      for (final item in newQueue) {
        String? videoId = _extractYouTubeVideoId(item.extras?['url'] as String? ?? item.id);
        
        if (videoId != null) {
          // Handle YouTube video
          String? streamUrl;
          
          // Use YT-DLP service to get streaming URL
          try {
            final youtubeDlService = YoutubeDLService();
            streamUrl = await youtubeDlService.getStreamUrl(videoId);
            if (streamUrl != null) {
              _logger.info('Got streaming URL using YT-DLP service for video: $videoId');
            }
          } catch (e) {
            _logger.warning('Error using YT-DLP service: $e');
          }
          
          if (streamUrl != null) {
            final newItem = item.copyWith(
              id: streamUrl,
              extras: {...?item.extras, 'url': streamUrl},
            );
            
            processedItems.add(newItem);
            audioSources.add(AudioSource.uri(Uri.parse(streamUrl), tag: newItem));
          } else {
            _logger.warning('Could not find streaming URL for YouTube video: $videoId');
          }
        } else {
          // Regular audio URL
          processedItems.add(item);
          audioSources.add(AudioSource.uri(
            Uri.parse(item.extras?['url'] as String? ?? item.id),
            tag: item,
          ));
        }
      }
      
      // Update queue and playlist
      queue.add(processedItems);
      await _playlist.clear();
      await _playlist.addAll(audioSources);
    } catch (e) {
      _logger.severe('Error updating queue: $e');
    }
  }

  Future<void> playMediaItem(MediaItem mediaItem) async {
    try {
      final idx = queue.value.indexWhere((m) {
        final vid1 = m.extras?['videoId'] ?? _extractYouTubeVideoId(m.extras?['url'] as String? ?? m.id);
        final vid2 = mediaItem.extras?['videoId'] ?? _extractYouTubeVideoId(mediaItem.extras?['url'] as String? ?? mediaItem.id);
        return vid1 != null && vid1 == vid2;
      });
      if (idx != -1) {
        await _player.seek(Duration.zero, index: idx);
        await _player.play();
      } else {
        // Replace current playback with the chosen media item but keep existing similar list.
        await clearAndPlay(mediaItem, resetSimilar: false);
      }
    } catch (e, st) {
      _logger.severe('Error in playMediaItem: $e');
      _logger.severe(st);
    }
  }
} 