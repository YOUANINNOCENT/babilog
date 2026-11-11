/// Dates et libellés en français.
library;

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];

String dateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// « Samedi 18 octobre »
String jourLibelle(DateTime d) {
  final s = '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';
  return s[0].toUpperCase() + s.substring(1);
}

/// « il y a 3 jours », « aujourd'hui »…
String ilYA(DateTime d, [DateTime? maintenant]) {
  final n = maintenant ?? DateTime.now();
  final m = n.difference(d).inMinutes;
  if (m < 1) return 'à l\'instant';
  if (m < 60) return 'il y a $m min';
  final h = m ~/ 60;
  if (h < 24) return 'il y a $h h';
  final j = h ~/ 24;
  if (j == 1) return 'hier';
  if (j < 30) return 'il y a $j jours';
  final mo = j ~/ 30;
  return 'il y a $mo mois';
}

/// Nombre de jours entiers entre deux dates (sans l'heure).
int joursEntre(DateTime a, DateTime b) =>
    DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;
