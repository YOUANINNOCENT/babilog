import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';
import 'messages.dart';

/// Détail d'une annonce : photos, caractéristiques, analyse du prix, visite, signalement.
class PageAnnonce extends StatelessWidget {
  const PageAnnonce({super.key, required this.reference});

  final String reference;

  Future<(Annonce, List<Annonce>, List<String>)> _charger() async {
    final r = await Api.instance.get('/annonces/$reference') as Map<String, dynamic>;
    final a = Annonce.fromJson(r['data'] as Map<String, dynamic>);
    final voisins = await Api.instance.get('/annonces', {'commune': a.commune, 'pieces': a.pieces, 'per_page': 4}) as Map<String, dynamic>;
    final ref = await Api.instance.get('/referentiel') as Map<String, dynamic>;
    final similaires = Resultats.fromJson(voisins, Annonce.fromJson).elements.where((x) => x.id != a.id).take(3).toList();
    return (a, similaires, Referentiel.fromJson(ref).motifs);
  }

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      actif: 'rechercher',
      child: Contenu(
        vertical: 20,
        child: Chargeur<(Annonce, List<Annonce>, List<String>)>(
          key: ValueKey(reference),
          hauteur: 500,
          charger: _charger,
          builder: (context, d, _) => _Detail(a: d.$1, similaires: d.$2, motifs: d.$3),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.a, required this.similaires, required this.motifs});

  final Annonce a;
  final List<Annonce> similaires;
  final List<String> motifs;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 1000;
    final gauche = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Galerie(large: large, photos: a.photos),
        const SizedBox(height: 24),
        Carte(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Titre('Caractéristiques', taille: 22, niveau: 2),
              const SizedBox(height: 14),
              Wrap(spacing: 36, runSpacing: 14, children: [
                _Spec('Type', a.type),
                _Spec('Pièces', '${a.pieces}'),
                _Spec('Chambres', '${a.chambres}'),
                _Spec('Salles de bain', '${a.sallesBain}'),
                _Spec('Meublé', a.meuble ? 'Oui' : 'Non'),
                _Spec('Caution / avance', '${a.cautionMois} mois / ${a.avanceMois} mois'),
              ]),
              if (a.equipements.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Équipements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in a.equipements) Chip(label: Text(e), side: const BorderSide(color: Couleurs.bordureForte), backgroundColor: Colors.white),
                ]),
              ],
              if (a.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const SizedBox(height: 6),
                Text(a.description),
              ],
            ],
          ),
        ),
        if (similaires.isNotEmpty) ...[
          const SizedBox(height: 32),
          Titre('Logements comparables à ${a.commune}', taille: 22, niveau: 2),
          const SizedBox(height: 16),
          Grille(largeurMin: 230, max: 3, enfants: [for (final s in similaires) CarteAnnonce(s)]),
        ],
      ],
    );
    // Contacter l'annonceur et demander une visite : réservé aux visiteurs et aux locataires.
    // Un propriétaire ou une agence connecté(e) ne voit pas ces options.
    final u = SessionScope.of(context).utilisateur;
    final annonceur = u != null && u.estAnnonceur;
    final droite = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Analyse(a: a),
        const SizedBox(height: 16),
        if (!a.contactPossible)
          _AnnonceCollectee(a: a)
        else if (annonceur)
          const Carte(
            padding: EdgeInsets.all(16),
            child: Text('Vous êtes connecté avec un compte annonceur. Le contact et les demandes de visite '
                'sont réservés aux locataires.', style: TextStyle(color: Couleurs.texte2)),
          )
        else ...[
          _Contacter(a: a),
          const SizedBox(height: 16),
          _FormulaireVisite(a: a),
        ],
        const SizedBox(height: 16),
        const Carte(
          alerte: true,
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Conseil de sécurité', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Ne versez jamais d\'avance ni de frais de visite avant d\'avoir visité le logement.', style: TextStyle(fontSize: 15)),
          ]),
        ),
        const SizedBox(height: 16),
        _Signalement(a: a, motifs: motifs),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 6, children: [
          TextButton(onPressed: () => aller(context, '/'), child: const Text('Accueil')),
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('/')),
          TextButton(
              onPressed: () => aller(context, Uri(path: '/annonces', queryParameters: {'commune': a.commune}).toString()),
              child: Text(a.commune)),
          Padding(padding: const EdgeInsets.only(top: 12), child: Text('/  ${a.titre} à ${a.quartier}', style: const TextStyle(color: Couleurs.texte2))),
        ]),
        const SizedBox(height: 6),
        Titre('${a.titre} à ${a.quartier}', taille: large ? 34 : 27),
        const SizedBox(height: 6),
        Text('${a.lieu} · publiée par ${a.annonceur} · ${a.publiee.toLowerCase()} · réf. ${a.id}',
            style: const TextStyle(color: Couleurs.texte2)),
        const SizedBox(height: 20),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: gauche),
            const SizedBox(width: 26),
            SizedBox(width: 390, child: droite),
          ])
        else ...[
          gauche,
          const SizedBox(height: 24),
          droite,
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Galerie extends StatelessWidget {
  const _Galerie({required this.large, required this.photos});

  final bool large;
  final List<PhotoAnnonce> photos;

  PhotoAnnonce? _p(int i) => i < photos.length ? photos[i] : null;

  @override
  Widget build(BuildContext context) {
    final galerie = !large
        ? Photo(_p(0), hauteur: 240, rayon: 16, taille: 56)
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 380,
              child: Row(children: [
                Expanded(flex: 2, child: Photo(_p(0), hauteur: 380, taille: 60)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(children: [
                    Expanded(child: Photo(_p(1), hauteur: double.infinity, mention: false)),
                    const SizedBox(height: 8),
                    Expanded(child: Photo(_p(2), hauteur: double.infinity, mention: false)),
                  ]),
                ),
              ]),
            ),
          );
    final credits = {for (final p in photos.where((p) => p.illustration && p.credit != null)) p.credit!};
    if (credits.isEmpty) return galerie;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      galerie,
      const SizedBox(height: 8),
      Text(
        'Photos d\'illustration libres de droits : elles ne représentent pas ce logement. '
        'Crédits : ${credits.join(' ; ')}.',
        style: const TextStyle(color: Couleurs.texte2, fontSize: 12.5),
      ),
    ]);
  }
}

