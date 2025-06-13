import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        if (mediaItem == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
          child: Container(
            height: 60,
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: ListTile(
              leading: mediaItem.artUri != null ? Image.network(mediaItem.artUri.toString()) : null,
              title: Text(mediaItem.title, overflow: TextOverflow.ellipsis),
              subtitle: Text(mediaItem.artist ?? '', overflow: TextOverflow.ellipsis),
              trailing: StreamBuilder<PlaybackState>(
                stream: audioHandler.playbackState,
                builder: (context, snapshot) {
                  final playbackState = snapshot.data;
                  final isPlaying = playbackState?.playing ?? false;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => audioHandler.skipToPrevious(),
                      ),
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () {
                          if (isPlaying) {
                            audioHandler.pause();
                          } else {
                            audioHandler.play();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => audioHandler.skipToNext(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
} 