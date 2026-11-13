import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// Accueil : bandeau rouge, recherche, atouts, annonces récentes, appel aux annonceurs.
class PageAccueil extends StatelessWidget {
  const PageAccueil({super.key});

  @override
  Widget build(BuildContext context) {
    return const SiteScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Bandeau(),
          Contenu(child: _Atouts()),
          Contenu(child: _Recentes()),
          Contenu(child: _AppelAnnonceurs()),
        ],
      ),
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau();

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 700;
    return Stack(
      children: [
        // Le rouge s'arrête au milieu de la carte de recherche.
        const Positioned(left: 0, right: 0, top: 0, bottom: 62, child: ColoredBox(color: Couleurs.primary)),
        Contenu(
          child: Padding(
            padding: EdgeInsets.only(top: etroit ? 40 : 70),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Couleurs.pastille, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Location à Abidjan',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 740),
                  child: Semantics(
                    header: true,
                    child: Text('Le bon logement, au juste prix.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: etroit ? 36 : 58,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -1)),
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: const Text(
                    'Chaque annonce est comparée aux loyers du quartier. Vous savez tout de suite si le prix demandé est juste.',
                    style: TextStyle(color: Colors.white, fontSize: 19, height: 1.5),
                  ),
                ),
                SizedBox(height: etroit ? 36 : 56),
                const _Recherche(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Recherche extends StatefulWidget {
  const _Recherche();

  @override
  State<_Recherche> createState() => _RechercheState();
}

class _RechercheState extends State<_Recherche> {
  String? _commune;
  String? _type;
  final _budget = TextEditingController();
  late final Future<List<Commune>> _communes = _chargerCommunes();

  Future<List<Commune>> _chargerCommunes() async {
    final r = await Api.instance.get('/communes') as Map<String, dynamic>;
    return (r['data'] as List).map((e) => Commune.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  void _chercher() {
    final q = <String, String>{
      'commune': ?_commune,
      'type': ?_type,
      if (lireMontant(_budget.text) != null) 'budget_max': '${lireMontant(_budget.text)}',
    };
    aller(context, Uri(path: '/annonces', queryParameters: q.isEmpty ? null : q).toString());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final colonne = c.maxWidth < 860;
      final champs = <Widget>[
        Champ(
          'Commune',
          FutureBuilder<List<Commune>>(
            future: _communes,
            builder: (context, s) => Liste<String>(
              valeur: _commune,
              libelleVide: 'Toutes les communes',
              options: [for (final c in s.data ?? const <Commune>[]) (c.nom, c.nom)],
              onChanged: (v) => setState(() => _commune = v),
            ),
          ),
        ),
        Champ(
          'Type de logement',
          Liste<String>(
            valeur: _type,
            libelleVide: 'Tous les types',
            options: const [('Studio', 'Studio'), ('Appartement', 'Appartement'), ('Villa', 'Villa')],
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        Champ(
          'Budget maximum (FCFA / mois)',
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _chercher(),
            decoration: deco(hint: 'Ex : 200 000'),
          ),
        ),
        FilledButton.icon(
          onPressed: _chercher,
          icon: const Icon(Icons.search),
          label: const Text('Rechercher'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ];
      return Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Couleurs.bordure),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: colonne
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final w in champs) Padding(padding: const EdgeInsets.only(bottom: 14), child: w)],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < champs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 18),
                    Expanded(child: champs[i]),
                  ],
                ],
              ),
      );
    });
  }
}

class _Atouts extends StatelessWidget {
  const _Atouts();

  @override
  Widget build(BuildContext context) {
    const atouts = [
      (Icons.check, 'Prix vérifié', 'Un modèle compare chaque loyer aux logements semblables du même quartier.'),
      (Icons.warning_amber_rounded, 'Annonces suspectes signalées',
          'Les annonces anormales sont repérées avant que vous versiez une avance.'),
      (Icons.chat_bubble_outline, 'Un assistant pour vous guider',
          'Dans l\'application mobile, l\'assistant cherche, compare et rappelle vos droits.'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 52, bottom: 64),
      child: Grille(
        largeurMin: 300,
        max: 3,
        espace: 18,
        enfants: [
          for (final (icone, titre, texte) in atouts)
            Carte(
              padding: const EdgeInsets.all(22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: Couleurs.primarySoft, shape: BoxShape.circle),
                    child: Icon(icone, color: Couleurs.primary, size: 21),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(texte, style: const TextStyle(color: Couleurs.texte2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Recentes extends StatelessWidget {
  const _Recentes();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: 8,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Titre('Annonces récentes', taille: 32, niveau: 2),
                SizedBox(height: 6),
                Text('Le badge indique la position du loyer par rapport au marché.', style: TextStyle(color: Couleurs.texte2)),
              ],
            ),
            TextButton(
              onPressed: () => aller(context, '/annonces?tri=recentes'),
              child: const Text('Voir toutes les annonces', style: TextStyle(decoration: TextDecoration.underline)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Chargeur<List<Annonce>>(
          charger: () async {
            final r = await Api.instance.get('/annonces', {'tri': 'recentes', 'per_page': 8}) as Map<String, dynamic>;
            return Resultats.fromJson(r, Annonce.fromJson).elements;
          },
          builder: (context, annonces, _) => Grille(enfants: [for (final a in annonces) CarteAnnonce(a)]),
        ),
      ],
    );
  }
}

class _AppelAnnonceurs extends StatelessWidget {
  const _AppelAnnonceurs();

  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).utilisateur;
    // Un locataire connecté ne voit pas l'appel aux propriétaires et agences.
    if (u != null && !u.estAnnonceur) return const SizedBox(height: 36);
    return Padding(
      padding: const EdgeInsets.only(top: 56, bottom: 36),
      child: Carte(
        alerte: true,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 32),
        child: SizedBox(width: double.infinity, child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 16,
          spacing: 24,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Titre('Propriétaire ou agence ?', taille: 27, niveau: 2),
                SizedBox(height: 8),
                Text('Publiez votre annonce : BabiLogis vous suggère un loyer cohérent avec le marché du quartier.'),
              ],
            ),
            FilledButton(
              onPressed: () => aller(context, u?.estAnnonceur == true ? '/espace/annonces/nouvelle' : '/inscription?profil=agence'),
              child: const Text('Publier une annonce'),
            ),
          ],
        )),
      ),
    );
  }
}
