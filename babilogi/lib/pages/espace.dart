import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';

/// Menu latéral de l'espace annonceur (et de l'administration).
class MenuEspace extends StatelessWidget {
  const MenuEspace({super.key, required this.actif});

  final String actif;

  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).utilisateur!;
    Widget lien(String t, String route, String cle, IconData icone) {
      final a = actif == cle;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: a ? Couleurs.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: ListTile(
            dense: true,
            selected: a,
            selectedColor: Couleurs.primary,
            leading: Icon(icone, size: 20),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: () => Navigator.of(context).pushReplacementNamed(route),
          ),
        ),
      );
    }

    return Carte(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: Couleurs.primary,
                child: Text(u.initiales, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.nom, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                  Text(u.estAdmin ? 'Administrateur' : (u.typeAnnonceur == 'agence' ? 'Agence' : 'Particulier'),
                      style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
                ]),
              ),
            ]),
          ),
          if (u.estAnnonceur) ...[
            lien('Tableau de bord', '/espace', 'tableau', Icons.dashboard_outlined),
            lien('Nouvelle annonce', '/espace/annonces/nouvelle', 'nouvelle', Icons.add_home_outlined),
          ],
          if (u.estAdmin) lien('Signalements', '/admin/signalements', 'admin', Icons.flag_outlined),
          lien('Baromètre des loyers', '/barometre', 'barometre', Icons.bar_chart),
        ],
      ),
    );
  }
}

/// Gabarit espace : menu à gauche (grand écran) ou en haut.
class GabaritEspace extends StatelessWidget {
  const GabaritEspace({super.key, required this.actif, required this.child});

  final String actif;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 1000;
    return SiteScaffold(
      actif: actif == 'admin' ? 'admin' : (actif == 'nouvelle' ? 'publier' : 'espace'),
      child: Contenu(
        maxWidth: 1320,
        vertical: 28,
        child: large
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 250, child: MenuEspace(actif: actif)),
                const SizedBox(width: 24),
                Expanded(child: child),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                MenuEspace(actif: actif),
                const SizedBox(height: 20),
                child,
              ]),
      ),
    );
  }
}

class _Donnees {
  _Donnees(Map<String, dynamic> j)
      : stats = Map<String, dynamic>.from(j['stats'] as Map),
        annonces = (j['annonces'] as List).map((e) => Annonce.fromJson(e as Map<String, dynamic>)).toList(),
        visites = (j['visites'] as List).map((e) => VisiteAnnonceur.fromJson(e as Map<String, dynamic>)).toList();

  final Map<String, dynamic> stats;
  final List<Annonce> annonces;
  final List<VisiteAnnonceur> visites;
}

class PageEspace extends StatefulWidget {
  const PageEspace({super.key});

  @override
  State<PageEspace> createState() => _PageEspaceState();
}

class _PageEspaceState extends State<PageEspace> {
  String? _statut;
  int _version = 0;

  void _recharger() => setState(() => _version++);

  Future<void> _supprimer(Annonce a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer ${a.id} ?'),
        content: Text('« ${a.titre} à ${a.quartier} » sera supprimée définitivement, avec ses demandes de visite.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await Api.instance.delete('/espace/annonces/${a.id}') as Map<String, dynamic>;
      if (mounted) message(context, '${r['message']}');
      _recharger();
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    }
  }

