import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/theme/mushaf_theme.dart';
import 'audio_provider.dart';

/// Play/pause + reciter name + a simple progress bar for [ayahKey] (spec
/// §14/§10's "Audio: Play/Pause, Reciter, Optional synchronized highlight"
/// — the highlight itself lives on `QuranAyahText`, driven from the Ayah
/// Context Sheet's own `highlightedWordKey`, not here).
class AudioPlaybackRow extends StatelessWidget {
  const AudioPlaybackRow({super.key, required this.ayahKey});

  final String ayahKey;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final bool isCurrentAyah = audioProvider.currentAyahKey == ayahKey;
    final bool isLoading = isCurrentAyah && audioProvider.isLoading;
    final bool isPlaying = isCurrentAyah && audioProvider.isPlaying;
    final Object? error = isCurrentAyah ? audioProvider.error : null;
    final Duration position =
        isCurrentAyah ? audioProvider.position : Duration.zero;
    final Duration duration =
        isCurrentAyah ? audioProvider.duration : Duration.zero;
    final String? reciterName =
        isCurrentAyah ? audioProvider.track?.reciterName : null;

    return Row(
      children: [
        IconButton(
          onPressed: audioProvider.reciterId == null
              ? null
              : () => audioProvider.togglePlayPauseOrLoad(ayahKey),
          icon: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: mushafInkColor,
                ),
        ),
        Expanded(
          child: error != null
              ? const Text(
                  'تعذّر تشغيل الصوت',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reciterName ?? 'مشاري راشد العفاسي',
                      style: TextStyle(
                        fontSize: 12,
                        color: mushafInkColor.withValues(alpha: 0.7),
                      ),
                    ),
                    if (isCurrentAyah && duration > Duration.zero) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value:
                            (position.inMilliseconds / duration.inMilliseconds)
                                .clamp(0.0, 1.0),
                        minHeight: 3,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDuration(position)} / '
                        '${_formatDuration(duration)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: mushafInkColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
