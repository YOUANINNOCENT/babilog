import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

const _equipements = ['Climatisation', 'Cuisine équipée', 'Forage', 'Gardien', 'Groupe électrogène', 'Parking', 'Meublé'];
const _tris = [
  ('prix_juste', 'Prix juste d\'abord'),
  ('recentes', 'Plus récentes'),
  ('prix_croissant', 'Prix croissant'),
  ('prix_decroissant', 'Prix décroissant'),
];

/// Filtres lus depuis l'adresse (/annonces?commune=Cocody&pieces=3…).
class Filtres {
  Filtres.depuis(Uri uri)
      : commune = uri.queryParameters['commune'],
        type = uri.queryParameters['type'],
        pieces = int.tryParse(uri.queryParameters['pieces'] ?? ''),
        budgetMax = int.tryParse(uri.queryParameters['budget_max'] ?? ''),
        juste = uri.queryParameters['juste'] == '1',
        texte = uri.queryParameters['q'] ?? '',
        tri = uri.queryParameters['tri'] ?? 'prix_juste',
        page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1,
        equipements = {...(uri.queryParametersAll['equipements[]'] ?? const []), ...(uri.queryParametersAll['equipements'] ?? const [])};

  Filtres({
    this.commune,
    this.type,
    this.pieces,
    this.budgetMax,
    this.juste = false,
    this.texte = '',
    this.tri = 'prix_juste',
    this.page = 1,
    Set<String>? equipements,
  }) : equipements = equipements ?? {};

  String? commune, type;
  int? pieces, budgetMax;
  bool juste;
  String texte, tri;
  int page;
  Set<String> equipements;

  int get nombreActifs =>
      [commune, type, pieces, budgetMax].where((e) => e != null).length + (juste ? 1 : 0) + (texte.isNotEmpty ? 1 : 0) + equipements.length;

  Map<String, dynamic> get parametres => {
        'commune': commune,
        'type': type,
        'pieces': pieces,
        'budget_max': budgetMax,
        if (juste) 'juste': 1,
        'q': texte,
        'tri': tri,
        'page': page > 1 ? page : null,
        'equipements': equipements.toList(),
        'per_page': 12,
      };

  String route() {
    final q = <String, dynamic>{};
    parametres.forEach((k, v) {
      if (k == 'per_page' || v == null) return;
      if (v is List) {
        if (v.isNotEmpty) q['equipements'] = v.map((e) => '$e').toList();
      } else if ('$v'.isNotEmpty && !(k == 'tri' && v == 'prix_juste')) {
        q[k] = '$v';
      }
    });
    return Uri(path: '/annonces', queryParameters: q.isEmpty ? null : q).toString();
  }

  Filtres copie() => Filtres(
      commune: commune,
      type: type,
      pieces: pieces,
      budgetMax: budgetMax,
      juste: juste,
      texte: texte,
      tri: tri,
      page: page,
      equipements: {...equipements});
}

class PageRecherche extends StatelessWidget {
  const PageRecherche({super.key, required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final f = Filtres.depuis(uri);
    final large = MediaQuery.sizeOf(context).width >= 980;
    final resultats = _Resultats(filtres: f, key: ValueKey(uri.toString()));
    return SiteScaffold(
      actif: 'rechercher',
      child: Contenu(
        vertical: 28,
        child: large
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 290, child: _PanneauFiltres(initial: f)),
                  const SizedBox(width: 28),
                  Expanded(child: resultats),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Carte(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text('Filtres${f.nombreActifs > 0 ? ' · ${f.nombreActifs}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        leading: const Icon(Icons.tune),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [_PanneauFiltres(initial: f, cadre: false)],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  resultats,
                ],
              ),
      ),
    );
  }
}

class _PanneauFiltres extends StatefulWidget {
  const _PanneauFiltres({required this.initial, this.cadre = true});

  final Filtres initial;
  final bool cadre;

  @override
  State<_PanneauFiltres> createState() => _PanneauFiltresState();
}

class _PanneauFiltresState extends State<_PanneauFiltres> {
  late Filtres f = widget.initial.copie();
  late final _texte = TextEditingController(text: f.texte);
  late final Future<List<Commune>> _communes = () async {
    final r = await Api.instance.get('/communes') as Map<String, dynamic>;
    return (r['data'] as List).map((e) => Commune.fromJson(e as Map<String, dynamic>)).toList();
  }();

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  void _appliquer() {
    f
      ..texte = _texte.text.trim()
      ..page = 1;
    Navigator.of(context).pushReplacementNamed(f.route());
  }

