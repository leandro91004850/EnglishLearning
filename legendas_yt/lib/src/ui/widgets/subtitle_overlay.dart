import 'package:material_ui/material_ui.dart';

import '../../data/prefs.dart';
import '../theme.dart';

/// A legenda sobre o vídeo: a fala original e/ou a tradução, conforme [show].
/// [baseSize] é o tamanho para um vídeo de 720 de largura; a letra acompanha
/// o tamanho do vídeo (cresce na tela cheia).
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.original,
    required this.translation,
    required this.show,
    required this.baseSize,
  });

  final String original;
  final String? translation;
  final ShowMode show;
  final int baseSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = (box.maxWidth / 720).clamp(0.5, 2.0);
        final size = baseSize * scale;
        final tr = translation;
        final lines = <Widget>[
          if (show != ShowMode.translation && original.isNotEmpty)
            _Line(original, size: size, color: Colors.white),
          if (show != ShowMode.original && tr != null && tr.isNotEmpty)
            _Line(tr, size: size, color: kTranslation)
          // só a tradução, mas ela ainda não chegou: mostra a original apagada
          else if (show == ShowMode.translation && original.isNotEmpty)
            _Line(original, size: size, color: Colors.white54),
        ];
        if (lines.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            // acima da barra de controles do YouTube
            padding: EdgeInsets.fromLTRB(box.maxWidth * .05, 0, box.maxWidth * .05, box.maxHeight * .14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) SizedBox(height: size * .2),
                  lines[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.size, required this.color});

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC8000000),
        borderRadius: BorderRadius.circular(size * .2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * .4, vertical: size * .08),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: size,
            height: 1.25,
            fontWeight: FontWeight.w500,
            shadows: const [Shadow(blurRadius: 3, color: Colors.black)],
          ),
        ),
      ),
    );
  }
}
