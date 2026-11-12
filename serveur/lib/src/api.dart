/// API BabiLogis (mêmes adresses et même format JSON que l'ancienne API Laravel) :
/// utilisée par le site web Dart, l'app mobile et l'app desktop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'base.dart';
import 'courriel.dart';
import 'donnees_demo.dart' as demo;
import 'francais.dart';
import 'prix.dart';
import 'securite.dart';
import 'securite_http.dart' show tailleMaxRequete;

const budgetPlafond = 700000;

/// Erreur renvoyée au client (code HTTP + message + erreurs par champ).
class ErreurApi implements Exception {
  ErreurApi(this.statut, this.message, [this.erreurs = const {}]);

  ErreurApi.validation(Map<String, String> e) : this(422, e.values.first, e);

  final int statut;
  final String message;
  final Map<String, String> erreurs;
}

Response reponseJson(Object? corps, {int statut = 200}) => Response(
      statut,
      body: jsonEncode(corps),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class Api {
  Api(this.base, {DateTime Function()? horloge, EnvoiCourriel? courriel})
      : _horloge = horloge ?? DateTime.now,
        _courriel = courriel ?? courrielDepuisEnvironnement();

  final Base base;
  final DateTime Function() _horloge;
  final EnvoiCourriel _courriel;

  static const dureeCode = Duration(minutes: 10);
  static const delaiRenvoi = Duration(minutes: 1);
  static const essaisMaxCode = 5;

  DateTime get maintenant => _horloge();

  Router get routeur {
    final r = Router(notFoundHandler: (_) => reponseJson({'message': 'Adresse inconnue.'}, statut: 404));
    r.get('/api/sante', (Request _) => reponseJson({
          'statut': 'ok',
          'service': 'BabiLogis API (Dart)',
          // Commit déployé (fourni à la compilation) : le déploiement vérifie que la nouvelle version répond.
          'version': const String.fromEnvironment('VERSION', defaultValue: 'dev'),
          'donnees': base.nbAnnoncesReelles > 0 ? 'reelles' : 'demonstration',
          'nb_annonces': base.valeur("SELECT COUNT(*) FROM annonces WHERE statut = 'publiee'"),
          'heure': maintenant.toIso8601String(),
        }));

    // Public
    r.get('/api/annonces', _protege(_annonces));
    r.get('/api/annonces/<ref>', (Request q, String ref) => _protege((q) => _annonce(q, ref))(q));
    r.get('/api/communes', _protege(_communes));
    r.get('/api/referentiel', _protege(_referentiel));
    r.get('/api/marche', _protege(_marche));
    r.post('/api/estimation', _protege(_estimation));
    r.post('/api/visites', _protege(_visite));
    r.post('/api/signalements', _protege(_signalement));
    r.post('/api/assistant', _protege(_assistant));

    // Comptes
    r.post('/api/connexion', _protege(_connexion));
    r.post('/api/inscription', _protege(_inscription));
    r.post('/api/verification', _protege(_verification));
    r.post('/api/verification/renvoyer', _protege(_renvoyerCode));
    r.post('/api/mot-de-passe/oublie', _protege(_motDePasseOublie));
    r.post('/api/mot-de-passe/reinitialiser', _protege(_reinitialiserMotDePasse));
    r.get('/api/moi', _protege((q) => {'utilisateur': _profil(_exiger(q))}));
    r.delete('/api/moi', _protege(_supprimerCompte));
    r.post('/api/deconnexion', _protege(_deconnexion));

    // Espace annonceur
    r.get('/api/espace', _protege(_espace));
    r.post('/api/espace/annonces', _protege((q) => _enregistrer(q, null)));
    r.get('/api/espace/annonces/<ref>', (Request q, String ref) => _protege((q) => _afficherPourAnnonceur(q, ref))(q));
    r.put('/api/espace/annonces/<ref>', (Request q, String ref) => _protege((q) => _enregistrer(q, ref))(q));
    r.delete('/api/espace/annonces/<ref>', (Request q, String ref) => _protege((q) => _supprimer(q, ref))(q));
    r.post('/api/espace/annonces/<ref>/photos', (Request q, String ref) => _protege((q) => _ajouterPhoto(q, ref))(q));
    r.delete('/api/espace/annonces/<ref>/photos/<id>',
        (Request q, String ref, String id) => _protege((q) => _supprimerPhoto(q, ref, int.tryParse(id) ?? 0))(q));
    r.get('/api/illustrations', _protege(_illustrations));
    // Messagerie et notifications
    r.post('/api/conversations', _protege(_ouvrirConversation));
    r.get('/api/conversations', _protege(_conversations));
    r.get('/api/conversations/<id>/messages',
        (Request q, String id) => _protege((q) => _messages(q, int.tryParse(id) ?? 0))(q));
    r.post('/api/conversations/<id>/messages',
        (Request q, String id) => _protege((q) => _envoyerMessage(q, int.tryParse(id) ?? 0))(q));
    r.get('/api/notifications', _protege(_notifications));
    r.post('/api/notifications/lues', _protege(_notificationsLues));
    r.patch('/api/espace/visites/<id>', (Request q, String id) => _protege((q) => _repondreVisite(q, int.tryParse(id) ?? 0))(q));

    // Administration
    r.get('/api/admin/signalements', _protege(_signalementsAdmin));
    r.patch('/api/admin/signalements/<id>', (Request q, String id) => _protege((q) => _decider(q, int.tryParse(id) ?? 0))(q));
    r.patch('/api/admin/annonces/<ref>/republier', (Request q, String ref) => _protege((q) => _republier(q, ref))(q));
    return r;
  }

  /// Transforme le résultat (Map, Response) ou l'erreur en réponse HTTP.
  Handler _protege(FutureOr<Object?> Function(Request) f) => (Request q) async {
        try {
          final r = await f(q);
          if (r is Response) return r;
          return reponseJson(r);
        } on ErreurApi catch (e) {
          return reponseJson({
            'message': e.message,
            if (e.erreurs.isNotEmpty) 'errors': {for (final k in e.erreurs.keys) k: [e.erreurs[k]]},
          }, statut: e.statut);
        } on FormatException {
          return reponseJson({'message': 'Requête invalide (JSON attendu).'}, statut: 400);
        } catch (e, pile) {
          stderr.writeln('Erreur : $e\n$pile');
          return reponseJson({'message': 'Erreur interne du serveur.'}, statut: 500);
        }
      };

  // ── Outils ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _corps(Request q) async {
    // Lecture bornée : une requête sans Content-Length ne peut pas dépasser la limite.
    final octets = <int>[];
    await for (final morceau in q.read()) {
      octets.addAll(morceau);
      if (octets.length > tailleMaxRequete) throw ErreurApi(413, 'Requête trop volumineuse (8 Mo maximum).');
    }
    final t = utf8.decode(octets, allowMalformed: true);
    if (t.trim().isEmpty) return {};
    final d = jsonDecode(t);
    if (d is! Map<String, dynamic>) throw const FormatException();
    return d;
  }

  Map<String, Object?>? _utilisateur(Request q) {
    final h = q.headers['authorization'] ?? '';
    if (!h.toLowerCase().startsWith('bearer ')) return null;
    final u = base.ligne('SELECT * FROM utilisateurs WHERE jeton = ?', [empreinteJeton(h.substring(7).trim())]);
    if (u == null) return null;
    // Session expirée (30 jours) : il faut se reconnecter.
    final expire = DateTime.tryParse('${u['jeton_expire_le'] ?? ''}');
    if (expire != null && expire.isBefore(maintenant)) return null;
    return u;
  }

  /// Durée de vie d'une session (jeton) : au-delà, reconnexion obligatoire.
  static const dureeSession = Duration(days: 30);

  /// Échecs de connexion par compte (en mémoire) : blocage temporaire après 8 échecs en 15 minutes.
  final Map<String, List<DateTime>> _echecs = {};

  void _verifierBlocage(String email) {
    final liste = _echecs[email];
    if (liste == null) return;
    liste.removeWhere((d) => maintenant.difference(d) > const Duration(minutes: 15));
    if (liste.length >= 8) {
      throw ErreurApi(429, 'Trop de tentatives de connexion pour ce compte. Réessayez dans 15 minutes '
          'ou utilisez « Mot de passe oublié ».');
    }
  }

  Map<String, Object?> _exiger(Request q, {String? role}) {
    final u = _utilisateur(q);
    if (u == null) throw ErreurApi(401, 'Connectez-vous pour continuer.');
    final r = u['role'];
    final ok = switch (role) {
      null => true,
      'annonceur' => r == 'annonceur' || r == 'admin',
      'admin' => r == 'admin',
      _ => false,
    };
    if (!ok) throw ErreurApi(403, 'Accès réservé.');
    return u;
  }

  static int? _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));

  static String _texte(Object? v) => v == null ? '' : '$v'.trim();

  /// Coupe un texte trop long (champs libres).
  static String _borne(String s, int max) => s.length <= max ? s : s.substring(0, max);

  /// Empreinte d'un mot de passe aléatoire : sert quand le compte n'existe pas (temps constant).
  static final _empreinteFactice = hacherMotDePasse(nouveauJeton());

  static bool _vrai(Object? v) => v == true || v == 1 || v == '1' || v == 'true' || v == 'on';

  Map<String, Object?> _profil(Map<String, Object?> u) {
    final nom = '${u['nom']}';
    final initiales = nom.split(' ').where((m) => m.isNotEmpty).take(2).map((m) => m[0].toUpperCase()).join();
    return {
      'id': u['id'],
      'nom': nom,
      'email': u['email'],
      'telephone': u['telephone'],
      'role': u['role'],
      'type_annonceur': u['type_annonceur'],
      'initiales': initiales,
      'est_annonceur': u['role'] == 'annonceur' || u['role'] == 'admin',
      'est_admin': u['role'] == 'admin',
      'email_verifie': u['email_verifie_le'] != null,
    };
  }

  // ── Annonces ────────────────────────────────────────────────────────────
  static const _selectAnnonce = '''
    SELECT a.*, q.nom AS quartier, c.nom AS commune, u.nom AS annonceur_nom, u.type_annonceur, u.email AS annonceur_email,
      (SELECT GROUP_CONCAT(e.nom, '|') FROM annonce_equipement ae JOIN equipements e ON e.id = ae.equipement_id WHERE ae.annonce_id = a.id) AS equipements_liste,
      (SELECT COUNT(*) FROM visites v WHERE v.annonce_id = a.id) AS visites_count
    FROM annonces a
    JOIN quartiers q ON q.id = a.quartier_id
    JOIN communes c ON c.id = q.commune_id
    JOIN utilisateurs u ON u.id = a.utilisateur_id
  ''';

  static String titre(String type, int pieces, bool meuble) =>
      type == 'Studio' ? (meuble ? 'Studio meublé' : 'Studio') : '$type $pieces pièces';

  /// Format JSON d'une annonce : celui que lisent le site, l'app mobile et l'app desktop.
  Map<String, Object?> annonceJson(Map<String, Object?> a, {bool prive = false}) {
    final meuble = a['meuble'] == 1;
    final type = '${a['type']}';
    final pieces = a['pieces'] as int;
    final loyer = a['loyer'] as int;
    final mn = a['estimation_min'] as int?;
    final mx = a['estimation_max'] as int?;
    final v = verdict(loyer, mn, mx);
    final publiee = a['publiee_le'] == null ? null : DateTime.tryParse('${a['publiee_le']}');
    final equip = '${a['equipements_liste'] ?? ''}'.split('|').where((e) => e.isNotEmpty).toList()..sort();
    return {
      'id': a['reference'],
      'type': type,
      'commune': a['commune'],
      'quartier': a['quartier'],
      'pieces': pieces,
      'chambres': a['chambres'],
      'salles_bain': a['salles_bain'],
      'meuble': meuble,
      'loyer': loyer,
      'estimation_min': mn,
      'estimation_max': mx,
      'equipements': equip,
      'annonceur': a['type_annonceur'] == 'agence' ? a['annonceur_nom'] : 'Particulier',
      'description': Base.sansMentionCollecte('${a['description'] ?? ''}'),
      'caution_mois': a['caution_mois'],
      'avance_mois': a['avance_mois'],
      'age_jours': publiee == null ? 0 : joursEntre(publiee, maintenant).clamp(0, 100000),
      'titre': titre(type, pieces, meuble),
      'verdict': v,
      'verdict_libelle': verdictLibelle(v),
      'source_estimation': a['source_estimation'],
      'statut': a['statut'],
      'publiee_le': a['publiee_le'],
      'url': '/annonces/${a['reference']}',
      // Messages et visites : seulement si l'annonce a été publiée par un vrai compte
      // (propriétaire ou agence). Les annonces collectées renvoient vers leur page d'origine.
      'contact_possible': a['annonceur_email'] != Base.compteCollecte,
      'lien_origine': a['lien_origine'],
      'photos': photosAnnonce(a['id'] as int, type, '${a['reference']}'),
      if (prive) ...{
        'quartier_id': a['quartier_id'],
        'vues': a['vues'],
        'visites_count': a['visites_count'],
      },
    };
  }

  // ── Photos ──────────────────────────────────────────────────────────────
  static const maxPhotos = 8;
  static const tailleMaxPhoto = 5 * 1024 * 1024;

  Map<String, Object?> photoJson(Map<String, Object?> p, {bool automatique = false}) {
    final illustration = p['source'] == 'illustration';
    return {
      'id': automatique ? null : p['id'],
      'url': '/images/${p['fichier']}',
      'illustration': illustration,
      'automatique': automatique,
      if (illustration) 'credit': '${p['auteur'] ?? 'Auteur inconnu'} · ${p['licence'] ?? ''}'.trim(),
      if (illustration) 'lien_source': p['lien_source'],
    };
  }

  /// Photos de l'annonce ; à défaut, 3 illustrations du même type de logement
  /// (toujours les mêmes pour une annonce donnée), signalées comme « illustration ».
  List<Map<String, Object?>> photosAnnonce(int annonceId, String type, String reference) {
    final propres = base.lignes('SELECT * FROM photos WHERE annonce_id = ? ORDER BY ordre, id', [annonceId]);
    if (propres.isNotEmpty) return [for (final p in propres) photoJson(p)];
    var biblio = base.lignes('SELECT * FROM photos WHERE annonce_id IS NULL AND categorie = ? ORDER BY id',
        [Base.categoriePhoto(type)]);
    // Peu de photos de studios à Abidjan sous licence libre : on se replie sur celles des appartements.
    if (biblio.isEmpty && type == 'Studio') {
      biblio = base.lignes("SELECT * FROM photos WHERE annonce_id IS NULL AND categorie = 'appartement' ORDER BY id");
    }
    if (biblio.isEmpty) return const [];
    final depart = reference.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff) % biblio.length;
    final n = biblio.length < 3 ? biblio.length : 3;
    // Indices consécutifs : jamais deux fois la même photo dans une annonce.
    return [for (var i = 0; i < n; i++) photoJson(biblio[(depart + i) % biblio.length], automatique: true)];
  }

  /// Bibliothèque d'illustrations libres de droits (pour que l'annonceur en choisisse).
  Object _illustrations(Request q) {
    final type = _texte(q.url.queryParameters['type']);
    final lignes = type.isEmpty
        ? base.lignes('SELECT * FROM photos WHERE annonce_id IS NULL ORDER BY categorie, id')
        : base.lignes('SELECT * FROM photos WHERE annonce_id IS NULL AND categorie = ? ORDER BY id', [Base.categoriePhoto(type)]);
    return {
      'data': [
        for (final p in lignes) {...photoJson(p), 'id': p['id'], 'categorie': p['categorie'], 'titre': p['titre']},
      ],
    };
  }

  static String? _extensionImage(List<int> o) {
    if (o.length > 3 && o[0] == 0xFF && o[1] == 0xD8 && o[2] == 0xFF) return 'jpg';
    if (o.length > 8 && o[0] == 0x89 && o[1] == 0x50 && o[2] == 0x4E && o[3] == 0x47) return 'png';
    if (o.length > 12 && o[0] == 0x52 && o[1] == 0x49 && o[2] == 0x46 && o[3] == 0x46 && o[8] == 0x57 && o[9] == 0x45) return 'webp';
    return null;
  }

  /// Ajoute une photo à l'annonce : fichier envoyé (base64) ou illustration de la bibliothèque.
  Future<Object> _ajouterPhoto(Request q, String ref) async {
    final u = _exiger(q, role: 'annonceur');
    final a = _annoncePourAnnonceur(u, ref, prendreEnCharge: true);
    final d = await _corps(q);
    final annonceId = a['id'] as int;
    final nb = base.valeur('SELECT COUNT(*) FROM photos WHERE annonce_id = ?', [annonceId]) as int;
    if (nb >= maxPhotos) throw ErreurApi.validation({'photo': 'Maximum $maxPhotos photos par annonce.'});
    final iso = maintenant.toIso8601String();
    final categorie = Base.categoriePhoto('${a['type']}');

    final illustrationId = _entier(d['illustration_id']);
    if (illustrationId != null) {
      final p = base.ligne('SELECT * FROM photos WHERE id = ? AND annonce_id IS NULL', [illustrationId]);
      if (p == null) throw ErreurApi.validation({'photo': 'Illustration introuvable.'});
      base.executer('''INSERT INTO photos (annonce_id, categorie, fichier, source, titre, auteur, licence, lien_source, ordre, cree_le)
          VALUES (?, ?, ?, 'illustration', ?, ?, ?, ?, ?, ?)''',
          [annonceId, p['categorie'], p['fichier'], p['titre'], p['auteur'], p['licence'], p['lien_source'], nb, iso]);
    } else {
      final dossier = base.dossierImages;
      if (dossier == null) throw ErreurApi(503, 'Stockage des images indisponible sur ce serveur.');
      List<int> octets;
      try {
        octets = base64Decode(_texte(d['donnees']).replaceFirst(RegExp(r'^data:[^,]*,'), ''));
      } on FormatException {
        throw ErreurApi.validation({'photo': 'Fichier illisible.'});
      }
      if (octets.isEmpty) throw ErreurApi.validation({'photo': 'Choisissez une photo.'});
      if (octets.length > tailleMaxPhoto) throw ErreurApi.validation({'photo': 'Photo trop lourde (5 Mo maximum).'});
      final ext = _extensionImage(octets);
      if (ext == null) throw ErreurApi.validation({'photo': 'Format accepté : JPEG, PNG ou WebP.'});
      final nom = 'annonces/$ref/${maintenant.millisecondsSinceEpoch}-${nb + 1}.$ext';
      final fichier = File('$dossier/$nom');
      fichier.parent.createSync(recursive: true);
      fichier.writeAsBytesSync(octets);
      base.executer('''INSERT INTO photos (annonce_id, categorie, fichier, source, titre, ordre, cree_le)
          VALUES (?, ?, ?, 'annonceur', ?, ?, ?)''', [annonceId, categorie, nom, _texte(d['nom']), nb, iso]);
    }
    return reponseJson({'photos': photosAnnonce(annonceId, '${a['type']}', ref)}, statut: 201);
  }

  Object _supprimerPhoto(Request q, String ref, int id) {
    final u = _exiger(q, role: 'annonceur');
    final a = _annoncePourAnnonceur(u, ref, prendreEnCharge: true);
    final p = base.ligne('SELECT * FROM photos WHERE id = ? AND annonce_id = ?', [id, a['id']]);
    if (p == null) throw ErreurApi(404, 'Photo introuvable.');
    base.executer('DELETE FROM photos WHERE id = ?', [id]);
    final dossier = base.dossierImages;
    if (p['source'] == 'annonceur' && dossier != null) {
      final f = File('$dossier/${p['fichier']}');
      if (f.existsSync()) f.deleteSync();
    }
    return {'photos': photosAnnonce(a['id'] as int, '${a['type']}', ref)};
  }

  Object _annonces(Request q) {
    final p = q.url.queryParameters;
    final pa = q.url.queryParametersAll;
    final where = <String>["a.statut = 'publiee'"];
    final params = <Object?>[];

    if (_texte(p['commune']).isNotEmpty) {
      where.add('c.nom = ?');
      params.add(p['commune']);
    }
    if (_texte(p['quartier']).isNotEmpty) {
      where.add('q.nom = ?');
      params.add(p['quartier']);
    }
    if (_texte(p['type']).isNotEmpty) {
      where.add('a.type = ?');
      params.add(p['type']);
    }
    final pieces = _entier(p['pieces']);
    if (pieces != null && pieces > 0) {
      where.add(pieces >= 5 ? 'a.pieces >= 5' : 'a.pieces = ?');
      if (pieces < 5) params.add(pieces);
    }
    final budget = int.tryParse((p['budget_max'] ?? '').replaceAll(RegExp(r'\D'), ''));
    if (budget != null && budget > 0 && budget < budgetPlafond) {
      where.add('a.loyer <= ?');
      params.add(budget);
    }
    if (_vrai(p['juste'])) where.add('a.loyer <= a.estimation_max');
    if (_vrai(p['meuble'])) where.add('a.meuble = 1');
    for (final e in {...?pa['equipements[]'], ...?pa['equipements']}.take(20)) {
      if (e == 'Meublé') {
        where.add('a.meuble = 1');
      } else {
        where.add('EXISTS (SELECT 1 FROM annonce_equipement ae JOIN equipements e ON e.id = ae.equipement_id WHERE ae.annonce_id = a.id AND e.nom = ?)');
        params.add(e);
      }
    }
    final texte = _borne(_texte(p['q']), 100);
    if (texte.isNotEmpty) {
      where.add('(a.type LIKE ? OR a.description LIKE ? OR q.nom LIKE ? OR c.nom LIKE ?)');
      params.addAll(List.filled(4, '%$texte%'));
    }
    final ordre = switch (p['tri']) {
      'prix_croissant' => 'a.loyer ASC',
      'prix_decroissant' => 'a.loyer DESC',
      'recentes' => 'a.publiee_le DESC',
      _ => 'CASE WHEN a.loyer < a.estimation_min THEN 0 WHEN a.loyer <= a.estimation_max THEN 1 ELSE 2 END, a.loyer ASC',
    };

    final parPage = (_entier(p['per_page']) ?? 50).clamp(1, 100);
    final filtre = 'WHERE ${where.join(' AND ')}';
    final total = base.valeur('SELECT COUNT(*) FROM annonces a JOIN quartiers q ON q.id = a.quartier_id JOIN communes c ON c.id = q.commune_id $filtre', params) as int;
    final derniere = total == 0 ? 1 : (total + parPage - 1) ~/ parPage;
    final page = (_entier(p['page']) ?? 1).clamp(1, derniere);
    final lignes = base.lignes('$_selectAnnonce $filtre ORDER BY $ordre LIMIT ? OFFSET ?', [...params, parPage, (page - 1) * parPage]);
    return {
      'data': [for (final a in lignes) annonceJson(a)],
      'meta': {'current_page': page, 'last_page': derniere, 'per_page': parPage, 'total': total},
    };
  }

  Object _annonce(Request q, String ref) {
    final a = base.ligne('$_selectAnnonce WHERE a.reference = ?', [ref]);
    if (a == null || a['statut'] != 'publiee') throw ErreurApi(404, 'Annonce introuvable.');
    base.executer('UPDATE annonces SET vues = vues + 1 WHERE id = ?', [a['id']]);
    return {'data': annonceJson(a)};
  }

  Object _communes(Request q) {
    final communes = base.lignes('''SELECT c.id, c.nom,
        (SELECT COUNT(*) FROM annonces a JOIN quartiers q ON q.id = a.quartier_id WHERE q.commune_id = c.id AND a.statut = 'publiee') AS nb
        FROM communes c ORDER BY c.nom''');
    return {
      'data': [
        for (final c in communes)
          () {
            final qs = base.lignes('SELECT id, nom FROM quartiers WHERE commune_id = ? ORDER BY nom', [c['id']]);
            return {
              'nom': c['nom'],
              'nb_annonces': c['nb'],
              'quartiers': [for (final x in qs) x['nom']],
              'quartiers_detail': qs,
            };
          }(),
      ],
    };
  }

  Object _referentiel(Request q) => {
        'types': demo.types,
        'equipements': [for (final r in base.lignes('SELECT nom FROM equipements ORDER BY nom')) r['nom']],
        'motifs_signalement': demo.motifsSignalement,
        'budget_plafond': budgetPlafond,
      };

  Object _marche(Request q) {
    final pieces = _entier(q.url.queryParameters['pieces']);
    final filtre = pieces == null ? '' : (pieces >= 5 ? 'AND a.pieces >= 5' : 'AND a.pieces = $pieces');
    final lignes = base.lignes('''SELECT c.nom AS commune, a.loyer, a.pieces, a.estimation_min, a.estimation_max
        FROM annonces a JOIN quartiers q ON q.id = a.quartier_id JOIN communes c ON c.id = q.commune_id
        WHERE a.statut = 'publiee' $filtre''');
    final groupes = <String, List<Map<String, Object?>>>{};
    for (final l in lignes) {
      groupes.putIfAbsent('${l['commune']}', () => []).add(l);
    }
    num mediane(List<num> v) {
      v.sort();
      final m = v.length ~/ 2;
      return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
    }

    final data = [
      for (final e in groupes.entries)
        {
          'commune': e.key,
          'nb_annonces': e.value.length,
          'loyer_median': mediane([for (final l in e.value) l['loyer'] as int]).round(),
          'loyer_min': e.value.map((l) => l['loyer'] as int).reduce((a, b) => a < b ? a : b),
          'loyer_max': e.value.map((l) => l['loyer'] as int).reduce((a, b) => a > b ? a : b),
          'prix_par_piece_median': mediane([for (final l in e.value) (l['loyer'] as int) / ((l['pieces'] as int) < 1 ? 1 : l['pieces'] as int)]).round(),
          'part_au_dessus': (e.value
                      .where((l) => verdict(l['loyer'] as int, l['estimation_min'] as int?, l['estimation_max'] as int?) == 'au_dessus')
                      .length /
                  e.value.length *
                  100)
              .round(),
        },
    ]..sort((a, b) => (b['loyer_median'] as int).compareTo(a['loyer_median'] as int));
    return {'data': data, 'pieces': pieces};
  }

  // ── Estimation ──────────────────────────────────────────────────────────
  /// Adresse du service IA (FastAPI, dossier ../ia_service). IA_SERVICE_URL=aucun pour le désactiver.
  /// Secret partagé avec le service IA (IA_CLE_INTERNE) : lui seul peut appeler l'agent et l'estimation.
  static String get cleInterneIa => Platform.environment['IA_CLE_INTERNE'] ?? '';

  static String get urlIa {
    final u = Platform.environment['IA_SERVICE_URL'] ?? 'http://127.0.0.1:8001';
    return u == 'aucun' ? '' : u.replaceAll(RegExp(r'/$'), '');
  }

  /// Service IA (modèle du Bloc 2) s'il répond, sinon règles simples.
  Future<Estimation> estimer(String commune, String quartier, String type, int pieces, bool meuble, List<String> equipements) async {
    final url = urlIa;
    if (url.isNotEmpty) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await client.postUrl(Uri.parse('${url.replaceAll(RegExp(r'/$'), '')}/estimer'));
        req.headers.contentType = ContentType.json;
        if (cleInterneIa.isNotEmpty) req.headers.set('x-cle-interne', cleInterneIa);
        req.write(jsonEncode({'commune': commune, 'quartier': quartier, 'type': type, 'pieces': pieces, 'meuble': meuble, 'equipements': equipements}));
        final rep = await req.close().timeout(const Duration(seconds: 3));
        final d = jsonDecode(await rep.transform(utf8.decoder).join()) as Map<String, dynamic>;
        client.close();
        if (rep.statusCode == 200 && d['estimation_min'] != null) {
          return Estimation((d['estimation_min'] as num).toInt(), (d['estimation_max'] as num).toInt(), 'modele');
        }
      } catch (e) {
        stderr.writeln('Service IA indisponible, estimation par règles : $e');
      }
    }
    return estimerParRegles(commune, type, pieces, meuble, equipements.length);
  }

  // ── Assistant IA (agent Gemini du service FastAPI) ──────────────────────
  Future<Object> _assistant(Request q) async {
    final d = await _corps(q);
    final message = _texte(d['message']);
    if (message.isEmpty) throw ErreurApi.validation({'message': 'Écrivez votre question.'});
    if (message.length > 1000) throw ErreurApi.validation({'message': 'Message trop long (1000 caractères maximum).'});
    final historique = <Map<String, String>>[
      for (final h in (d['historique'] as List? ?? const []))
        if (h is Map)
          {
            'role': h['role'] == 'assistant' ? 'assistant' : 'utilisateur',
            'texte': _borne('${h['texte'] ?? ''}', 2000),
          },
    ];
    final recents = historique.length > 10 ? historique.sublist(historique.length - 10) : historique;
    if (urlIa.isEmpty) throw ErreurApi(503, 'L\'assistant IA est désactivé sur ce serveur.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.postUrl(Uri.parse('$urlIa/agent/discuter'));
      req.headers.contentType = ContentType.json;
      if (cleInterneIa.isNotEmpty) req.headers.set('x-cle-interne', cleInterneIa);
      req.write(jsonEncode({'message': message, 'historique': recents}));
      final rep = await req.close().timeout(const Duration(seconds: 90));
      final corps = await rep.transform(utf8.decoder).join();
      if (rep.statusCode != 200) {
        stderr.writeln('Assistant IA : réponse ${rep.statusCode} $corps');
        throw ErreurApi(502, 'L\'assistant IA a rencontré un problème. Réessayez.');
      }
      return jsonDecode(corps) as Map<String, dynamic>;
    } on ErreurApi {
      rethrow;
    } catch (e) {
      stderr.writeln('Assistant IA injoignable : $e');
      throw ErreurApi(503, 'L\'assistant IA n\'est pas démarré. Lancez le service : cd ia_service && ./lancer.sh');
    } finally {
      client.close();
    }
  }

  Future<Object> _estimation(Request q) async {
    final d = await _corps(q);
    final commune = _texte(d['commune']);
    final type = _texte(d['type']);
    final pieces = _entier(d['pieces']);
    final err = <String, String>{
      if (base.valeur('SELECT 1 FROM communes WHERE nom = ?', [commune]) == null) 'commune': 'Commune inconnue.',
      if (!demo.types.contains(type)) 'type': 'Type de logement inconnu.',
      if (pieces == null || pieces < 1 || pieces > 20) 'pieces': 'Nombre de pièces invalide (1 à 20).',
    };
    if (err.isNotEmpty) throw ErreurApi.validation(err);
    final equip = [for (final e in (d['equipements'] as List? ?? const [])) '$e'];
    final e = await estimer(commune, _texte(d['quartier']), type, pieces!, _vrai(d['meuble']), equip);
    final r = <String, Object?>{
      'estimation_min': e.minimum,
      'estimation_max': e.maximum,
      'estimation_centrale': e.centrale,
      'source': e.source,
      'nb_comparables': base.valeur('''SELECT COUNT(*) FROM annonces a JOIN quartiers q ON q.id = a.quartier_id JOIN communes c ON c.id = q.commune_id
          WHERE a.statut = 'publiee' AND c.nom = ? AND a.pieces = ?''', [commune, pieces]),
    };
    final loyer = _entier(d['loyer']);
    if (loyer != null && loyer >= 1000) {
      r['verdict'] = verdict(loyer, e.minimum, e.maximum);
      r['ecart_pourcent'] = ((loyer - e.centrale) / e.centrale * 100).round();
    }
    return r;
  }

  // ── Visites et signalements ─────────────────────────────────────────────
  int _idAnnoncePubliee(String ref) {
    final id = base.valeur("SELECT id FROM annonces WHERE reference = ?", [ref]) as int?;
    if (id == null) throw ErreurApi.validation({'annonce': 'Annonce introuvable.'});
    return id;
  }

  Future<Object> _visite(Request q) async {
    final d = await _corps(q);
    final u = _utilisateur(q);
    _reserveAuxLocataires(u);
    _exigerAnnonceurInscrit(_texte(d['annonce']));
    final nom = _texte(d['nom']);
    final tel = _texte(d['telephone']);
    final date = DateTime.tryParse(_texte(d['date_visite']));
    final heure = _texte(d['heure']);
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final err = <String, String>{
      if (nom.isEmpty || nom.length > 80) 'nom': 'Indiquez votre nom (80 caractères au plus).',
      if (!RegExp(r'^[0-9 +]{8,20}$').hasMatch(tel)) 'telephone': 'Entrez un numéro de téléphone valide (ex. 07 01 02 03 04).',
      if (date == null) 'date_visite': 'Choisissez une date.' else if (date.isBefore(aujourdhui)) 'date_visite': 'Choisissez une date à partir d\'aujourd\'hui.',
      if (heure.isEmpty || heure.length > 20) 'heure': 'Choisissez une heure.',
      if (date != null && date.isAfter(aujourdhui.add(const Duration(days: 366)))) 'date_visite': 'Choisissez une date dans l\'année.',
    };
    if (err.isNotEmpty) throw ErreurApi.validation(err);
    final canal = ['web', 'mobile', 'assistant'].contains(d['canal']) ? d['canal'] : 'mobile';
    final id = base.inserer(
        'INSERT INTO visites (annonce_id, utilisateur_id, nom, telephone, date_visite, heure, canal, cree_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [_idAnnoncePubliee(_texte(d['annonce'])), u?['id'], nom, tel, dateIso(date!), heure, canal, maintenant.toIso8601String()]);
    // Notification (et e-mail) à l'annonceur de l'annonce
    final a = base.ligne('''SELECT a.reference, a.type, a.pieces, a.meuble, a.utilisateur_id, q.nom AS quartier
        FROM annonces a JOIN quartiers q ON q.id = a.quartier_id WHERE a.reference = ?''', [_texte(d['annonce'])]);
    if (a != null) {
      notifier(a['utilisateur_id'] as int, 'visite', 'Nouvelle demande de visite',
          '$nom souhaite visiter ${titre('${a['type']}', a['pieces'] as int, a['meuble'] == 1)} à ${a['quartier']} '
              '(${a['reference']}) le ${jourLibelle(date).toLowerCase()} à $heure. Téléphone : $tel.',
          lien: '/espace', courriel: true);
    }
    return reponseJson({'id': id, 'statut': 'en_attente', 'message': 'Demande de visite envoyée à l\'annonceur.'}, statut: 201);
  }

  Future<Object> _signalement(Request q) async {
    final d = await _corps(q);
    final u = _utilisateur(q);
    final motif = _texte(d['motif']);
    if (motif.isEmpty || motif.length > 120) throw ErreurApi.validation({'motif': 'Choisissez un motif.'});
    if (_texte(d['details']).length > 1000) throw ErreurApi.validation({'details': 'Détails trop longs (1 000 caractères maximum).'});
    final iso = maintenant.toIso8601String();
    final id = base.inserer(
        "INSERT INTO signalements (annonce_id, utilisateur_id, motif, details, source, cree_le, modifie_le) VALUES (?, ?, ?, ?, 'utilisateur', ?, ?)",
        [_idAnnoncePubliee(_texte(d['annonce'])), u?['id'], motif, _texte(d['details']).isEmpty ? null : _texte(d['details']), iso, iso]);
    return reponseJson({'id': id, 'message': 'Signalement reçu. Notre équipe va vérifier l\'annonce.'}, statut: 201);
  }

  // ── Comptes ─────────────────────────────────────────────────────────────
  /// Adresses administrateur (variable ADMIN_EMAIL, plusieurs adresses séparées par des virgules).
  static Set<String> get _adressesAdmin => (Platform.environment['ADMIN_EMAIL'] ?? '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();

  Map<String, Object?> _ouvrirSession(int id) {
    // Compte listé dans ADMIN_EMAIL : il devient administrateur dès sa connexion (adresse confirmée par code).
    final email = '${base.valeur('SELECT email FROM utilisateurs WHERE id = ?', [id]) ?? ''}'.toLowerCase();
    if (_adressesAdmin.contains(email)) {
      base.executer("UPDATE utilisateurs SET role = 'admin' WHERE id = ? AND role != 'admin'", [id]);
    }
    final jeton = nouveauJeton();
    base.executer('UPDATE utilisateurs SET jeton = ?, jeton_expire_le = ? WHERE id = ?',
        [empreinteJeton(jeton), maintenant.add(dureeSession).toIso8601String(), id]);
    return {'jeton': jeton, 'utilisateur': _profil(base.ligne('SELECT * FROM utilisateurs WHERE id = ?', [id])!)};
  }

  Future<Object> _connexion(Request q) async {
    final d = await _corps(q);
    final email = _texte(d['email']).toLowerCase();
    _verifierBlocage(email);
    final u = base.ligne('SELECT * FROM utilisateurs WHERE email = ?', [email]);
    // Même durée de calcul que le compte existe ou non (pas d'indice sur les adresses inscrites).
    final ok = verifierMotDePasse('${d['password'] ?? ''}', u == null ? _empreinteFactice : '${u['mot_de_passe']}');
    if (u == null || !ok) {
      if (_echecs.length > 10000) _echecs.clear(); // mémoire bornée
      _echecs.putIfAbsent(email, () => []).add(maintenant);
      throw ErreurApi.validation({'email': 'E-mail ou mot de passe incorrect.'});
    }
    _echecs.remove(email);
    if (u['email_verifie_le'] == null) {
      await _envoyerCode(u);
      throw ErreurApi.validation({'verification': 'Confirmez d\'abord votre adresse e-mail avec le code que nous vous avons envoyé.'});
    }
    return _ouvrirSession(u['id'] as int);
  }

  Future<Object> _inscription(Request q) async {
    final d = await _corps(q);
    final nom = _texte(d['nom']);
    final email = _texte(d['email']).toLowerCase();
    final tel = _texte(d['telephone']);
    final profil = _texte(d['profil']);
    final mdp = '${d['password'] ?? ''}';
    final err = <String, String>{
      if (nom.isEmpty || nom.length > 80) 'nom': 'Indiquez votre nom (80 caractères au plus).',
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email))
        'email': 'Entrez une adresse e-mail valide.'
      else if (base.valeur('SELECT 1 FROM utilisateurs WHERE email = ?', [email]) != null)
        'email': 'Cette adresse e-mail est déjà utilisée.',
      if (tel.isNotEmpty && !RegExp(r'^[0-9 +]{8,20}$').hasMatch(tel)) 'telephone': 'Entrez un numéro de téléphone valide (ex. 07 01 02 03 04).',
      if (!['locataire', 'particulier', 'agence'].contains(profil)) 'profil': 'Choisissez votre profil.',
      if (mdp.length < 8) 'password': 'Le mot de passe doit contenir au moins 8 caractères.',
      if (!_vrai(d['consentement'])) 'consentement': 'Vous devez accepter l\'utilisation de vos données pour créer un compte.',
    };
    if (err.isNotEmpty) throw ErreurApi.validation(err);
    final id = base.inserer(
        'INSERT INTO utilisateurs (nom, email, telephone, mot_de_passe, role, type_annonceur, cree_le) VALUES (?, ?, ?, ?, ?, ?, ?)', [
      nom, email, tel, hacherMotDePasse(mdp),
      profil == 'locataire' ? 'locataire' : 'annonceur',
      profil == 'locataire' ? null : profil,
      maintenant.toIso8601String(),
    ]);
    await _envoyerCode(base.ligne('SELECT * FROM utilisateurs WHERE id = ?', [id])!);
    return reponseJson({'verification': true, 'email': email, 'message': 'Compte créé. Saisissez le code envoyé à $email.'}, statut: 201);
  }

  /// Envoie un nouveau code à 6 chiffres, sauf si le précédent date de moins d'une minute (renvoie alors false).
  Future<bool> _envoyerCode(Map<String, Object?> u) async {
    final precedent = base.valeur('SELECT envoye_le FROM codes_email WHERE utilisateur_id = ?', [u['id']]) as String?;
    if (precedent != null && maintenant.difference(DateTime.parse(precedent)) < delaiRenvoi) return false;
    final code = nouveauCodeEmail();
    base.executer('INSERT OR REPLACE INTO codes_email (utilisateur_id, empreinte, expire_le, essais, envoye_le) VALUES (?, ?, ?, 0, ?)', [
      u['id'], empreinteJeton('${u['id']}:$code'), maintenant.add(dureeCode).toIso8601String(), maintenant.toIso8601String(),
    ]);
    try {
      await _courriel(
        '${u['email']}',
        'Votre code BabiLogis : $code',
        'Bonjour ${u['nom']},\n\n'
            'Votre code de vérification BabiLogis est : $code\n\n'
            'Il est valable ${dureeCode.inMinutes} minutes. Si vous n\'avez pas créé de compte, ignorez cet e-mail.\n\n'
            'L\'équipe BabiLogis',
      );
    } catch (e) {
      stderr.writeln('Envoi du code à ${u['email']} impossible : $e');
      base.executer('DELETE FROM codes_email WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi(503, 'Impossible d\'envoyer l\'e-mail de vérification pour le moment. Réessayez dans quelques minutes.');
    }
    return true;
  }

  Future<Object> _verification(Request q) async {
    final d = await _corps(q);
    final u = base.ligne('SELECT * FROM utilisateurs WHERE email = ?', [_texte(d['email']).toLowerCase()]);
    final code = _texte(d['code']).replaceAll(' ', '');
    if (u == null) throw ErreurApi.validation({'code': 'Code incorrect.'});
    if (u['email_verifie_le'] != null) throw ErreurApi.validation({'code': 'Cette adresse est déjà vérifiée : connectez-vous.'});
    final c = base.ligne('SELECT * FROM codes_email WHERE utilisateur_id = ?', [u['id']]);
    if (c == null || DateTime.parse('${c['expire_le']}').isBefore(maintenant)) {
      throw ErreurApi.validation({'code': 'Ce code a expiré. Demandez-en un nouveau.'});
    }
    if ((c['essais'] as int) >= essaisMaxCode) throw ErreurApi.validation({'code': 'Trop d\'essais. Demandez un nouveau code.'});
    if (c['empreinte'] != empreinteJeton('${u['id']}:$code')) {
      base.executer('UPDATE codes_email SET essais = essais + 1 WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi.validation({'code': 'Code incorrect.'});
    }
    base.executer('UPDATE utilisateurs SET email_verifie_le = ? WHERE id = ?', [maintenant.toIso8601String(), u['id']]);
    base.executer('DELETE FROM codes_email WHERE utilisateur_id = ?', [u['id']]);
    return _ouvrirSession(u['id'] as int);
  }

  Future<Object> _renvoyerCode(Request q) async {
    final d = await _corps(q);
    final u = base.ligne('SELECT * FROM utilisateurs WHERE email = ?', [_texte(d['email']).toLowerCase()]);
    if (u != null && u['email_verifie_le'] == null && !await _envoyerCode(u)) {
      throw ErreurApi(429, 'Patientez une minute avant de demander un nouveau code.');
    }
    return {'message': 'Si un compte attend une vérification à cette adresse, un nouveau code vient d\'être envoyé.'};
  }

  // ── Mot de passe oublié ─────────────────────────────────────────────────
  /// Envoie un code à 6 chiffres (valable 10 min) à l'adresse du compte.
  /// La réponse est toujours la même, que le compte existe ou non (pas de fuite d'adresses).
  Future<Object> _motDePasseOublie(Request q) async {
    final d = await _corps(q);
    final email = _texte(d['email']).toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw ErreurApi.validation({'email': 'Entrez une adresse e-mail valide.'});
    }
    const reponse = {
      'message': 'Si un compte existe à cette adresse, un code de réinitialisation vient d\'être envoyé. '
          'Il est valable 10 minutes.',
    };
    final u = base.ligne('SELECT * FROM utilisateurs WHERE email = ?', [email]);
    if (u == null) {
      // Visible seulement dans la console du serveur (la réponse, elle, ne révèle rien).
      stdout.writeln('Mot de passe oublié : aucun compte pour $email, aucun e-mail envoyé.');
      return reponse;
    }
    final precedent = base.valeur('SELECT envoye_le FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]) as String?;
    if (precedent != null && maintenant.difference(DateTime.parse(precedent)) < delaiRenvoi) {
      stdout.writeln('Mot de passe oublié : code déjà envoyé à $email il y a moins d\'une minute.');
      return reponse;
    }
    final code = nouveauCodeEmail();
    base.executer('INSERT OR REPLACE INTO codes_mot_de_passe (utilisateur_id, empreinte, expire_le, essais, envoye_le) VALUES (?, ?, ?, 0, ?)', [
      u['id'], empreinteJeton('mdp:${u['id']}:$code'), maintenant.add(dureeCode).toIso8601String(), maintenant.toIso8601String(),
    ]);
    try {
      await _courriel(
        '${u['email']}',
        'Réinitialisation de votre mot de passe BabiLogis : $code',
        'Bonjour ${u['nom']},\n\n'
            'Vous avez demandé à réinitialiser votre mot de passe BabiLogis.\n'
            'Votre code est : $code\n\n'
            'Il est valable ${dureeCode.inMinutes} minutes. Si vous n\'êtes pas à l\'origine de cette demande, '
            'ignorez cet e-mail : votre mot de passe actuel reste valable.\n\n'
            'L\'équipe BabiLogis',
      );
    } catch (e) {
      stderr.writeln('Envoi du code de réinitialisation à ${u['email']} impossible : $e');
      base.executer('DELETE FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi(503, 'Impossible d\'envoyer l\'e-mail pour le moment. Réessayez dans quelques minutes.');
    }
    return reponse;
  }

  /// Vérifie le code et enregistre le nouveau mot de passe. Les sessions ouvertes sont fermées.
  Future<Object> _reinitialiserMotDePasse(Request q) async {
    final d = await _corps(q);
    final email = _texte(d['email']).toLowerCase();
    final code = _texte(d['code']).replaceAll(' ', '');
    final mdp = '${d['password'] ?? ''}';
    final err = <String, String>{
      if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) 'code': 'Saisissez le code à 6 chiffres reçu par e-mail.',
      if (mdp.length < 8) 'password': 'Le mot de passe doit contenir au moins 8 caractères.',
    };
    if (err.isNotEmpty) throw ErreurApi.validation(err);
    final u = base.ligne('SELECT * FROM utilisateurs WHERE email = ?', [email]);
    final c = u == null ? null : base.ligne('SELECT * FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]);
    if (u == null || c == null) throw ErreurApi.validation({'code': 'Code incorrect ou expiré. Demandez un nouveau code.'});
    if (DateTime.parse('${c['expire_le']}').isBefore(maintenant)) {
      base.executer('DELETE FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi.validation({'code': 'Ce code a expiré. Demandez-en un nouveau.'});
    }
    if ((c['essais'] as int) >= essaisMaxCode) {
      base.executer('DELETE FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi.validation({'code': 'Trop d\'essais. Demandez un nouveau code.'});
    }
    if (c['empreinte'] != empreinteJeton('mdp:${u['id']}:$code')) {
      base.executer('UPDATE codes_mot_de_passe SET essais = essais + 1 WHERE utilisateur_id = ?', [u['id']]);
      throw ErreurApi.validation({'code': 'Code incorrect.'});
    }
    base.transaction(() {
      // Le code reçu prouve aussi que l'adresse e-mail appartient bien à la personne.
      base.executer('UPDATE utilisateurs SET mot_de_passe = ?, jeton = NULL, email_verifie_le = COALESCE(email_verifie_le, ?) WHERE id = ?',
          [hacherMotDePasse(mdp), maintenant.toIso8601String(), u['id']]);
      base.executer('DELETE FROM codes_mot_de_passe WHERE utilisateur_id = ?', [u['id']]);
    });
    _echecs.remove(email); // le compte est débloqué
    return {'message': 'Mot de passe modifié. Connectez-vous avec votre nouveau mot de passe.'};
  }

  Object _deconnexion(Request q) {
    final u = _exiger(q);
    base.executer('UPDATE utilisateurs SET jeton = NULL WHERE id = ?', [u['id']]);
    return {'message': 'Déconnecté.'};
  }

  /// Suppression définitive du compte, confirmée par le mot de passe. Les demandes de visite
  /// du compte sont effacées, car elles contiennent son nom et son téléphone. Refusée pour
  /// un administrateur et pour un annonceur qui a encore des annonces (la cascade les
  /// effacerait, avec les demandes des autres utilisateurs).
  Future<Object> _supprimerCompte(Request q) async {
    final u = _exiger(q);
    final d = await _corps(q);
    if (!verifierMotDePasse('${d['password'] ?? ''}', '${u['mot_de_passe']}')) {
      throw ErreurApi.validation({'password': 'Mot de passe incorrect.'});
    }
    if (u['role'] == 'admin') throw ErreurApi(403, 'Un compte administrateur ne peut pas être supprimé ici.');
    if (base.valeur('SELECT 1 FROM annonces WHERE utilisateur_id = ? LIMIT 1', [u['id']]) != null) {
      throw ErreurApi(409, 'Supprimez d\'abord vos annonces, puis réessayez.');
    }
    base.transaction(() {
      base.executer('DELETE FROM visites WHERE utilisateur_id = ?', [u['id']]);
      base.executer('DELETE FROM utilisateurs WHERE id = ?', [u['id']]);
    });
    return {'message': 'Compte supprimé.'};
  }

  // ── Espace annonceur ────────────────────────────────────────────────────
  Object _espace(Request q) {
    final u = _exiger(q, role: 'annonceur');
    final statut = _texte(q.url.queryParameters['statut']);
    final annonces = base.lignes(
        '$_selectAnnonce WHERE a.utilisateur_id = ? ${statut.isEmpty ? '' : 'AND a.statut = ?'} ORDER BY a.modifiee_le DESC',
        [u['id'], if (statut.isNotEmpty) statut]);
    final toutes = base.lignes('SELECT id, loyer, estimation_min, estimation_max, statut, vues FROM annonces WHERE utilisateur_id = ?', [u['id']]);
    final depuis = maintenant.subtract(const Duration(days: 7)).toIso8601String();
    final visites = base.lignes('''SELECT v.*, a.reference, a.type, a.pieces, a.meuble, q.nom AS quartier
        FROM visites v JOIN annonces a ON a.id = v.annonce_id JOIN quartiers q ON q.id = a.quartier_id
        WHERE a.utilisateur_id = ?
        ORDER BY CASE WHEN v.statut = 'en_attente' THEN 0 ELSE 1 END, v.date_visite LIMIT 30''', [u['id']]);
    const libelles = {'en_attente': 'En attente', 'confirmee': 'Confirmée', 'refusee': 'Refusée', 'annulee': 'Annulée'};
    return {
      'stats': {
        'publiees': toutes.where((a) => a['statut'] == 'publiee').length,
        'visites_7j': base.valeur(
            'SELECT COUNT(*) FROM visites v JOIN annonces a ON a.id = v.annonce_id WHERE a.utilisateur_id = ? AND v.cree_le >= ?', [u['id'], depuis]),
        'vues': toutes.fold<int>(0, (s, a) => s + (a['vues'] as int)),
        'au_dessus': toutes
            .where((a) => verdict(a['loyer'] as int, a['estimation_min'] as int?, a['estimation_max'] as int?) == 'au_dessus')
            .length,
      },
      'annonces': [for (final a in annonces) annonceJson(a, prive: true)],
      'visites': [
        for (final v in visites)
          {
            'id': v['id'],
            'annonce': v['reference'],
            'annonce_titre': '${titre('${v['type']}', v['pieces'] as int, v['meuble'] == 1)} — ${v['quartier']}',
            'nom': v['nom'],
            'telephone': v['telephone'],
            'date_visite': v['date_visite'],
            'date_libelle': jourLibelle(DateTime.parse('${v['date_visite']}')),
            'heure': v['heure'],
            'canal': v['canal'],
            'statut': v['statut'],
            'statut_libelle': libelles[v['statut']] ?? v['statut'],
          },
      ],
    };
  }

  /// Annonce modifiable par ce compte : la sienne, toutes pour l'administrateur, et les annonces
  /// collectées sur le web (compte technique « collecte »), ouvertes aux propriétaires et agences.
  /// Avec [prendreEnCharge], une annonce collectée que l'on modifie (texte ou photos) devient celle
  /// du compte : elle passe dans son espace, reçoit messages et visites, et les autres comptes ne
  /// peuvent plus la modifier.
  Map<String, Object?> _annoncePourAnnonceur(Map<String, Object?> u, String ref, {bool prendreEnCharge = false}) {
    final a = base.ligne('$_selectAnnonce WHERE a.reference = ?', [ref]);
    if (a == null) throw ErreurApi(404, 'Annonce introuvable.');
    final collectee = a['annonceur_email'] == Base.compteCollecte;
    if (a['utilisateur_id'] != u['id'] && u['role'] != 'admin' && !collectee) {
      throw ErreurApi(403, 'Cette annonce ne vous appartient pas.');
    }
    if (collectee && prendreEnCharge && u['role'] != 'admin') {
      base.executer('UPDATE annonces SET utilisateur_id = ?, lien_origine = NULL, modifiee_le = ? WHERE id = ?',
          [u['id'], maintenant.toIso8601String(), a['id']]);
      return base.ligne('$_selectAnnonce WHERE a.id = ?', [a['id']])!;
    }
    return a;
  }

  Object _afficherPourAnnonceur(Request q, String ref) {
    final u = _exiger(q, role: 'annonceur');
    return {'annonce': annonceJson(_annoncePourAnnonceur(u, ref), prive: true)};
  }

  Future<Object> _enregistrer(Request q, String? ref) async {
    final u = _exiger(q, role: 'annonceur');
    final existante = ref == null ? null : _annoncePourAnnonceur(u, ref, prendreEnCharge: true);
    final d = await _corps(q);

    var quartierId = _entier(d['quartier_id']);
    // Variante « commune + nom du quartier » (app desktop) : le quartier est créé s'il n'existe pas encore.
    if (quartierId == null && _texte(d['commune']).isNotEmpty && _texte(d['quartier']).isNotEmpty) {
      final cid = base.valeur('SELECT id FROM communes WHERE nom = ?', [_texte(d['commune'])]) as int?;
      if (cid != null) {
        final nomQ = _texte(d['quartier']);
        quartierId = base.valeur('SELECT id FROM quartiers WHERE commune_id = ? AND lower(nom) = lower(?)', [cid, nomQ]) as int?;
        quartierId ??= base.inserer('INSERT INTO quartiers (commune_id, nom) VALUES (?, ?)', [cid, nomQ]);
      }
    }
    final quartier = quartierId == null
        ? null
        : base.ligne('SELECT q.id, q.nom, c.nom AS commune FROM quartiers q JOIN communes c ON c.id = q.commune_id WHERE q.id = ?', [quartierId]);
    final type = _texte(d['type']);
    final pieces = _entier(d['pieces']);
    final chambres = _entier(d['chambres']);
    final sdb = _entier(d['salles_bain']);
    final loyer = _entier(d['loyer']);
    final caution = _entier(d['caution_mois']);
    final avance = _entier(d['avance_mois']);
    final description = _texte(d['description']);
    final action = _texte(d['action']);
    final equip = [for (final e in (d['equipements'] as List? ?? const [])) '$e'].where((e) => base.idEquipement(e) != null).toList();

    bool hors(int? v, int min, int max) => v == null || v < min || v > max;
    final err = <String, String>{
      if (quartier == null) 'quartier_id': 'Choisissez le quartier.',
      if (!demo.types.contains(type)) 'type': 'Choisissez le type de logement.',
      if (hors(pieces, 1, 20)) 'pieces': 'Nombre de pièces invalide (1 à 20).',
      if (hors(chambres, 0, 20)) 'chambres': 'Nombre de chambres invalide.',
      if (hors(sdb, 1, 10)) 'salles_bain': 'Nombre de salles de bain invalide.',
      if (hors(loyer, 10000, 20000000)) 'loyer': 'Le loyer doit être d\'au moins 10 000 FCFA.',
      if (hors(caution, 0, 2)) 'caution_mois': 'La caution est limitée à 2 mois (loi n° 2018-575).',
      if (hors(avance, 0, 2)) 'avance_mois': 'L\'avance est limitée à 2 mois (loi n° 2018-575).',
      if (description.length > 3000) 'description': 'La description est limitée à 3 000 caractères.',
      if (!['publier', 'brouillon'].contains(action)) 'action': 'Action inconnue.',
    };
    if (err.isNotEmpty) throw ErreurApi.validation(err);

    final meuble = _vrai(d['meuble']);
    final e = await estimer('${quartier!['commune']}', '${quartier['nom']}', type, pieces!, meuble, equip);
    var statut = existante?['statut'] == 'masquee' ? 'masquee' : (action == 'publier' ? 'publiee' : 'brouillon');
    final iso = maintenant.toIso8601String();
    final publieeLe = existante?['publiee_le'] ?? (statut == 'publiee' ? iso : null);
    final valeurs = [
      quartier['id'], type, pieces, chambres, sdb, meuble ? 1 : 0, loyer, e.minimum, e.maximum, e.source,
      caution, avance, description, statut, publieeLe, iso,
    ];
    final id = base.transaction(() {
      int id;
      if (existante == null) {
        id = base.inserer('''INSERT INTO annonces (quartier_id, type, pieces, chambres, salles_bain, meuble, loyer, estimation_min,
            estimation_max, source_estimation, caution_mois, avance_mois, description, statut, publiee_le, modifiee_le, reference, utilisateur_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [...valeurs, base.nouvelleReference(), u['id']]);
      } else {
        id = existante['id'] as int;
        base.executer('''UPDATE annonces SET quartier_id = ?, type = ?, pieces = ?, chambres = ?, salles_bain = ?, meuble = ?, loyer = ?,
            estimation_min = ?, estimation_max = ?, source_estimation = ?, caution_mois = ?, avance_mois = ?, description = ?,
            statut = ?, publiee_le = ?, modifiee_le = ? WHERE id = ?''', [...valeurs, id]);
      }
      base.definirEquipements(id, equip);
      return id;
    });
    final a = base.ligne('$_selectAnnonce WHERE a.id = ?', [id])!;
    return reponseJson({'annonce': annonceJson(a, prive: true)}, statut: existante == null ? 201 : 200);
  }

  Object _supprimer(Request q, String ref) {
    final u = _exiger(q, role: 'annonceur');
    final a = _annoncePourAnnonceur(u, ref);
    base.executer('DELETE FROM annonces WHERE id = ?', [a['id']]);
    final dossier = base.dossierImages;
    final photos = dossier == null ? null : Directory('$dossier/annonces/$ref');
    if (photos != null && photos.existsSync()) photos.deleteSync(recursive: true);
    return {'message': 'Annonce $ref supprimée.'};
  }

  Future<Object> _repondreVisite(Request q, int id) async {
    final u = _exiger(q, role: 'annonceur');
    final v = base.ligne('''SELECT v.id, v.utilisateur_id AS locataire_id, v.date_visite, v.heure, a.utilisateur_id, a.reference
        FROM visites v JOIN annonces a ON a.id = v.annonce_id WHERE v.id = ?''', [id]);
    if (v == null) throw ErreurApi(404, 'Demande de visite introuvable.');
    if (v['utilisateur_id'] != u['id'] && u['role'] != 'admin') throw ErreurApi(403, 'Cette annonce ne vous appartient pas.');
    final statut = _texte((await _corps(q))['statut']);
    if (!['confirmee', 'refusee'].contains(statut)) throw ErreurApi.validation({'statut': 'Réponse inconnue.'});
    base.executer('UPDATE visites SET statut = ? WHERE id = ?', [statut, id]);
    final locataire = v['locataire_id'] as int?;
    if (locataire != null) {
      final jour = DateTime.tryParse('${v['date_visite']}');
      notifier(locataire, 'visite_reponse', statut == 'confirmee' ? 'Visite confirmée' : 'Visite refusée',
          'Annonce ${v['reference']}${jour == null ? '' : ' · ${jourLibelle(jour).toLowerCase()} à ${v['heure']}'}.',
          lien: '/annonces/${v['reference']}');
    }
    return {'message': statut == 'confirmee' ? 'Visite confirmée.' : 'Visite refusée.', 'statut': statut};
  }

  // ── Notifications ───────────────────────────────────────────────────────
  /// Crée une notification pour [utilisateurId] ; avec [courriel], l'envoie aussi par e-mail (sans bloquer).
  void notifier(int utilisateurId, String type, String titreNotif, String texte, {String? lien, bool courriel = false}) {
    base.executer('INSERT INTO notifications (utilisateur_id, type, titre, texte, lien, cree_le) VALUES (?, ?, ?, ?, ?, ?)',
        [utilisateurId, type, titreNotif, texte, lien, maintenant.toIso8601String()]);
    if (!courriel) return;
    final email = base.valeur('SELECT email FROM utilisateurs WHERE id = ?', [utilisateurId]) as String?;
    if (email == null || !email.contains('@')) return;
    unawaited(_courriel(email, 'BabiLogis — $titreNotif', '$texte\n\nRépondez depuis votre espace BabiLogis.')
        .catchError((Object e) => stderr.writeln('E-mail de notification non envoyé : $e')));
  }

  Map<String, Object?> _notificationJson(Map<String, Object?> n) => {
        'id': n['id'],
        'type': n['type'],
        'titre': n['titre'],
        'texte': n['texte'],
        'lien': n['lien'],
        'lue': n['lue_le'] != null,
        'cree_le': n['cree_le'],
        'quand': ilYA(DateTime.parse('${n['cree_le']}'), maintenant),
      };

  /// Notifications de l'utilisateur (les 30 dernières, ou celles après ?apres=id) + compteurs.
  Object _notifications(Request q) {
    final u = _exiger(q);
    final apres = _entier(q.url.queryParameters['apres']) ?? 0;
    final lignes = base.lignes('SELECT * FROM notifications WHERE utilisateur_id = ? AND id > ? ORDER BY id DESC LIMIT 30',
        [u['id'], apres]);
    return {
      'data': [for (final n in lignes) _notificationJson(n)],
      'non_lues': base.valeur('SELECT COUNT(*) FROM notifications WHERE utilisateur_id = ? AND lue_le IS NULL', [u['id']]),
      'messages_non_lus': _messagesNonLus(u['id'] as int),
    };
  }

  Future<Object> _notificationsLues(Request q) async {
    final u = _exiger(q);
    final d = await _corps(q);
    final iso = maintenant.toIso8601String();
    final ids = [for (final i in (d['ids'] as List? ?? const [])) _entier(i)].whereType<int>().toList();
    if (ids.isEmpty) {
      base.executer('UPDATE notifications SET lue_le = ? WHERE utilisateur_id = ? AND lue_le IS NULL', [iso, u['id']]);
    } else {
      for (final id in ids) {
        base.executer('UPDATE notifications SET lue_le = ? WHERE id = ? AND utilisateur_id = ?', [iso, id, u['id']]);
      }
    }
    return {'non_lues': base.valeur('SELECT COUNT(*) FROM notifications WHERE utilisateur_id = ? AND lue_le IS NULL', [u['id']])};
  }

  // ── Messagerie (locataire ↔ propriétaire ou agence) ─────────────────────
  int _messagesNonLus(int utilisateurId) => base.valeur('''SELECT COUNT(*) FROM messages m JOIN conversations c ON c.id = m.conversation_id
      WHERE (c.locataire_id = ? OR c.annonceur_id = ?) AND m.auteur_id != ? AND m.lu_le IS NULL''',
      [utilisateurId, utilisateurId, utilisateurId]) as int;

  static const _selectConversation = '''
    SELECT c.*, a.reference, a.type, a.pieces, a.meuble, a.loyer, q.nom AS quartier, co.nom AS commune,
      l.nom AS locataire_nom, an.nom AS annonceur_nom, an.type_annonceur
    FROM conversations c
    JOIN annonces a ON a.id = c.annonce_id
    JOIN quartiers q ON q.id = a.quartier_id
    JOIN communes co ON co.id = q.commune_id
    JOIN utilisateurs l ON l.id = c.locataire_id
    JOIN utilisateurs an ON an.id = c.annonceur_id
  ''';

  Map<String, Object?> _conversationJson(Map<String, Object?> c, int moi) {
    final jeSuisLocataire = c['locataire_id'] == moi;
    final dernier = base.ligne('SELECT texte, cree_le, auteur_id FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT 1', [c['id']]);
    final annonceur = c['type_annonceur'] == 'agence' ? '${c['annonceur_nom']}' : '${c['annonceur_nom']} (propriétaire)';
    return {
      'id': c['id'],
      'je_suis': jeSuisLocataire ? 'locataire' : 'annonceur',
      'interlocuteur': jeSuisLocataire ? annonceur : '${c['locataire_nom']}',
      'annonce': {
        'reference': c['reference'],
        'titre': titre('${c['type']}', c['pieces'] as int, c['meuble'] == 1),
        'lieu': '${c['commune']}, ${c['quartier']}',
        'loyer': c['loyer'],
        'photos': photosAnnonce(c['annonce_id'] as int, '${c['type']}', '${c['reference']}').take(1).toList(),
      },
      'dernier_message': dernier?['texte'],
      'dernier_de_moi': dernier != null && dernier['auteur_id'] == moi,
      'maj_le': c['maj_le'],
      'quand': ilYA(DateTime.parse('${c['maj_le']}'), maintenant),
      'non_lus': base.valeur('SELECT COUNT(*) FROM messages WHERE conversation_id = ? AND auteur_id != ? AND lu_le IS NULL',
          [c['id'], moi]),
    };
  }

  Map<String, Object?> _conversationPour(Map<String, Object?> u, int id) {
    final c = base.ligne('$_selectConversation WHERE c.id = ?', [id]);
    if (c == null) throw ErreurApi(404, 'Conversation introuvable.');
    if (c['locataire_id'] != u['id'] && c['annonceur_id'] != u['id']) throw ErreurApi(403, 'Cette conversation ne vous concerne pas.');
    return c;
  }

  /// Ouvre (ou retrouve) la conversation du locataire connecté avec l'annonceur d'une annonce.
  /// Contacter un annonceur et demander une visite sont réservés aux locataires :
  /// un propriétaire, une agence (ou l'administrateur) ne peut pas le faire.
  void _reserveAuxLocataires(Map<String, Object?>? u) {
    if (u != null && (u['role'] == 'annonceur' || u['role'] == 'admin')) {
      throw ErreurApi(403, 'Réservé aux locataires : connectez-vous avec un compte locataire pour contacter un annonceur ou demander une visite.');
    }
  }

  /// Refuse le contact pour une annonce collectée sur le web (son annonceur n'a pas de compte BabiLogis).
  void _exigerAnnonceurInscrit(String reference) {
    final email = base.valeur('SELECT u.email FROM annonces a JOIN utilisateurs u ON u.id = a.utilisateur_id WHERE a.reference = ?',
        [reference]) as String?;
    if (email == Base.compteCollecte) {
      throw ErreurApi(409, 'Cette annonce a été collectée sur le web : son annonceur n\'est pas inscrit sur BabiLogis. '
          'Contactez-le depuis l\'annonce d\'origine.');
    }
  }

  Future<Object> _ouvrirConversation(Request q) async {
    final u = _exiger(q);
    _reserveAuxLocataires(u);
    final d = await _corps(q);
    final a = base.ligne("SELECT id, utilisateur_id, statut FROM annonces WHERE reference = ?", [_texte(d['annonce'])]);
    _exigerAnnonceurInscrit(_texte(d['annonce']));
    if (a == null || a['statut'] != 'publiee') throw ErreurApi(404, 'Annonce introuvable.');
    if (a['utilisateur_id'] == u['id']) throw ErreurApi.validation({'annonce': 'C\'est votre propre annonce.'});
    final iso = maintenant.toIso8601String();
    var id = base.valeur('SELECT id FROM conversations WHERE annonce_id = ? AND locataire_id = ?', [a['id'], u['id']]) as int?;
    id ??= base.inserer('INSERT INTO conversations (annonce_id, locataire_id, annonceur_id, cree_le, maj_le) VALUES (?, ?, ?, ?, ?)',
        [a['id'], u['id'], a['utilisateur_id'], iso, iso]);
    final premier = _texte(d['message']);
    if (premier.isNotEmpty) _ajouterMessage(u, _conversationPour(u, id), premier);
    return reponseJson({'conversation': _conversationJson(_conversationPour(u, id), u['id'] as int)}, statut: 201);
  }

  Object _conversations(Request q) {
    final u = _exiger(q);
    final lignes = base.lignes('$_selectConversation WHERE c.locataire_id = ? OR c.annonceur_id = ? ORDER BY c.maj_le DESC LIMIT 100',
        [u['id'], u['id']]);
    return {
      'data': [for (final c in lignes) _conversationJson(c, u['id'] as int)],
      'messages_non_lus': _messagesNonLus(u['id'] as int),
    };
  }

  Map<String, Object?> _messageJson(Map<String, Object?> m, int moi) => {
        'id': m['id'],
        'texte': m['texte'],
        'moi': m['auteur_id'] == moi,
        'lu': m['lu_le'] != null,
        'cree_le': m['cree_le'],
        'heure': '${m['cree_le']}'.length >= 16 ? '${m['cree_le']}'.substring(11, 16).replaceFirst(':', ' h ') : '',
      };

  /// Messages d'une conversation (tous, ou ceux après ?apres=id) ; marque comme lus ceux de l'interlocuteur.
  Object _messages(Request q, int id) {
    final u = _exiger(q);
    final c = _conversationPour(u, id);
    final apres = _entier(q.url.queryParameters['apres']) ?? 0;
    base.executer('UPDATE messages SET lu_le = ? WHERE conversation_id = ? AND auteur_id != ? AND lu_le IS NULL',
        [maintenant.toIso8601String(), id, u['id']]);
    base.executer("UPDATE notifications SET lue_le = ? WHERE utilisateur_id = ? AND lien = ? AND lue_le IS NULL",
        [maintenant.toIso8601String(), u['id'], '/messages/$id']);
    final lignes = base.lignes('SELECT * FROM messages WHERE conversation_id = ? AND id > ? ORDER BY id LIMIT 500', [id, apres]);
    return {
      'conversation': _conversationJson(c, u['id'] as int),
      'messages': [for (final m in lignes) _messageJson(m, u['id'] as int)],
    };
  }

  Future<Object> _envoyerMessage(Request q, int id) async {
    final u = _exiger(q);
    final c = _conversationPour(u, id);
    final texte = _texte((await _corps(q))['texte']);
    final m = _ajouterMessage(u, c, texte);
    return reponseJson({'message': _messageJson(m, u['id'] as int)}, statut: 201);
  }

  Map<String, Object?> _ajouterMessage(Map<String, Object?> u, Map<String, Object?> c, String texte) {
    if (texte.isEmpty) throw ErreurApi.validation({'texte': 'Écrivez votre message.'});
    if (texte.length > 2000) throw ErreurApi.validation({'texte': 'Message trop long (2 000 caractères maximum).'});
    final iso = maintenant.toIso8601String();
    final mid = base.inserer('INSERT INTO messages (conversation_id, auteur_id, texte, cree_le) VALUES (?, ?, ?, ?)',
        [c['id'], u['id'], texte, iso]);
    base.executer('UPDATE conversations SET maj_le = ? WHERE id = ?', [iso, c['id']]);
    // Notification au destinataire, sauf s'il en a déjà une non lue pour cette conversation (pas de rafale).
    final destinataire = (c['locataire_id'] == u['id'] ? c['annonceur_id'] : c['locataire_id']) as int;
    final lien = '/messages/${c['id']}';
    final dejaNotifie = base.valeur('SELECT COUNT(*) FROM notifications WHERE utilisateur_id = ? AND lien = ? AND lue_le IS NULL',
        [destinataire, lien]) as int;
    if (dejaNotifie == 0) {
      final apercu = texte.length > 120 ? '${texte.substring(0, 117)}…' : texte;
      notifier(destinataire, 'message', 'Nouveau message de ${u['nom']}', '${c['reference']} · $apercu', lien: lien,
          courriel: c['annonceur_id'] == destinataire);
    }
    return base.ligne('SELECT * FROM messages WHERE id = ?', [mid])!;
  }

  // ── Administration ──────────────────────────────────────────────────────
  Object _signalementsAdmin(Request q) {
    _exiger(q, role: 'admin');
    final vue = _texte(q.url.queryParameters['vue']).isEmpty ? 'a_traiter' : _texte(q.url.queryParameters['vue']);
    final filtre = switch (vue) {
      'a_traiter' => "WHERE s.statut = 'a_traiter'",
      'ia' => "WHERE s.source = 'modele'",
      'traites' => "WHERE s.statut != 'a_traiter'",
      _ => '',
    };
    final liste = base.lignes('''SELECT s.*, a.reference, a.type, a.pieces, a.meuble, a.loyer, a.estimation_min, a.estimation_max,
        a.statut AS annonce_statut, q.nom AS quartier, c.nom AS commune
        FROM signalements s JOIN annonces a ON a.id = s.annonce_id JOIN quartiers q ON q.id = a.quartier_id JOIN communes c ON c.id = q.commune_id
        $filtre
        ORDER BY CASE s.risque WHEN 'eleve' THEN 0 WHEN 'moyen' THEN 1 WHEN 'faible' THEN 2 ELSE 3 END, s.cree_le DESC LIMIT 100''');
    final il30 = maintenant.subtract(const Duration(days: 30)).toIso8601String();
    return {
      'compteurs': {
        'a_traiter': base.valeur("SELECT COUNT(*) FROM signalements WHERE statut = 'a_traiter'"),
        'ia': base.valeur("SELECT COUNT(*) FROM signalements WHERE source = 'modele'"),
        'masquees': base.valeur("SELECT COUNT(*) FROM annonces WHERE statut = 'masquee' AND modifiee_le >= ?", [il30]),
        'annonces': base.valeur("SELECT COUNT(*) FROM annonces WHERE statut = 'publiee'"),
        'utilisateurs': base.valeur('SELECT COUNT(*) FROM utilisateurs'),
      },
      'signalements': [
        for (final s in liste)
          () {
            final v = verdict(s['loyer'] as int, s['estimation_min'] as int?, s['estimation_max'] as int?);
            return {
              'id': s['id'],
              'motif': s['motif'],
              'details': s['details'],
              'source': s['source'],
              'risque': s['risque'],
              'statut': s['statut'],
              'date': ilYA(DateTime.parse('${s['cree_le']}'), maintenant),
              'annonce': {
                'id': s['reference'],
                'titre': titre('${s['type']}', s['pieces'] as int, s['meuble'] == 1),
                'quartier': s['quartier'],
                'commune': s['commune'],
                'loyer': s['loyer'],
                'verdict': v,
                'verdict_libelle': verdictLibelle(v),
                'statut': s['annonce_statut'],
              },
            };
          }(),
      ],
    };
  }

  Future<Object> _decider(Request q, int id) async {
    _exiger(q, role: 'admin');
    final s = base.ligne('SELECT s.*, a.reference FROM signalements s JOIN annonces a ON a.id = s.annonce_id WHERE s.id = ?', [id]);
    if (s == null) throw ErreurApi(404, 'Signalement introuvable.');
    final decision = _texte((await _corps(q))['decision']);
    final iso = maintenant.toIso8601String();
    if (decision == 'masquer') {
      base.transaction(() {
        base.executer("UPDATE annonces SET statut = 'masquee', modifiee_le = ? WHERE id = ?", [iso, s['annonce_id']]);
        base.executer("UPDATE signalements SET statut = 'annonce_masquee', modifie_le = ? WHERE annonce_id = ? AND statut = 'a_traiter'",
            [iso, s['annonce_id']]);
      });
      return {'message': 'Annonce ${s['reference']} masquée.'};
    }
    if (decision == 'rejeter') {
      base.executer("UPDATE signalements SET statut = 'rejete', modifie_le = ? WHERE id = ?", [iso, id]);
      return {'message': 'Signalement rejeté : l\'annonce reste en ligne.'};
    }
    throw ErreurApi.validation({'decision': 'Décision inconnue.'});
  }

  Object _republier(Request q, String ref) {
    _exiger(q, role: 'admin');
    final id = base.valeur('SELECT id FROM annonces WHERE reference = ?', [ref]);
    if (id == null) throw ErreurApi(404, 'Annonce introuvable.');
    base.executer("UPDATE annonces SET statut = 'publiee', modifiee_le = ? WHERE id = ?", [maintenant.toIso8601String(), id]);
    return {'message': 'Annonce $ref remise en ligne.'};
  }
}
