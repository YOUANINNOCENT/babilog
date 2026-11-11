/// Estimation du loyer juste par règles simples, en attendant le modèle IA
/// (blocs 2 et 5). Mêmes règles que l'app mobile et l'app desktop.
library;

const prixParPiece = <String, int>{
  'Cocody': 90000, 'Plateau': 100000, 'Marcory': 75000, 'Treichville': 60000,
  'Bingerville': 55000, 'Koumassi': 50000, 'Port-Bouët': 45000, 'Adjamé': 42000,
  'Yopougon': 38000, 'Attécoubé': 32000, 'Abobo': 28000, 'Songon': 26000,
  'Anyama': 24000,
};

int arrondir(num v) => (v / 5000).round() * 5000;

class Estimation {
  Estimation(this.minimum, this.maximum, this.source);

  final int minimum, maximum;
  final String source; // regles | modele

  int get centrale => arrondir((minimum + maximum) / 2);
}

double prixCentral(String commune, String type, int pieces, bool meuble, int nbEquipements) =>
    (prixParPiece[commune] ?? 50000) *
    (pieces < 1 ? 1 : pieces) *
    (type == 'Villa' ? 1.25 : 1.0) *
    (1 + 0.04 * nbEquipements) *
    (meuble ? 1.2 : 1.0);

Estimation estimerParRegles(String commune, String type, int pieces, bool meuble, int nbEquipements) {
  final c = prixCentral(commune, type, pieces, meuble, nbEquipements);
  return Estimation(arrondir(c * 0.92), arrondir(c * 1.08), 'regles');
}

/// bonne_affaire | juste | au_dessus (null si pas d'estimation).
String? verdict(int loyer, int? minimum, int? maximum) {
  if (minimum == null || maximum == null) return null;
  if (loyer < minimum) return 'bonne_affaire';
  if (loyer > maximum) return 'au_dessus';
  return 'juste';
}

String verdictLibelle(String? v) => switch (v) {
      'bonne_affaire' => 'Bonne affaire',
      'juste' => 'Prix juste',
      'au_dessus' => 'Au-dessus du marché',
      _ => 'En cours d\'analyse',
    };