  Future<void> _repondre(VisiteAnnonceur v, String statut) async {
    try {
      final r = await Api.instance.patch('/espace/visites/${v.id}', {'statut': statut}) as Map<String, dynamic>;
      if (mounted) message(context, statut == 'confirmee' ? '${r['message']} ${v.nom} sera prévenu(e).' : '${r['message']}');
      _recharger();
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = SessionScope.of(context).utilisateur!;
    return GabaritEspace(
      actif: 'tableau',
      child: Chargeur<_Donnees>(
        key: ValueKey('$_statut-$_version'),
        hauteur: 400,
        charger: () async => _Donnees(await Api.instance.get('/espace', {'statut': _statut}) as Map<String, dynamic>),
        builder: (context, d, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Titre('Bonjour, ${u.nom}', taille: 28),
                  const Text('Voici l\'activité de vos annonces.', style: TextStyle(color: Couleurs.texte2)),
                ]),
                FilledButton.icon(
                  onPressed: () => aller(context, '/espace/annonces/nouvelle'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle annonce'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Grille(largeurMin: 200, max: 4, espace: 14, enfants: [
              Kpi('Annonces publiées', '${d.stats['publiees']}'),
              Kpi('Visites demandées (7 j)', '${d.stats['visites_7j']}'),
              Kpi('Vues des annonces', fcfa((d.stats['vues'] as num).toInt(), unite: false)),
              Kpi('Au-dessus du marché', '${d.stats['au_dessus']}',
                  alerte: (d.stats['au_dessus'] as num) > 0,
                  detail: (d.stats['au_dessus'] as num) > 0 ? 'Revoyez ces loyers' : 'Loyers cohérents'),
            ]),
            const SizedBox(height: 28),
            Row(children: [
              const Expanded(child: Titre('Mes annonces', taille: 22, niveau: 2)),
              SizedBox(
                width: 200,
                child: Liste<String>(
                  valeur: _statut,
                  libelleVide: 'Tous les statuts',
                  options: const [('publiee', 'Publiée'), ('brouillon', 'Brouillon'), ('masquee', 'Masquée')],
                  onChanged: (v) => setState(() => _statut = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (d.annonces.isEmpty)
              Carte(
                child: Vide(
                  icone: Icons.add_home_outlined,
                  titre: 'Aucune annonce',
                  texte: 'Publiez votre première annonce : le loyer juste est estimé pendant la saisie.',
                  action: FilledButton(onPressed: () => aller(context, '/espace/annonces/nouvelle'), child: const Text('Publier une annonce')),
                ),
              )
            else
              Carte(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < d.annonces.length; i++) ...[
                    if (i > 0) const Divider(),
                    _LigneAnnonce(
                      a: d.annonces[i],
                      onModifier: () => aller(context, '/espace/annonces/${d.annonces[i].id}/modifier'),
                      onSupprimer: () => _supprimer(d.annonces[i]),
                    ),
                  ],
                ]),
              ),
            const SizedBox(height: 32),
            const Titre('Demandes de visite', taille: 22, niveau: 2),
            const SizedBox(height: 12),
            if (d.visites.isEmpty)
              const Text('Aucune demande de visite pour le moment.', style: TextStyle(color: Couleurs.texte2))
            else
              for (final v in d.visites)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Carte(
                    padding: const EdgeInsets.all(18),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 10,
                      spacing: 16,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(v.annonceTitre, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${v.nom} · ${v.telephone} · ${v.dateLibelle} à ${v.heure} · via ${v.canalLibelle}',
                              style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
                        ]),
                        if (v.statut == 'en_attente')
                          Wrap(spacing: 8, children: [
                            FilledButton(onPressed: () => _repondre(v, 'confirmee'), child: const Text('Confirmer')),
                            OutlinedButton(onPressed: () => _repondre(v, 'refusee'), child: const Text('Refuser')),
                          ])
                        else
                          Pastille(v.statutLibelle,
                              fg: v.statut == 'confirmee' ? Couleurs.justeFg : Couleurs.texte,
                              bg: v.statut == 'confirmee' ? Couleurs.justeBg : Couleurs.surfaceMuted),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LigneAnnonce extends StatelessWidget {
  const _LigneAnnonce({required this.a, required this.onModifier, required this.onSupprimer});

  final Annonce a;
  final VoidCallback onModifier, onSupprimer;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 760;
    final infos = InkWell(
      onTap: () => aller(context, '/annonces/${a.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.titre, style: const TextStyle(fontWeight: FontWeight.w800, color: Couleurs.primary)),
        Text('${a.lieu} · ${a.id}', style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
      ]),
    );
    final badges = Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(fcfa(a.loyer), style: const TextStyle(fontWeight: FontWeight.w800)),
      VerdictBadge(a.verdict, a.verdictLibelle, petit: true),
      Pastille(a.statutLibelle, fg: Couleurs.texte, bg: Couleurs.surfaceMuted),
      Text(pluriel(a.nbVisites, 'visite'), style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
    ]);
    final actions = Wrap(spacing: 4, children: [
      OutlinedButton(onPressed: onModifier, child: const Text('Modifier')),
      TextButton(onPressed: onSupprimer, child: const Text('Supprimer')),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: large
          ? Row(children: [Expanded(flex: 3, child: infos), Expanded(flex: 4, child: badges), actions])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [infos, const SizedBox(height: 8), badges, actions]),
    );
  }
}
