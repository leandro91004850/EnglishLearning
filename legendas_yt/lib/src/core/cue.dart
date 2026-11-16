/// Uma fala da legenda: aparece em [start] segundos e fica [dur] segundos.
class Cue {
  const Cue(this.start, this.dur, this.text);

  factory Cue.fromJson(Map<String, dynamic> json) => Cue(
        (json['start'] as num).toDouble(),
        (json['dur'] as num).toDouble(),
        json['text'] as String,
      );

  final double start;
  final double dur;
  final String text;

  double get end => start + dur;

  Map<String, Object> toJson() => {'start': start, 'dur': dur, 'text': text};

  @override
  String toString() => 'Cue($start, $dur, $text)';
}

/// Índice da última fala que já começou em [seconds] (-1 se nenhuma começou).
/// As falas vêm em ordem de início.
int cueIndexAt(List<Cue> cues, double seconds) {
  var lo = 0, hi = cues.length - 1, found = -1;
  final t = seconds + 0.05; // margem para o tempo que o player informa
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= t) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}
