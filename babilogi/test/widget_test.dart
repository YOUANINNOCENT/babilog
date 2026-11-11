import 'package:babilogi/format.dart';
import 'package:babilogi/models.dart';
import 'package:babilogi/pages/recherche.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Format des montants', () {
    expect(fcfa(250000), '250 000 FCFA');
    expect(lireMontant('200 000 FCFA'), 200000);
  });

  test('Les filtres font l\'aller-retour avec l\'adresse', () {
    final f = Filtres.depuis(Uri.parse('/annonces?commune=Cocody&pieces=3&equipements=Parking&equipements=Gardien'));
    expect(f.commune, 'Cocody');
    expect(f.pieces, 3);
    expect(f.equipements, {'Parking', 'Gardien'});
    final g = Filtres.depuis(Uri.parse(f.route()));
    expect(g.equipements, f.equipements);
    expect(g.nombreActifs, 4);
  });

  test('Lecture d\'une annonce de l\'API', () {
    final a = Annonce.fromJson({
      'id': 'BL-1001', 'type': 'Appartement', 'commune': 'Cocody', 'quartier': 'Angré', 'pieces': 3, 'chambres': 2,
      'salles_bain': 2, 'meuble': false, 'loyer': 250000, 'estimation_min': 235000, 'estimation_max': 270000,
      'equipements': ['Parking'], 'annonceur': 'Agence Horizon', 'age_jours': 1, 'verdict': 'juste',
      'verdict_libelle': 'Prix juste', 'titre': 'Appartement 3 pièces',
    });
    expect(a.details, 'Cocody, Angré · 2 chambres · parking');
    expect(a.estimationCentrale, 252500);
    expect(a.publiee, 'Publiée hier');
  });
}
