import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../config.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/composants.dart';
import '../widgets/site.dart';
import 'espace.dart';

/// Publier ou modifier une annonce, avec l'estimation du loyer juste en direct.
class PageFormulaire extends StatelessWidget {
  const PageFormulaire({super.key, this.reference});

  final String? reference; // null = nouvelle annonce

  Future<(List<Commune>, Referentiel, Annonce?)> _charger() async {
    final c = await Api.instance.get('/communes') as Map<String, dynamic>;
    final r = await Api.instance.get('/referentiel') as Map<String, dynamic>;
    Annonce? a;
    if (reference != null) {
      final j = await Api.instance.get('/espace/annonces/$reference') as Map<String, dynamic>;
      a = Annonce.fromJson(j['annonce'] as Map<String, dynamic>);
    }
    return (
      (c['data'] as List).map((e) => Commune.fromJson(e as Map<String, dynamic>)).toList(),
      Referentiel.fromJson(r),
      a,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GabaritEspace(
      actif: reference == null ? 'nouvelle' : 'tableau',
      child: Chargeur<(List<Commune>, Referentiel, Annonce?)>(
        key: ValueKey(reference),
        hauteur: 400,
        charger: _charger,
        builder: (context, d, _) => _Formulaire(communes: d.$1, referentiel: d.$2, annonce: d.$3),
      ),
    );
  }
}

class _Formulaire extends StatefulWidget {
  const _Formulaire({required this.communes, required this.referentiel, this.annonce});

  final List<Commune> communes;
  final Referentiel referentiel;
  final Annonce? annonce;

  @override
  State<_Formulaire> createState() => _FormulaireState();
}

class _FormulaireState extends State<_Formulaire> {
  late String _commune;
  int? _quartierId;
  String _type = 'Appartement';
  int _pieces = 3, _chambres = 2, _sdb = 1, _caution = 2, _avance = 2;
  bool _meuble = false;
  final Set<String> _equipements = {};
  final _loyer = TextEditingController();
  final _description = TextEditingController();

  Map<String, dynamic>? _estimation;
  bool _estimationEnCours = false;
  Timer? _minuterie;
  bool _envoi = false;
  Map<String, String> _erreurs = {};

  bool get _edition => widget.annonce != null;

  @override
  void initState() {
    super.initState();
    final a = widget.annonce;
    final noms = widget.communes.map((c) => c.nom).toList();
    _commune = a?.commune ?? (noms.contains('Cocody') ? 'Cocody' : (noms.isEmpty ? '' : noms.first));
    if (a != null) {
      _quartierId = a.quartierId;
      _type = a.type;
      _pieces = a.pieces;
      _chambres = a.chambres;
      _sdb = a.sallesBain < 1 ? 1 : a.sallesBain;
      _caution = a.cautionMois.clamp(0, 2).toInt();
      _avance = a.avanceMois.clamp(0, 2).toInt();
      _meuble = a.meuble;
      _equipements.addAll(a.equipements);
      _loyer.text = fcfa(a.loyer, unite: false);
      _description.text = a.description;
    }
    _quartierId ??= _quartiers.isEmpty ? null : _quartiers.first.id;
    _loyer.addListener(_planifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _estimer());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _loyer.dispose();
    _description.dispose();
    super.dispose();
  }

  List<Quartier> get _quartiers =>
      widget.communes.firstWhere((c) => c.nom == _commune, orElse: () => widget.communes.first).quartiers;

  void _changer(VoidCallback f) {
    setState(f);
    _planifier();
  }

  void _planifier() {
    _minuterie?.cancel();
    _minuterie = Timer(const Duration(milliseconds: 400), _estimer);
  }

