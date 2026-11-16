import 'package:material_ui/material_ui.dart';

/// Fundo da janela do app.py (`background_color="#0f0f10"`).
const Color kBackground = Color(0xFF0F0F10);
const Color kPanel = Color(0xFF151517);
const Color kPanelHigh = Color(0xFF1F1F23);
const Color kLine = Color(0xFF2A2A2F);
const Color kSeed = Color(0xFFE5483C);

/// Cor da linha traduzida (a original fica branca).
const Color kTranslation = Color(0xFFFFD866);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kSeed, brightness: Brightness.dark).copyWith(
    surface: kPanel,
    surfaceContainerLowest: kBackground,
    surfaceContainerLow: const Color(0xFF131315),
    surfaceContainer: kPanel,
    surfaceContainerHigh: kPanelHigh,
    surfaceContainerHighest: const Color(0xFF26262B),
    outlineVariant: kLine,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1, space: 1),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Fonte de largura fixa (tempos, diagnóstico).
const TextStyle kMono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Roboto Mono', 'monospace', 'Courier New'],
  fontFeatures: [FontFeature.tabularFigures()],
);