class _Spec extends StatelessWidget {
  const _Spec(this.cle, this.valeur);

  final String cle, valeur;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cle, style: const TextStyle(color: Couleurs.texte2, fontSize: 14)),
          Text(valeur, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Analyse extends StatelessWidget {
  const _Analyse({required this.a});

  final Annonce a;

  @override
  Widget build(BuildContext context) {
    final c = a.estimationCentrale;
    final ecart = c == null || c == 0 ? 0 : ((a.loyer - c) / c * 100).round();
    final phrase = switch (a.verdict) {
      'juste' => 'Le prix demandé est dans la fourchette du marché.',
      'bonne_affaire' => 'Le prix demandé est inférieur au marché : vérifiez bien le logement lors de la visite.',
      'au_dessus' => 'Le prix demandé est supérieur au marché (${ecart > 0 ? '+' : ''}$ecart % par rapport à l\'estimation centrale). Vous pouvez négocier.',
      _ => 'L\'estimation de ce logement est en cours.',
    };
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loyer demandé', style: TextStyle(color: Couleurs.texte2)),
          Prix(a.loyer, taille: 30),
          const Divider(height: 32),
          Row(children: [
            const Expanded(child: Text('Analyse BabiLogis', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            VerdictBadge(a.verdict, a.verdictLibelle),
          ]),
          if (a.estMin != null && a.estMax != null) ...[
            const SizedBox(height: 18),
            JaugePrix(loyer: a.loyer, minimum: a.estMin!, maximum: a.estMax!),
            const SizedBox(height: 12),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Loyer estimé pour ce logement : '),
              TextSpan(text: fcfa(a.estMin), style: const TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' à '),
              TextSpan(text: fcfa(a.estMax), style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: '. $phrase'),
            ])),
            const SizedBox(height: 8),
            Text(
              '${a.sourceEstimation == 'modele' ? 'Estimé par le modèle BabiLogis' : 'Estimé à partir des loyers de référence'} : même commune, même nombre de pièces, équipements proches.',
              style: const TextStyle(color: Couleurs.texte2, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormulaireVisite extends StatefulWidget {
  const _FormulaireVisite({required this.a});

  final Annonce a;

  @override
  State<_FormulaireVisite> createState() => _FormulaireVisiteState();
}

class _FormulaireVisiteState extends State<_FormulaireVisite> {
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  late DateTime _date = _prochainSamedi();
  String _heure = '10 h';
  bool _envoi = false;
  Map<String, String> _erreurs = {};
  bool _envoyee = false;

  static DateTime _prochainSamedi() {
    final n = DateTime.now();
    final j = n.add(Duration(days: (DateTime.saturday - n.weekday) % 7 == 0 ? 7 : (DateTime.saturday - n.weekday) % 7));
    return DateTime(j.year, j.month, j.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = SessionScope.read(context).utilisateur;
    if (u != null && _nom.text.isEmpty) {
      _nom.text = u.nom;
      _tel.text = u.telephone;
    }
  }

  @override
  void dispose() {
    _nom.dispose();
    _tel.dispose();
    super.dispose();
  }

  static const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

  String get _dateTexte => '${_jours[_date.weekday - 1]} ${_date.day} ${_mois[_date.month - 1]}';

  Future<void> _choisirDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      helpText: 'Date de la visite',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _envoyer() async {
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    try {
      final d = _date;
      await Api.instance.post('/visites', {
        'annonce': widget.a.id,
        'nom': _nom.text.trim(),
        'telephone': _tel.text.trim(),
        'date_visite': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        'heure': _heure,
        'canal': 'web',
      });
      if (!mounted) return;
      setState(() => _envoyee = true);
      message(context, 'Demande de visite envoyée. L\'annonceur vous répondra par téléphone ou SMS.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _erreurs = e.erreurs);
      if (e.erreurs.isEmpty) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_envoyee) {
      return Carte(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle, color: Couleurs.justeFg),
            SizedBox(width: 8),
            Text('Demande envoyée', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
          const SizedBox(height: 8),
          Text('Visite demandée pour $_dateTexte à $_heure. L\'annonceur vous contactera au ${_tel.text}.'),
        ]),
      );
    }
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Demander une visite', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 14),
          Champ('Votre nom', TextField(controller: _nom, autofillHints: const [AutofillHints.name], decoration: deco(erreur: _erreurs['nom']))),
          const SizedBox(height: 12),
          Champ(
              'Téléphone',
              TextField(
                  controller: _tel,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: deco(hint: '07 01 02 03 04', erreur: _erreurs['telephone']))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Champ(
                'Date',
                OutlinedButton.icon(
                  onPressed: _choisirDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_dateTexte, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Champ(
                'Heure',
                Liste<String>(
                  valeur: _heure,
                  options: const [('9 h', '9 h'), ('10 h', '10 h'), ('11 h', '11 h'), ('14 h', '14 h'), ('15 h', '15 h'), ('16 h', '16 h'), ('17 h', '17 h')],
                  onChanged: (v) => setState(() => _heure = v ?? _heure),
                ),
              ),
            ),
          ]),
          if (_erreurs['date_visite'] != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_erreurs['date_visite']!, style: const TextStyle(color: Couleurs.danger))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _envoi ? null : _envoyer,
            child: _envoi
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
  }
}

class _Signalement extends StatefulWidget {
  const _Signalement({required this.a, required this.motifs});

  final Annonce a;
  final List<String> motifs;

  @override
  State<_Signalement> createState() => _SignalementState();
}

class _SignalementState extends State<_Signalement> {
  String? _motif;
  final _details = TextEditingController();
  bool _envoi = false;
  bool _fait = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (_motif == null) {
      message(context, 'Choisissez un motif.', erreur: true);
      return;
    }
    setState(() => _envoi = true);
    try {
      await Api.instance.post('/signalements', {'annonce': widget.a.id, 'motif': _motif, 'details': _details.text.trim()});
      if (!mounted) return;
      setState(() => _fait = true);
      message(context, 'Merci. Notre équipe va vérifier cette annonce.');
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fait) {
      return const Carte(child: Text('Signalement envoyé. Merci pour votre vigilance.', style: TextStyle(fontWeight: FontWeight.w600)));
    }
    return Carte(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Signaler cette annonce', style: TextStyle(fontWeight: FontWeight.w700, color: Couleurs.primary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final m in widget.motifs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(_motif == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: _motif == m ? Couleurs.primary : Couleurs.bordureForte),
                title: Text(m),
                selected: _motif == m,
                onTap: () => setState(() => _motif = m),
              ),
            const SizedBox(height: 8),
            TextField(controller: _details, maxLines: 3, maxLength: 1000, decoration: deco(hint: 'Précisions (facultatif)')),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _envoi ? null : _envoyer,
                style: OutlinedButton.styleFrom(foregroundColor: Couleurs.danger, side: const BorderSide(color: Couleurs.danger)),
                child: const Text('Envoyer le signalement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Annonce collectée sur le web : son annonceur n'a pas de compte BabiLogis,
/// le locataire est renvoyé vers l'annonce d'origine pour le contacter.
class _AnnonceCollectee extends StatelessWidget {
  const _AnnonceCollectee({required this.a});

  final Annonce a;

  @override
  Widget build(BuildContext context) {
    final lien = a.lienOrigine;
    final site = lien == null ? null : Uri.tryParse(lien)?.host.replaceFirst('www.', '');
    return Carte(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Contacter l\'annonceur', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        Text(
            'Cette annonce a été collectée sur ${site ?? 'le web'} pour l\'analyse des prix : son annonceur n\'est pas '
            'inscrit sur BabiLogis. La messagerie et les demandes de visite sont disponibles sur les annonces publiées '
            'par les propriétaires et agences inscrits.',
            style: const TextStyle(color: Couleurs.texte2)),
        if (lien != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(lien), webOnlyWindowName: '_blank'),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('Voir l\'annonce d\'origine${site == null ? '' : ' ($site)'}'),
          ),
        ],
      ]),
    );
  }
}

/// Échange direct avec le propriétaire ou l'agence (messagerie BabiLogis).
class _Contacter extends StatelessWidget {
  const _Contacter({required this.a});

  final Annonce a;

  Future<void> _ecrire(BuildContext context) async {
    final session = SessionScope.read(context);
    if (!session.connecte) {
      message(context, 'Connectez-vous pour écrire à l\'annonceur.');
      aller(context, '/connexion?suite=/annonces/${a.id}');
      return;
    }
    final champ = TextEditingController(
        text: 'Bonjour, votre annonce ${a.id} (${a.titre} à ${a.quartier}) m\'intéresse. Est-elle toujours disponible ?');
    final texte = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Écrire à ${a.annonceur.isEmpty ? 'l\'annonceur' : a.annonceur}'),
        content: SizedBox(
          width: 480,
          child: TextField(controller: champ, maxLines: 5, maxLength: 2000, autofocus: true, decoration: deco(hint: 'Votre message')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(champ.text.trim()), child: const Text('Envoyer')),
        ],
      ),
    );
    if (texte == null || texte.isEmpty || !context.mounted) return;
    await contacterAnnonceur(context, a.id, texte);
  }

  @override
  Widget build(BuildContext context) {
    return Carte(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Une question ?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        Text('Échangez directement avec ${a.annonceur.isEmpty || a.annonceur == 'Particulier' ? 'le propriétaire' : a.annonceur} '
            'dans la messagerie BabiLogis.', style: const TextStyle(color: Couleurs.texte2)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _ecrire(context),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('Contacter l\'annonceur'),
        ),
      ]),
    );
  }
}