  Future<void> _estimer() async {
    if (_commune.isEmpty) return;
    setState(() => _estimationEnCours = true);
    try {
      final q = _quartiers.where((q) => q.id == _quartierId);
      final r = await Api.instance.post('/estimation', {
        'commune': _commune,
        'quartier': q.isEmpty ? '' : q.first.nom,
        'type': _type,
        'pieces': _pieces,
        'meuble': _meuble,
        'equipements': _equipements.toList(),
        if (lireMontant(_loyer.text) != null && lireMontant(_loyer.text)! >= 1000) 'loyer': lireMontant(_loyer.text),
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _estimation = r);
    } catch (_) {
      if (mounted) setState(() => _estimation = null);
    } finally {
      if (mounted) setState(() => _estimationEnCours = false);
    }
  }

  Future<void> _enregistrer(String action) async {
    setState(() {
      _envoi = true;
      _erreurs = {};
    });
    final corps = {
      'quartier_id': _quartierId,
      'type': _type,
      'pieces': _pieces,
      'chambres': _chambres,
      'salles_bain': _sdb,
      'meuble': _meuble,
      'loyer': lireMontant(_loyer.text),
      'caution_mois': _caution,
      'avance_mois': _avance,
      'description': _description.text.trim(),
      'equipements': _equipements.toList(),
      'action': action,
    };
    try {
      final r = (_edition
          ? await Api.instance.put('/espace/annonces/${widget.annonce!.id}', corps)
          : await Api.instance.post('/espace/annonces', corps)) as Map<String, dynamic>;
      final a = Annonce.fromJson(r['annonce'] as Map<String, dynamic>);
      if (!mounted) return;
      message(
          context,
          a.statut == 'publiee'
              ? 'Annonce ${a.id} ${_edition ? 'enregistrée' : 'publiée'}. Analyse du prix : ${a.verdictLibelle}.'
              : 'Brouillon ${a.id} enregistré.');
      if (!_edition) {
        // Nouvelle annonce : on ouvre sa page de modification pour ajouter les photos.
        message(context, 'Annonce ${a.id} enregistrée. Ajoutez maintenant vos photos.');
        Navigator.of(context).pushReplacementNamed('/espace/annonces/${a.id}/modifier');
        return;
      }
      Navigator.of(context).pushReplacementNamed('/espace');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _erreurs = e.erreurs);
      message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Aperçu de l'annonce telle que les locataires la verront, avant publication.
  /// « Modifier » referme l'aperçu (la saisie est conservée), « Publier » enregistre.
  Future<void> _previsualiser() async {
    final q = _quartiers.where((q) => q.id == _quartierId);
    final loyer = lireMontant(_loyer.text);
    final choix = await showDialog<String>(
      context: context,
      builder: (_) => _Apercu(
        reference: widget.annonce?.id,
        photosInitiales: widget.annonce?.photos ?? const [],
        commune: _commune,
        quartier: q.isEmpty ? '' : q.first.nom,
        type: _type,
        pieces: _pieces,
        chambres: _chambres,
        sallesBain: _sdb,
        meuble: _meuble,
        equipements: _equipements.toList(),
        loyer: loyer,
        caution: _caution,
        avance: _avance,
        description: _description.text.trim(),
        estimation: _estimation,
        dejaPubliee: _edition && widget.annonce!.statut == 'publiee',
      ),
    );
    if (!mounted) return;
    if (choix == 'publier') await _enregistrer('publier');
    if (choix == 'brouillon') await _enregistrer('brouillon');
  }

  Widget _compteur(String libelle, int valeur, int min, int max, ValueChanged<int> onChanged) {
    return Champ(
      libelle,
      Container(
        height: 50,
        decoration: BoxDecoration(border: Border.all(color: Couleurs.bordureForte), borderRadius: BorderRadius.circular(10), color: Colors.white),
        child: Row(children: [
          IconButton(
              tooltip: 'Moins',
              onPressed: valeur > min ? () => _changer(() => onChanged(valeur - 1)) : null,
              icon: const Icon(Icons.remove)),
          Expanded(
            child: Semantics(
              label: '$libelle : $valeur',
              child: Text('$valeur', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ),
          IconButton(
              tooltip: 'Plus', onPressed: valeur < max ? () => _changer(() => onChanged(valeur + 1)) : null, icon: const Icon(Icons.add)),
        ]),
      ),
    );
  }

  Widget _bloc(String titre, List<Widget> enfants) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Carte(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 14),
            ...enfants,
          ]),
        ),
      );

