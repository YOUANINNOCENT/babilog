/// Données de démonstration (exemples inventés), identiques à l'app mobile.
library;

import 'dart:math';

import 'prix.dart';

const communes = [
  'Abobo', 'Adjamé', 'Anyama', 'Attécoubé', 'Bingerville', 'Cocody',
  'Koumassi', 'Marcory', 'Plateau', 'Port-Bouët', 'Songon', 'Treichville',
  'Yopougon',
];

const quartiers = <String, List<String>>{
  'Abobo': ['Abobo Gare', 'Avocatier', 'PK 18', 'Abobo Baoulé'],
  'Adjamé': ['Williamsville', '220 Logements', 'Adjamé Liberté'],
  'Anyama': ['Anyama Centre', 'Ebimpé'],
  'Attécoubé': ['Santé', 'Locodjro', 'Agban'],
  'Bingerville': ['Bingerville Centre', 'Akandjé', 'Feh Kessé'],
  'Cocody': ['Angré', 'Riviera 3', 'II Plateaux', 'Riviera Palmeraie', 'Blockhaus', 'Danga'],
  'Koumassi': ['Remblais', 'Koumassi Campement', 'Sicogi'],
  'Marcory': ['Zone 4', 'Biétry', 'Anoumabo', 'Marcory Résidentiel'],
  'Plateau': ['Plateau Centre', 'Indénié'],
  'Port-Bouët': ['Vridi', 'Gonzagueville', 'Adjouffou'],
  'Songon': ['Songon Agban', 'Songon Kassemblé'],
  'Treichville': ['Arras', 'Biafra', 'Belleville'],
  'Yopougon': ['Niangon', 'Sideci', 'Selmer', 'Toits Rouges'],
};

/// « Meublé » n'est pas un équipement : c'est la colonne annonces.meuble.
const equipements = ['Climatisation', 'Cuisine équipée', 'Forage', 'Gardien', 'Groupe électrogène', 'Parking'];

const types = ['Studio', 'Appartement', 'Villa'];

const motifsSignalement = [
  'Le logement n\'existe pas ou est déjà loué',
  'Prix ou informations trompeurs',
  'On me demande de l\'argent avant la visite',
  'Photos qui ne correspondent pas',
  'Autre problème',
];

/// Comptes de démonstration (mot de passe : « password »).
const comptes = [
  ('Administrateur BabiLogis', 'admin@babilogis.ci', '0700000000', 'admin', null),
  ('Agence Horizon', 'horizon@babilogis.ci', '0701020304', 'annonceur', 'agence'),
  ('Agence Lagune', 'lagune@babilogis.ci', '0705060708', 'annonceur', 'agence'),
  ('Immo Plus Abidjan', 'immoplus@babilogis.ci', '0709101112', 'annonceur', 'agence'),
  ('Kouadio Yao', 'kouadio@babilogis.ci', '0501020304', 'annonceur', 'particulier'),
  ('Fatou Diabaté', 'fatou@babilogis.ci', '0505060708', 'annonceur', 'particulier'),
  ('Awa Koné', 'awa@babilogis.ci', '0102030405', 'locataire', null),
];

class AnnonceDemo {
  AnnonceDemo(this.reference, this.type, this.commune, this.quartier, this.pieces, this.chambres, this.sdb, this.meuble,
      this.loyer, this.estMin, this.estMax, this.equipements, this.annonceur, this.description, this.ageJours);

  final String reference, type, commune, quartier, annonceur, description;
  final int pieces, chambres, sdb, loyer, estMin, estMax, ageJours;
  final bool meuble;
  final List<String> equipements;
}

