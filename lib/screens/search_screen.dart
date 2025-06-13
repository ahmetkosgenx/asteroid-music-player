import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:asteroid/api/youtube_service.dart';
import 'package:asteroid/api/youtube_music_api.dart';
import 'package:asteroid/providers/search_provider.dart';
import 'dart:math' as math;
import 'package:asteroid/audio_handler.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  final YouTubeService _youtubeService = YouTubeService();
  bool _showHistory = false;
  int _loadingItemIndex = -1;
  String _currentlyPlayingVideoId = '';
  final _logger = Logger('SearchScreen');
  List<String> _searchHistory = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    _searchController = TextEditingController(text: searchProvider.query);
    _loadSearchHistory();
    _initYouTubeService();
    _scrollController.addListener(_onScroll);
  }
  
  Future<void> _initYouTubeService() async {
    await _youtubeService.init();
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _searchHistory = prefs.getStringList('search_history') ?? [];
      });
    } catch (e) {
      _logger.warning('Error loading search history: $e');
    }
  }

  Future<void> _saveSearchHistory(String query) async {
    if (query.isEmpty) return;
    
    try {
      // Remove if exists and add to the beginning
      _searchHistory.remove(query);
      _searchHistory.insert(0, query);
      
      // Keep only last 10 searches
      if (_searchHistory.length > 10) {
        _searchHistory = _searchHistory.sublist(0, 10);
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('search_history', _searchHistory);
    } catch (e) {
      _logger.warning('Error saving search history: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _youtubeService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search() async {
    final searchProvider = Provider.of<SearchProvider>(context, listen: false);
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    await _saveSearchHistory(query);
    searchProvider.setQuery(query);
    searchProvider.setLoading(true);
    searchProvider.setResults([]);
    setState(() {
      _loadingItemIndex = -1;
      _showHistory = false;
    });
    try {
      if (!_youtubeService.isConnected) {
        throw Exception('No internet connection. Please check your network settings.');
      }
      final results = await _youtubeService.search(query);
      searchProvider.setResults(results, continuation: YouTubeMusicApi.lastSearchContinuationToken);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No results found for "$query"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search error: e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      searchProvider.setLoading(false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final provider = Provider.of<SearchProvider>(context, listen: false);
    if (provider.isLoadingMore || provider.continuationToken == null) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final provider = Provider.of<SearchProvider>(context, listen: false);
    final token = provider.continuationToken;
    if (token == null) return;
    provider.setLoadingMore(true);
    try {
      final more = await _youtubeService.searchNext(token);
      provider.appendResults(more, continuation: YouTubeMusicApi.lastSearchContinuationToken);
    } catch (e) {
      // ignore for now
    } finally {
      provider.setLoadingMore(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);
    final theme = Theme.of(context);
    final searchProvider = Provider.of<SearchProvider>(context);
    final _searchResults = searchProvider.results;
    final _isLoading = searchProvider.isLoading;
    
    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevents RenderFlex overflow when keyboard appears
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            snap: false,
            title: null, // Remove the 'Search' text from the SliverAppBar
            expandedHeight: 56, // Match the search bar height
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56), // Match the search bar height
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16), // Remove vertical padding
                child: _buildSearchBar(theme),
              ),
            ),
          ),
          if (_showHistory && _searchHistory.isNotEmpty && !_isLoading)
            _buildSearchHistory(),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchResults.isEmpty && !_showHistory)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search, size: 80, color: theme.disabledColor),
                    const SizedBox(height: 16),
                    Text(
                      'Search for your favorite music',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!_showHistory)
            _buildSearchResults(audioHandler, _searchResults),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search songs, artists, albums...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _showHistory = true;
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            _showHistory = value.isEmpty;
          });
        },
        onSubmitted: (_) => _search(),
        onTap: () {
          setState(() {
            _showHistory = true;
          });
        },
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildSearchHistory() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final query = _searchHistory[index];
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(query),
            trailing: IconButton(
              icon: const Icon(Icons.north_west),
              onPressed: () {
                _searchController.text = query;
                _search();
              },
            ),
            onTap: () {
              _searchController.text = query;
              _search();
            },
          );
        },
        childCount: _searchHistory.length,
      ),
    );
  }

  Widget _buildSearchResults(AudioHandler audioHandler, List<YoutubeMusicVideo> searchResults) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final currentMediaItem = mediaSnapshot.data;
        
        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, playbackSnapshot) {
            final playbackState = playbackSnapshot.data;
            final isPlaying = playbackState?.playing ?? false;
            
            // Update currently playing video ID from extras only if changed
            if (currentMediaItem != null && currentMediaItem.extras != null) {
              final videoId = currentMediaItem.extras!['videoId'] as String?;
              String? newId;
              if (videoId != null) {
                newId = videoId;
              } else if (currentMediaItem.extras!.containsKey('url')) {
                final url = currentMediaItem.extras!['url'] as String?;
                if (url != null && url.length == 11 && !url.contains('/') && !url.contains('.')) {
                  newId = url;
                  _logger.info('Using URL as video ID: $url');
                }
              }
              if (newId != null && newId != _currentlyPlayingVideoId) {
                _currentlyPlayingVideoId = newId;
                _logger.info('Current playing video ID: $_currentlyPlayingVideoId');
              }
            }
            
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == searchResults.length) {
                    // loading indicator row
                    return Provider.of<SearchProvider>(context, listen: false).isLoadingMore ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ) : const SizedBox.shrink();
                  }
                  final video = searchResults[index];
                  final bool isItemLoading = index == _loadingItemIndex;
                  final bool isCurrentlyPlaying = video.videoId == _currentlyPlayingVideoId;
                  
                  return ListTile(
                    leading: video.thumbnailUrl.isNotEmpty 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              video.thumbnailUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.music_note),
                                );
                              },
                            ),
                          )
                        : Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.music_note),
                          ),
                    title: Text(
                      video.title,
                      style: TextStyle(
                        fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
                        // Remove color override for current song
                        // color: isCurrentlyPlaying
                        //     ? Theme.of(context).primaryColor
                        //     : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      video.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isItemLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: isCurrentlyPlaying
                                ? Icon(isPlaying ? Icons.pause : Icons.play_arrow)
                                : const Icon(Icons.play_arrow),
                            onPressed: (isCurrentlyPlaying || !isItemLoading)
                           ? () async {
                               if (isCurrentlyPlaying) {
                                 if (isPlaying) {
                                   await audioHandler.pause();
                                 } else {
                                   await audioHandler.play();
                                 }
                                 return;
                               }
                               setState(() {
                                 _loadingItemIndex = index;
                               });
                               try {
                                 final String? streamUrl = await _youtubeService.getStreamingUrl(video.videoId);
                                 if (streamUrl == null) {
                                   _logger.severe('Failed to get streaming URL for video ID: ${video.videoId}');
                                   _youtubeService.printProcessedVideoIds();
                                   setState(() {
                                     _loadingItemIndex = -1;
                                   });
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     SnackBar(
                                       content: Text('Cannot play this song: Unable to get streaming URL for ${video.title}. Video ID: ${video.videoId}'),
                                       duration: const Duration(seconds: 5),
                                     ),
                                   );
                                   return;
                                 }
                                 _logger.info('Got streaming URL (${streamUrl.length} chars): ${streamUrl.substring(0, math.min(100, streamUrl.length))}...');

                                 final updatedMediaItem = _youtubeService.youtubeVideoToMediaItem(video).copyWith(
                                   id: streamUrl,
                                   extras: {
                                     ...?_youtubeService.youtubeVideoToMediaItem(video).extras,
                                     'url': streamUrl,
                                   },
                                 );

                                 await (audioHandler as MyAudioHandler).clearAndPlay(updatedMediaItem);

                                // Wait until playback actually starts before navigating / clearing loader
                                try {
                                  await audioHandler.playbackState.firstWhere((s) => s.playing);
                                } catch (_) {}

                                if (context.mounted) {
                                  Navigator.of(context).pushNamed('/player');
                                }

                                setState(() {
                                  _loadingItemIndex = -1;
                                  _currentlyPlayingVideoId = video.videoId;
                                });
                                _addToSearchHistory(video.title);
                              } catch (e) {
                                _logger.severe('Error playing song: $e');
                                setState(() {
                                  _loadingItemIndex = -1;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error playing song: ${e.toString()}'),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          : null,
                          ),
                    onTap: null, // Disable ListTile tap
                  );
                },
                childCount: searchResults.length + 1,
              ),
            );
          },
        );
      },
    );
  }

  void _addToSearchHistory(String title) {
    if (title.isNotEmpty) {
      _saveSearchHistory(title);
    }
  }
}