  Widget _ligne(List<Widget> enfants) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 420) {
          return Column(children: [
            for (final e in enfants) Padding(padding: const EdgeInsets.only(bottom: 12), child: e),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < enfants.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: enfants[i])],
          ]),
        );
      });

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 1180;
    final formulaire = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bloc('Emplacement', [
          _ligne([
            Champ(
              'Commune',
              Liste<String>(
                valeur: _commune,
                options: [for (final c in widget.communes) (c.nom, c.nom)],
                onChanged: (v) => _changer(() {
                  _commune = v ?? _commune;
                  _quartierId = _quartiers.isEmpty ? null : _quartiers.first.id;
                }),
              ),
            ),
            Champ(
              'Quartier',
              Liste<int>(
                valeur: _quartierId,
                options: [for (final q in _quartiers) (q.id, q.nom)],
                onChanged: (v) => _changer(() => _quartierId = v),
              ),
            ),
          ]),
          if (_erreurs['quartier_id'] != null) Text(_erreurs['quartier_id']!, style: const TextStyle(color: Couleurs.danger)),
        ]),
        _bloc('Le logement', [
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.start, children: [
            for (final t in widget.referentiel.types.isEmpty ? const ['Studio', 'Appartement', 'Villa'] : widget.referentiel.types)
              Puce(t,
                  choisi: _type == t,
                  onTap: () => _changer(() {
                        _type = t;
                        if (t == 'Studio') _pieces = 1;
                      })),
          ]),
          const SizedBox(height: 14),
          _ligne([
            _compteur('Pièces', _pieces, 1, 20, (v) => _pieces = v),
            _compteur('Chambres', _chambres, 0, 20, (v) => _chambres = v),
            _compteur('Salles de bain', _sdb, 1, 10, (v) => _sdb = v),
          ]),
          const Text('Équipements', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.start, children: [
            Puce('Meublé', choisi: _meuble, onTap: () => _changer(() => _meuble = !_meuble)),
            for (final e in widget.referentiel.equipements)
              Puce(e,
                  choisi: _equipements.contains(e),
                  onTap: () => _changer(() => _equipements.contains(e) ? _equipements.remove(e) : _equipements.add(e))),
          ]),
        ]),
        _bloc('Conditions', [
          _ligne([
            Champ(
              'Loyer mensuel (FCFA)',
              TextField(
                controller: _loyer,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                decoration: deco(hint: 'Ex : 250 000', erreur: _erreurs['loyer']),
              ),
            ),
            _compteur('Caution (mois)', _caution, 0, 2, (v) => _caution = v),
            _compteur('Avance (mois)', _avance, 0, 2, (v) => _avance = v),
          ]),
          const Text('Loi n° 2018-575 : la caution et l\'avance sont limitées à 2 mois de loyer chacune.',
              style: TextStyle(color: Couleurs.texte2, fontSize: 14)),
          const SizedBox(height: 14),
          Champ(
            'Description',
            TextField(
              controller: _description,
              maxLines: 5,
              maxLength: 3000,
              decoration: deco(hint: 'Étage, luminosité, proximité des écoles et transports…', erreur: _erreurs['description']),
            ),
          ),
        ]),
        if (_edition)
          Padding(padding: const EdgeInsets.only(bottom: 16), child: GestionPhotos(annonce: widget.annonce!, type: _type))
        else
          _bloc('Photos', [
            const Text('Vous pourrez ajouter vos photos (ou choisir des photos d\'illustration) juste après '
                'l\'enregistrement de l\'annonce.', style: TextStyle(color: Couleurs.texte2)),
          ]),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _envoi ? null : _previsualiser,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Prévisualiser'),
          ),
          FilledButton(
            onPressed: _envoi ? null : () => _enregistrer('publier'),
            child: Text(_edition && widget.annonce!.statut == 'publiee' ? 'Enregistrer' : 'Publier l\'annonce'),
          ),
          OutlinedButton(onPressed: _envoi ? null : () => _enregistrer('brouillon'), child: const Text('Enregistrer en brouillon')),
          TextButton(onPressed: () => Navigator.of(context).pushReplacementNamed('/espace'), child: const Text('Annuler')),
        ]),
      ],
    );

    final estimation = _Estimation(donnees: _estimation, enCours: _estimationEnCours);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Titre(_edition ? 'Modifier l\'annonce ${widget.annonce!.id}' : 'Publier une annonce', taille: 28),
        const SizedBox(height: 6),
        const Text('Le loyer juste est estimé pendant la saisie, avant la publication.', style: TextStyle(color: Couleurs.texte2)),
        const SizedBox(height: 20),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: formulaire),
            const SizedBox(width: 20),
            SizedBox(width: 330, child: estimation),
          ])
        else ...[
          estimation,
          const SizedBox(height: 16),
          formulaire,
        ],
      ],
    );
  }
}