/// Les 12 annonces écrites à la main (mêmes références que l'app mobile).
final annoncesEcrites = [
  AnnonceDemo('BL-1001', 'Appartement', 'Cocody', 'Angré', 3, 2, 2, false, 250000, 235000, 270000,
      ['Parking', 'Gardien', 'Forage', 'Climatisation'], 'Agence Horizon',
      'Appartement lumineux au 2e étage d\'une résidence calme, proche des commerces et des écoles. Cuisine équipée.', 1),
  AnnonceDemo('BL-1002', 'Appartement', 'Cocody', 'Riviera 3', 3, 2, 1, false, 230000, 240000, 275000, ['Gardien', 'Forage'],
      'Agence Horizon', 'Appartement au rez-de-chaussée avec petite cour, quartier résidentiel calme.', 2),
  AnnonceDemo('BL-1003', 'Appartement', 'Cocody', 'II Plateaux', 3, 2, 2, false, 270000, 250000, 285000, ['Parking', 'Climatisation'],
      'Particulier', 'Appartement rénové, proche des grands axes.', 3),
  AnnonceDemo('BL-1004', 'Appartement', 'Cocody', 'Blockhaus', 3, 2, 1, false, 290000, 220000, 255000, ['Gardien'], 'Particulier',
      'Appartement avec vue, à rafraîchir.', 4),
  AnnonceDemo('BL-1005', 'Villa', 'Cocody', 'Riviera Palmeraie', 5, 4, 3, false, 650000, 600000, 700000,
      ['Parking', 'Gardien', 'Groupe électrogène', 'Climatisation'], 'Agence Horizon', 'Villa familiale avec jardin et dépendance.', 5),
  AnnonceDemo('BL-1006', 'Studio', 'Marcory', 'Zone 4', 1, 1, 1, true, 180000, 130000, 160000, ['Climatisation', 'Gardien'],
      'Agence Lagune', 'Studio meublé dans une résidence sécurisée.', 6),
  AnnonceDemo('BL-1007', 'Appartement', 'Marcory', 'Biétry', 3, 2, 2, false, 220000, 205000, 240000, ['Parking', 'Forage'],
      'Agence Lagune', 'Appartement proche de la lagune, quartier animé.', 7),
  AnnonceDemo('BL-1008', 'Appartement', 'Yopougon', 'Niangon', 2, 1, 1, false, 90000, 100000, 120000, ['Forage'], 'Particulier',
      'Appartement simple et propre, proche des transports.', 8),
  AnnonceDemo('BL-1009', 'Appartement', 'Plateau', 'Plateau Centre', 4, 3, 2, false, 450000, 360000, 410000,
      ['Parking', 'Climatisation', 'Gardien'], 'Agence Horizon', 'Grand appartement en plein centre des affaires.', 9),
  AnnonceDemo('BL-1010', 'Studio', 'Abobo', 'Abobo Gare', 1, 1, 1, false, 50000, 45000, 60000, [], 'Particulier',
      'Studio non meublé, proche de la gare.', 1),
  AnnonceDemo('BL-1011', 'Appartement', 'Koumassi', 'Remblais', 2, 1, 1, false, 130000, 115000, 140000, ['Forage', 'Gardien'],
      'Agence Lagune', 'Appartement avec balcon, quartier calme.', 2),
  AnnonceDemo('BL-1012', 'Appartement', 'Bingerville', 'Akandjé', 3, 2, 2, false, 160000, 150000, 185000, ['Parking', 'Forage'],
      'Particulier', 'Appartement neuf dans une petite résidence.', 3),
];

const _annonceurs = ['Agence Horizon', 'Agence Lagune', 'Particulier', 'Particulier', 'Immo Plus Abidjan'];
const _equipementsPossibles = ['Parking', 'Gardien', 'Climatisation', 'Forage', 'Groupe électrogène'];

/// Même générateur (même graine) que DemoData.simuler dans l'app mobile.
List<AnnonceDemo> annoncesSimulees({int seed = 2026, int nombre = 48}) {
  final r = Random(seed);
  return [
    for (var i = 0; i < nombre; i++) _simuler(r, 'BL-${3001 + i}'),
  ];
}

AnnonceDemo _simuler(Random r, String id) {
  final commune = communes[r.nextInt(communes.length)];
  final qs = quartiers[commune]!;
  final quartier = qs[r.nextInt(qs.length)];
  final t = r.nextDouble();
  final type = t < 0.2 ? 'Studio' : (t < 0.85 ? 'Appartement' : 'Villa');
  final pieces = switch (type) {
    'Studio' => 1,
    'Villa' => 4 + r.nextInt(3),
    _ => 2 + r.nextInt(3),
  };
  final equip = _equipementsPossibles.where((_) => r.nextDouble() < 0.4).toList();
  final meuble = type == 'Studio' ? r.nextDouble() < 0.5 : r.nextDouble() < 0.1;
  final central = prixCentral(commune, type, pieces, meuble, equip.length);
  final loyer = arrondir(central * (0.85 + r.nextDouble() * 0.35));
  final annonceur = _annonceurs[r.nextInt(_annonceurs.length)];
  final description = '${type == 'Studio' ? 'Studio' : '$type de $pieces pièces'} à $quartier ($commune)'
      '${equip.isEmpty ? '' : ', avec ${equip.join(', ').toLowerCase()}'}. '
      '${meuble ? 'Logement meublé. ' : ''}Annonce de démonstration générée automatiquement.';
  final age = 1 + r.nextInt(30);
  return AnnonceDemo(id, type, commune, quartier, pieces, max(1, pieces - 1), pieces >= 3 ? 2 : 1, meuble, loyer,
      arrondir(central * 0.92), arrondir(central * 1.08), equip, annonceur, description, age);
}
