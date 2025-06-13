import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/audio_handler.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);
    final myAudioHandler = audioHandler as MyAudioHandler;
    return StreamBuilder<List<MediaItem>>(
      stream: audioHandler.queue,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? [];
        return StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final mediaItem = snapshot.data;
            if ((mediaItem == null && queue.isEmpty) || queue.isEmpty) return const SizedBox.shrink();
            final current = mediaItem ?? (queue.isNotEmpty ? queue.first : null);
            if (current == null) return const SizedBox.shrink();
            final currentIndex = queue.indexWhere((item) => item.id == current.id);
            final hasPrevious = currentIndex > 0;
            final hasNext = currentIndex >= 0 && currentIndex < queue.length - 1;
            return GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/player'),
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    if (current.artUri != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          current.artUri.toString(),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 48,
                            height: 48,
                            color: Colors.grey[300],
                            child: const Icon(Icons.music_note, size: 32),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[300],
                        child: const Icon(Icons.music_note, size: 32),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            current.title,
                            style: Theme.of(context).textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((current.artist ?? '').isNotEmpty)
                            Text(
                              current.artist!,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          StreamBuilder<Duration>(
                            stream: myAudioHandler.positionStream,
                            builder: (context, posSnap) {
                              final pos = posSnap.data ?? Duration.zero;
                              final total = current.duration ?? Duration.zero;
                              return LinearProgressIndicator(
                                value: total.inMilliseconds > 0
                                    ? pos.inMilliseconds / total.inMilliseconds
                                    : 0.0,
                                minHeight: 3,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PlayerControls(
                      audioHandler: audioHandler,
                      hasPrevious: hasPrevious,
                      hasNext: hasNext,
                      previousIndex: hasPrevious ? currentIndex - 1 : null,
                      nextIndex: hasNext ? currentIndex + 1 : null,
                      queue: queue,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final AudioHandler audioHandler;
  final bool hasPrevious;
  final bool hasNext;
  final int? previousIndex;
  final int? nextIndex;
  final List<MediaItem> queue;
  const _PlayerControls({
    required this.audioHandler,
    required this.hasPrevious,
    required this.hasNext,
    required this.previousIndex,
    required this.nextIndex,
    required this.queue,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: hasPrevious
                  ? () async {
                      if (previousIndex != null) {
                        await audioHandler.skipToQueueItem(previousIndex!);
                        await audioHandler.play();
                      }
                    }
                  : null,
            ),
            IconButton(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: playing ? audioHandler.pause : audioHandler.play,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: () async {
                await audioHandler.skipToNext();
              },
            ),
          ],
        );
      },
    );
  }
}