  @override
  Widget build(BuildContext context) {
    final budget = (f.budgetMax ?? 700000).toDouble().clamp(25000.0, 700000.0);
    final contenu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.cadre) ...[
          Row(children: [
            const Expanded(child: Text('Filtres', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            if (f.nombreActifs > 0) Pastille('${f.nombreActifs}'),
          ]),
          const SizedBox(height: 16),
        ],
        Champ('Mot-clé ou quartier', TextField(controller: _texte, decoration: deco(hint: 'Angré, Zone 4…'), onSubmitted: (_) => _appliquer())),
        const SizedBox(height: 14),
        Champ(
          'Commune',
          FutureBuilder<List<Commune>>(
            future: _communes,
            builder: (context, s) => Liste<String>(
              valeur: f.commune,
              libelleVide: 'Toutes les communes',
              options: [for (final c in s.data ?? const <Commune>[]) (c.nom, '${c.nom} (${c.nbAnnonces})')],
              onChanged: (v) => setState(() => f.commune = v),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Champ(
          'Type',
          Liste<String>(
            valeur: f.type,
            libelleVide: 'Tous les types',
            options: const [('Studio', 'Studio'), ('Appartement', 'Appartement'), ('Villa', 'Villa')],
            onChanged: (v) => setState(() => f.type = v),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Pièces', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in [1, 2, 3, 4, 5])
            Puce(p == 5 ? '5+' : '$p', choisi: f.pieces == p, onTap: () => setState(() => f.pieces = f.pieces == p ? null : p)),
        ]),
        const SizedBox(height: 14),
        Text('Budget maximum : ${budget >= 700000 ? 'sans limite' : fcfa(budget.round())}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        Slider(
          value: budget,
          min: 25000,
          max: 700000,
          divisions: 27,
          label: budget >= 700000 ? 'Sans limite' : fcfa(budget.round()),
          onChanged: (v) => setState(() => f.budgetMax = v >= 700000 ? null : v.round()),
        ),
        const Text('Équipements', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _equipements)
            Puce(e, choisi: f.equipements.contains(e), onTap: () => setState(() => f.equipements.contains(e) ? f.equipements.remove(e) : f.equipements.add(e))),
        ]),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: f.juste,
          activeColor: Couleurs.primary,
          title: const Text('Masquer les loyers au-dessus du marché'),
          onChanged: (v) => setState(() => f.juste = v ?? false),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _appliquer, child: const Text('Afficher les résultats')),
        if (widget.initial.nombreActifs > 0)
          TextButton(onPressed: () => Navigator.of(context).pushReplacementNamed('/annonces'), child: const Text('Réinitialiser')),
      ],
    );
    return widget.cadre ? Carte(child: contenu) : contenu;
  }
}

class _Resultats extends StatelessWidget {
  const _Resultats({super.key, required this.filtres});

  final Filtres filtres;

  @override
  Widget build(BuildContext context) {
    final f = filtres;
    final titre = [if (f.type != null) f.type!, f.commune ?? 'Abidjan'].join(' · ');
    return Chargeur<Resultats<Annonce>>(
      charger: () async => Resultats.fromJson(await Api.instance.get('/annonces', f.parametres) as Map<String, dynamic>, Annonce.fromJson),
      builder: (context, r, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Titre(f.texte.isNotEmpty ? '« ${f.texte} »' : titre, taille: 28),
                  Semantics(
                    liveRegion: true,
                    child: Text('${pluriel(r.total, 'logement')} trouvé${r.total > 1 ? 's' : ''}',
                        style: const TextStyle(color: Couleurs.texte2)),
                  ),
                ],
              ),
              SizedBox(
                width: 240,
                child: Liste<String>(
                  valeur: f.tri,
                  options: _tris,
                  onChanged: (v) {
                    final g = f.copie()
                      ..tri = v ?? 'prix_juste'
                      ..page = 1;
                    Navigator.of(context).pushReplacementNamed(g.route());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (r.elements.isEmpty)
            Carte(
              child: Vide(
                icone: Icons.search_off,
                titre: 'Aucun logement pour ces critères',
                texte: 'Élargissez votre budget ou retirez un filtre.',
                action: OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacementNamed('/annonces'), child: const Text('Réinitialiser les filtres')),
              ),
            )
          else ...[
            Grille(largeurMin: 260, max: 3, enfants: [for (final a in r.elements) CarteAnnonce(a)]),
            if (r.derniere > 1) ...[
              const SizedBox(height: 28),
              _Pagination(page: r.page, derniere: r.derniere, filtres: f),
            ],
          ],
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.page, required this.derniere, required this.filtres});

  final int page, derniere;
  final Filtres filtres;

  void _aller(BuildContext context, int p) {
    final g = filtres.copie()..page = p;
    Navigator.of(context).pushReplacementNamed(g.route());
  }

  @override
  Widget build(BuildContext context) {
    final pages = <int>{1, derniere, page - 1, page, page + 1}.where((p) => p >= 1 && p <= derniere).toList()..sort();
    final boutons = <Widget>[
      IconButton(
          tooltip: 'Page précédente', onPressed: page > 1 ? () => _aller(context, page - 1) : null, icon: const Icon(Icons.chevron_left)),
    ];
    int? avant;
    for (final p in pages) {
      if (avant != null && p - avant > 1) boutons.add(const Padding(padding: EdgeInsets.all(8), child: Text('…')));
      boutons.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: p == page
            ? FilledButton(onPressed: null, style: FilledButton.styleFrom(minimumSize: const Size(46, 46), disabledBackgroundColor: Couleurs.primary, disabledForegroundColor: Colors.white), child: Text('$p'))
            : OutlinedButton(
                onPressed: () => _aller(context, p), style: OutlinedButton.styleFrom(minimumSize: const Size(46, 46), padding: EdgeInsets.zero), child: Text('$p')),
      ));
      avant = p;
    }
    boutons.add(IconButton(
        tooltip: 'Page suivante',
        onPressed: page < derniere ? () => _aller(context, page + 1) : null,
        icon: const Icon(Icons.chevron_right)));
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: boutons);
  }
}
