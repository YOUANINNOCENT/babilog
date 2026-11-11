import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// Baromètre des loyers : loyer médian par commune.
class PageBarometre extends StatelessWidget {
  const PageBarometre({super.key, this.pieces});

  final int? pieces;

  @override
  Widget build(BuildContext context) {
    const choix = [(null, 'Tous'), (1, 'Studio / 1 pièce'), (2, '2 pièces'), (3, '3 pièces'), (4, '4 pièces'), (5, '5 pièces et +')];
    return SiteScaffold(
      actif: 'barometre',
      child: Contenu(
        vertical: 36,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Titre('Baromètre des loyers', taille: 38),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
              width: 700,
              child: Text(
                'Loyer médian des annonces publiées sur BabiLogis, par commune. La médiane est le loyer du milieu : la moitié des logements sont moins chers, l\'autre moitié plus chers.',
                style: TextStyle(color: Couleurs.texte2),
              ),
            )),
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (p, libelle) in choix)
                Puce(libelle,
                    choisi: pieces == p,
                    onTap: () => Navigator.of(context).pushReplacementNamed(p == null ? '/barometre' : '/barometre?pieces=$p')),
            ]),
            const SizedBox(height: 22),
            Chargeur<List<LigneMarche>>(
              key: ValueKey(pieces),
              charger: () async {
                final r = await Api.instance.get('/marche', {'pieces': pieces}) as Map<String, dynamic>;
                return (r['data'] as List).map((e) => LigneMarche.fromJson(e as Map<String, dynamic>)).toList();
              },
              builder: (context, lignes, _) => lignes.isEmpty
                  ? const Carte(child: Vide(icone: Icons.bar_chart, titre: 'Pas encore assez d\'annonces', texte: 'Aucune annonce publiée pour ce nombre de pièces.'))
                  : _Barres(lignes: lignes, pieces: pieces),
            ),
          ],
        ),
      ),
    );
  }
}

class _Barres extends StatelessWidget {
  const _Barres({required this.lignes, required this.pieces});

  final List<LigneMarche> lignes;
  final int? pieces;

  @override
  Widget build(BuildContext context) {
    final max = lignes.map((l) => l.median).fold<int>(1, (a, b) => b > a ? b : a);
    final etroit = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Loyer médian par commune', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 16),
              for (final l in lignes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Semantics(
                    label: '${l.commune} : loyer médian ${fcfa(l.median)}',
                    excludeSemantics: true,
                    child: Row(children: [
                      SizedBox(
                        width: etroit ? 96 : 140,
                        child: InkWell(
                          onTap: () => aller(context,
                              Uri(path: '/annonces', queryParameters: {'commune': l.commune, if (pieces != null) 'pieces': '$pieces'}).toString()),
                          child: Text(l.commune, style: const TextStyle(color: Couleurs.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(color: Couleurs.surfaceMuted, borderRadius: BorderRadius.circular(6)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (l.median / max).clamp(0.02, 1.0),
                            child: Container(decoration: BoxDecoration(color: Couleurs.primary, borderRadius: BorderRadius.circular(6))),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: etroit ? 110 : 140,
                        child: Text(fcfa(l.median), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Carte(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: Couleurs.texte2, fontSize: 13),
              columns: const [
                DataColumn(label: Text('COMMUNE')),
                DataColumn(label: Text('ANNONCES'), numeric: true),
                DataColumn(label: Text('LOYER MÉDIAN'), numeric: true),
                DataColumn(label: Text('FOURCHETTE')),
                DataColumn(label: Text('PAR PIÈCE'), numeric: true),
                DataColumn(label: Text('AU-DESSUS DU MARCHÉ'), numeric: true),
              ],
              rows: [
                for (final l in lignes)
                  DataRow(cells: [
                    DataCell(Text(l.commune, style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text('${l.nbAnnonces}')),
                    DataCell(Text(fcfa(l.median), style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(Text('${fcfa(l.minimum, unite: false)} – ${fcfa(l.maximum)}', style: const TextStyle(color: Couleurs.texte2))),
                    DataCell(Text(fcfa(l.parPiece))),
                    DataCell(Text('${l.partAuDessus} %')),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Données de démonstration. Les vraies statistiques viendront des annonces collectées (bloc 1).',
            style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
      ],
    );
  }
}