class _Estimation extends StatelessWidget {
  const _Estimation({required this.donnees, required this.enCours});

  final Map<String, dynamic>? donnees;
  final bool enCours;

  @override
  Widget build(BuildContext context) {
    final d = donnees;
    final verdict = d?['verdict'] as String?;
    final libelle = switch (verdict) {
      'juste' => 'Prix juste',
      'au_dessus' => 'Au-dessus du marché',
      'bonne_affaire' => 'Bonne affaire',
      _ => '',
    };
    final ecart = (d?['ecart_pourcent'] as num?)?.toInt() ?? 0;
    final conseil = switch (verdict) {
      'au_dessus' => 'Votre loyer est $ecart % au-dessus de l\'estimation centrale. Les annonces au prix juste reçoivent plus de visites.',
      'bonne_affaire' => 'Votre loyer est en dessous du marché : votre annonce sera mise en avant.',
      'juste' => 'Votre loyer est dans la fourchette du marché.',
      _ => 'Saisissez le loyer pour voir l\'analyse.',
    };
    return Semantics(
      liveRegion: true,
      child: Carte(
        alerte: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Estimation BabiLogis', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              if (enCours) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Couleurs.primary)),
            ]),
            const SizedBox(height: 12),
            if (d == null)
              Text(enCours ? 'Calcul en cours…' : 'Estimation indisponible pour le moment. Vous pouvez quand même publier.',
                  style: const TextStyle(color: Couleurs.texte2))
            else ...[
              const Text('Loyer juste estimé', style: TextStyle(color: Couleurs.texte2)),
              Text('${fcfa((d['estimation_min'] as num).toInt(), unite: false)} – ${fcfa((d['estimation_max'] as num).toInt())}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (verdict != null) VerdictBadge(verdict, libelle),
              const SizedBox(height: 10),
              Text(conseil),
              const SizedBox(height: 10),
              Text(
                '${d['source'] == 'modele' ? 'Modèle IA BabiLogis' : 'Loyers de référence'} · ${pluriel((d['nb_comparables'] as num?)?.toInt() ?? 0, 'annonce comparable', 'annonces comparables')}',
                style: const TextStyle(color: Couleurs.texte2, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Fenêtre d'aperçu : reprend la présentation de la fiche annonce du site.
class _Apercu extends StatelessWidget {
  const _Apercu({
    required this.reference,
    required this.photosInitiales,
    required this.commune,
    required this.quartier,
    required this.type,
    required this.pieces,
    required this.chambres,
    required this.sallesBain,
    required this.meuble,
    required this.equipements,
    required this.loyer,
    required this.caution,
    required this.avance,
    required this.description,
    required this.estimation,
    required this.dejaPubliee,
  });

  final String? reference;
  final List<PhotoAnnonce> photosInitiales;
  final String commune, quartier, type, description;
  final int pieces, chambres, sallesBain, caution, avance;
  final bool meuble, dejaPubliee;
  final List<String> equipements;
  final int? loyer;
  final Map<String, dynamic>? estimation;

  /// En modification, on relit les photos du serveur (elles ont pu changer depuis l'ouverture).
  Future<List<PhotoAnnonce>> _photos() async {
    if (reference == null) return photosInitiales;
    try {
      final j = await Api.instance.get('/espace/annonces/$reference') as Map<String, dynamic>;
      return Annonce.fromJson(j['annonce'] as Map<String, dynamic>).photos;
    } catch (_) {
      return photosInitiales;
    }
  }

  List<String> get _manques => [
        if (loyer == null || loyer! < 1000) 'le loyer',
        if (quartier.isEmpty) 'le quartier',
      ];

  @override
  Widget build(BuildContext context) {
    final verdict = estimation?['verdict'] as String?;
    final libelle = switch (verdict) {
      'juste' => 'Prix juste',
      'au_dessus' => 'Au-dessus du marché',
      'bonne_affaire' => 'Bonne affaire',
      _ => '',
    };
    final titre = type == 'Studio' ? 'Studio${meuble ? ' meublé' : ''}' : '$type $pieces pièces${meuble ? ' meublé' : ''}';
    final largeur = MediaQuery.sizeOf(context).width;
    final manques = _manques;

    Widget info(IconData icone, String texte) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 18, color: Couleurs.texte2),
          const SizedBox(width: 6),
          Text(texte),
        ]);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: largeur < 600 ? 12 : 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              color: Couleurs.primarySoft,
              child: Row(children: [
                const Icon(Icons.visibility_outlined, color: Couleurs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Aperçu : voici ce que verront les locataires',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Couleurs.primary)),
                ),
                IconButton(
                    tooltip: 'Fermer', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FutureBuilder<List<PhotoAnnonce>>(
                    future: _photos(),
                    builder: (context, snap) {
                      final photos = snap.data ?? photosInitiales;
                      if (photos.isEmpty) {
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Photo(null, hauteur: 220, rayon: 12),
                          const SizedBox(height: 6),
                          Text(
                              reference == null
                                  ? 'Les photos s\'ajoutent juste après l\'enregistrement. Sans photo, des photos d\'illustration sont affichées.'
                                  : 'Aucune photo : des photos d\'illustration seront affichées.',
                              style: const TextStyle(color: Couleurs.texte2, fontSize: 13)),
                        ]);
                      }
                      return SizedBox(
                        height: 220,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => SizedBox(
                            width: photos.length == 1 ? 700 : 320,
                            child: Photo(photos[i], hauteur: 220, rayon: 12),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(titre, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    if (verdict != null) VerdictBadge(verdict, libelle),
                  ]),
                  const SizedBox(height: 4),
                  Text(quartier.isEmpty ? commune : '$quartier, $commune', style: const TextStyle(color: Couleurs.texte2, fontSize: 16)),
                  const SizedBox(height: 12),
                  Text(loyer == null ? 'Loyer non renseigné' : '${fcfa(loyer)} / mois',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Couleurs.primary)),
                  if (loyer != null)
                    Text('Caution : $caution mois · Avance : $avance mois · À l\'entrée : ${fcfa(loyer! * (caution + avance))}',
                        style: const TextStyle(color: Couleurs.texte2)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 18, runSpacing: 8, children: [
                    info(Icons.home_outlined, type),
                    info(Icons.meeting_room_outlined, pluriel(pieces, 'pièce')),
                    info(Icons.bed_outlined, pluriel(chambres, 'chambre')),
                    info(Icons.bathtub_outlined, pluriel(sallesBain, 'salle de bain', 'salles de bain')),
                  ]),
                  if (meuble || equipements.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final e in [if (meuble) 'Meublé', ...equipements])
                        Chip(label: Text(e), visualDensity: VisualDensity.compact),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(description.isEmpty ? 'Aucune description pour le moment.' : description,
                      style: TextStyle(color: description.isEmpty ? Couleurs.texte2 : null, height: 1.45)),
                  if (estimation != null) ...[
                    const SizedBox(height: 16),
                    Text(
                        'Loyer juste estimé : ${fcfa((estimation!['estimation_min'] as num).toInt(), unite: false)} – '
                        '${fcfa((estimation!['estimation_max'] as num).toInt())}',
                        style: const TextStyle(color: Couleurs.texte2)),
                  ],
                  if (manques.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(10)),
                      child: Text('À compléter avant de publier : ${manques.join(', ')}.',
                          style: const TextStyle(color: Color(0xFF8A4B00))),
                    ),
                  ],
                ]),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
                if (!dejaPubliee)
                  TextButton(onPressed: () => Navigator.of(context).pop('brouillon'), child: const Text('Enregistrer en brouillon')),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop('publier'),
                  child: Text(dejaPubliee ? 'Enregistrer' : 'Publier l\'annonce'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photos de l'annonce : ajout de vraies photos, choix d'illustrations libres de droits, suppression.
class GestionPhotos extends StatefulWidget {
  const GestionPhotos({super.key, required this.annonce, required this.type});

  final Annonce annonce;
  final String type;

  @override
  State<GestionPhotos> createState() => _GestionPhotosState();
}

class _GestionPhotosState extends State<GestionPhotos> {
  late List<PhotoAnnonce> _photos = widget.annonce.photos;
  bool _envoi = false;

  List<PhotoAnnonce> get _choisies => _photos.where((p) => !p.automatique).toList();

  void _maj(dynamic r) {
    if (r is Map && r['photos'] != null) setState(() => _photos = PhotoAnnonce.liste(r['photos']));
  }

  Future<void> _ajouterFichiers() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (res == null || !mounted) return;
    setState(() => _envoi = true);
    var n = 0;
    try {
      for (final f in res.files) {
        final octets = f.bytes;
        if (octets == null) continue;
        if (octets.length > 5 * 1024 * 1024) {
          if (!mounted) return;
          message(context, '${f.name} dépasse 5 Mo : photo ignorée.', erreur: true);
          continue;
        }
        _maj(await Api.instance.post('/espace/annonces/${widget.annonce.id}/photos', {'nom': f.name, 'donnees': base64Encode(octets)}));
        n++;
      }
      if (mounted && n > 0) message(context, '$n photo${n > 1 ? 's' : ''} ajoutée${n > 1 ? 's' : ''}.');
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _choisirIllustration() async {
    final id = await showDialog<int>(context: context, builder: (_) => _Bibliotheque(type: widget.type));
    if (id == null || !mounted) return;
    setState(() => _envoi = true);
    try {
      _maj(await Api.instance.post('/espace/annonces/${widget.annonce.id}/photos', {'illustration_id': id}));
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _supprimer(PhotoAnnonce p) async {
    setState(() => _envoi = true);
    try {
      _maj(await Api.instance.delete('/espace/annonces/${widget.annonce.id}/photos/${p.id}'));
    } on ApiException catch (e) {
      if (mounted) message(context, e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choisies = _choisies;
    final automatiques = _photos.where((p) => p.automatique).toList();
    return Carte(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Photos', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        const Text('Ajoutez vos vraies photos (JPEG, PNG ou WebP, 5 Mo maximum, 8 photos), ou choisissez des photos '
            'd\'illustration libres de droits. Les illustrations sont signalées comme telles aux locataires.',
            style: TextStyle(color: Couleurs.texte2)),
        const SizedBox(height: 14),
        if (choisies.isEmpty && automatiques.isNotEmpty) ...[
          const Text('Aucune photo choisie : ces illustrations sont affichées automatiquement.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in (choisies.isEmpty ? automatiques : choisies))
            SizedBox(
              width: 150,
              child: Stack(children: [
                Photo(p, hauteur: 110, rayon: 10, mention: false),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Pastille(p.illustration ? 'Illustration' : 'Votre photo',
                      bg: p.illustration ? Colors.black54 : Couleurs.primary),
                ),
                if (p.id != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Retirer cette photo',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _envoi ? null : () => _supprimer(p),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: _envoi || choisies.length >= 8 ? null : _ajouterFichiers,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Ajouter mes photos'),
          ),
          OutlinedButton.icon(
            onPressed: _envoi || choisies.length >= 8 ? null : _choisirIllustration,
            icon: const Icon(Icons.collections_outlined, size: 18),
            label: const Text('Choisir une illustration'),
          ),
          if (_envoi) const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
      ]),
    );
  }
}

/// Bibliothèque d'illustrations libres de droits du type de logement.
class _Bibliotheque extends StatelessWidget {
  const _Bibliotheque({required this.type});

  final String type;

  Future<List<PhotoAnnonce>> _charger() async {
    final r = await Api.instance.get('/illustrations', {'type': type}) as Map<String, dynamic>;
    return PhotoAnnonce.liste(r['data']);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Illustrations · $type'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: FutureBuilder<List<PhotoAnnonce>>(
          future: _charger(),
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return Center(child: Text('${s.error}'));
            final photos = s.data ?? const [];
            if (photos.isEmpty) {
              return const Center(
                child: Text('Aucune illustration sur le serveur.\nLancez : python3 outils/collecter_images.py',
                    textAlign: TextAlign.center),
              );
            }
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.25),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final p = photos[i];
                return Tooltip(
                  message: p.credit ?? '',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(p.id),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(urlImage(p.url), fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const PhotoVide(hauteur: 120)),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler'))],
    );
  }
}
