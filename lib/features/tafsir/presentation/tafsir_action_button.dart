import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/ayah_action_button.dart';
import '../../quran_reader/domain/quran_repository.dart';
import '../../quran_reader/presentation/quran_reader_provider.dart';
import '../domain/tafsir_repository.dart';
import 'tafsir_screen.dart';

/// The Ayah Context Sheet's "تفسير" action (spec §10's Actions row / §11:
/// "Tafsir open: Tafsir reader replaces/extends the context layer without
/// losing ayah identity"): pushes the full-screen [TafsirScreen], handing it
/// the same [QuranReaderProvider] instance explicitly — a route pushed via
/// `Navigator.push` isn't a descendant of the reader's own
/// `ChangeNotifierProvider`, so ambient `context.read` wouldn't find it
/// there once inside [TafsirScreen].
class TafsirActionButton extends StatelessWidget {
  const TafsirActionButton({
    super.key,
    required this.ayahKey,
    required this.quranRepository,
    required this.tafsirRepository,
  });

  final String ayahKey;
  final QuranRepository quranRepository;
  final TafsirRepository tafsirRepository;

  @override
  Widget build(BuildContext context) {
    return AyahActionButton(
      icon: Icons.menu_book_outlined,
      label: 'تفسير',
      onPressed: () {
        final quranReaderProvider = context.read<QuranReaderProvider>();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TafsirScreen(
              initialAyahKey: ayahKey,
              quranRepository: quranRepository,
              tafsirRepository: tafsirRepository,
              quranReaderProvider: quranReaderProvider,
            ),
          ),
        );
      },
    );
  }
}
