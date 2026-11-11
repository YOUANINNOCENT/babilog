/// 250000 → « 250 000 FCFA ».
String fcfa(int? montant, {bool unite = true}) {
  final s = (montant ?? 0).abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  final n = '${(montant ?? 0) < 0 ? '−' : ''}$b';
  return unite ? '$n FCFA' : n;
}

/// « 200 000 FCFA » → 200000.
int? lireMontant(String texte) {
  final c = texte.replaceAll(RegExp(r'[^0-9]'), '');
  return c.isEmpty ? null : int.parse(c);
}

String pluriel(int n, String mot, [String? motPluriel]) => '$n ${n > 1 ? (motPluriel ?? '${mot}s') : mot}';
