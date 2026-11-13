import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';
import 'espace.dart';

/// Back-office : signalements à traiter. La décision reste humaine.
class PageAdmin extends StatefulWidget {
  const PageAdmin({super.key, this.vue = 'a_traiter'});

  final String vue;

  @override
  State<PageAdmin> createState() => _PageAdminState();
}

class _PageAdminState extends State<PageAdmin> {
  int _version = 0;

  Future<void> _action(Future<dynamic> Function() appel) async {
    try {
      final r = await appel() as Map<String, dynamic>;
      if (mounted) message(context, '${r['message']}');
      setState(() => _version++);
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const vues = [('a_traiter', 'À traiter'), ('ia', 'Repérés par l\'IA'), ('traites', 'Traités'), ('tous', 'Tous')];
    return GabaritEspace(
      actif: 'admin',
      child: Chargeur<Map<String, dynamic>>(
        key: ValueKey('${widget.vue}-$_version'),
        hauteur: 400,
        charger: () async => await Api.instance.get('/admin/signalements', {'vue': widget.vue}) as Map<String, dynamic>,
        builder: (context, d, _) {
          final c = Map<String, dynamic>.from(d['compteurs'] as Map);
          final liste = (d['signalements'] as List).map((e) => SignalementAdmin.fromJson(e as Map<String, dynamic>)).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Titre('Signalements', taille: 28),
              const Text('Annonces signalées par les utilisateurs ou repérées par le modèle d\'anomalies.',
                  style: TextStyle(color: Couleurs.texte2)),
              const SizedBox(height: 20),
              Grille(largeurMin: 200, max: 4, espace: 14, enfants: [
                Kpi('À traiter', '${c['a_traiter']}', alerte: true),
                Kpi('Repérés par l\'IA', '${c['ia']}'),
                Kpi('Annonces masquées (30 j)', '${c['masquees']}'),
                Kpi('Annonces en ligne', '${c['annonces']}', detail: '${c['utilisateurs']} utilisateurs inscrits'),
              ]),
              const SizedBox(height: 22),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (v, l) in vues)
                  Puce(l,
                      choisi: widget.vue == v,
                      onTap: () => Navigator.of(context).pushReplacementNamed('/admin/signalements${v == 'a_traiter' ? '' : '?vue=$v'}')),
              ]),
              const SizedBox(height: 16),
              if (liste.isEmpty)
                const Carte(child: Vide(icone: Icons.check, titre: 'Rien à traiter', texte: 'Tous les signalements ont été traités.'))
              else
                for (final s in liste)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Carte(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              InkWell(
                                onTap: () => aller(context, '/annonces/${s.annonceId}'),
                                child: Text(s.annonceTitre,
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Couleurs.primary, decoration: TextDecoration.underline)),
                              ),
                              const SizedBox(height: 4),
                              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text('${fcfa(s.annonceLoyer)} / mois · ${s.annonceId}', style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
                                VerdictBadge(s.annonceVerdict, s.annonceVerdictLibelle, petit: true),
                              ]),
                              const SizedBox(height: 10),
                              Text(s.motif, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (s.details != null && s.details!.isNotEmpty)
                                Text(s.details!, style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 12, children: [
                                Text(s.source == 'modele' ? 'Modèle d\'anomalies' : 'Utilisateur', style: const TextStyle(fontSize: 14)),
                                if (s.risque != null)
                                  Text('Risque IA : ${_risque(s.risque!)}',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _couleurRisque(s.risque!))),
                                Text(s.date, style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
                              ]),
                            ]),
                          ),
                          if (s.statut == 'a_traiter')
                            Wrap(spacing: 8, children: [
                              FilledButton(
                                  onPressed: () => _action(() => Api.instance.patch('/admin/signalements/${s.id}', {'decision': 'masquer'})),
                                  child: const Text('Masquer l\'annonce')),
                              OutlinedButton(
                                  onPressed: () => _action(() => Api.instance.patch('/admin/signalements/${s.id}', {'decision': 'rejeter'})),
                                  child: const Text('Rejeter')),
                            ])
                          else
                            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Pastille(s.statut == 'rejete' ? 'Rejeté' : 'Annonce masquée', fg: Couleurs.texte, bg: Couleurs.surfaceMuted),
                              if (s.annonceStatut == 'masquee')
                                TextButton(
                                    onPressed: () => _action(() => Api.instance.patch('/admin/annonces/${s.annonceId}/republier', {})),
                                    child: const Text('Remettre en ligne')),
                            ]),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              const Text('Le risque IA est une aide à la décision : la décision finale revient toujours à l\'administrateur.',
                  style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
            ],
          );
        },
      ),
    );
  }

  static String _risque(String r) => switch (r) { 'eleve' => 'élevé', 'moyen' => 'moyen', _ => 'faible' };

  static Color _couleurRisque(String r) => switch (r) { 'eleve' => Couleurs.danger, 'moyen' => Couleurs.hautFg, _ => Couleurs.texte2 };
}
