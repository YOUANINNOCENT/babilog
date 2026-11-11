import 'dart:convert';
import 'dart:io';

import 'package:babilogis_serveur/babilogis_serveur.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Base base;
  late Handler api;

  setUp(() {
    base = Base.ouvrir(null, maintenant: DateTime(2026, 10, 16, 10));
    api = Api(base, horloge: () => DateTime(2026, 10, 16, 10)).routeur.call;
  });
  tearDown(() => base.fermer());

  Future<(int, dynamic)> appel(String methode, String chemin, {Object? corps, String? jeton}) async {
    final r = await api(Request(methode, Uri.parse('http://localhost$chemin'),
        body: corps == null ? null : jsonEncode(corps),
        headers: {'content-type': 'application/json', if (jeton != null) 'authorization': 'Bearer $jeton'}));
    final t = await r.readAsString();
    return (r.statusCode, t.isEmpty ? null : jsonDecode(t));
  }

  test('60 annonces au format de l\'app mobile', () async {
    final (s, d) = await appel('GET', '/api/annonces?per_page=100');
    expect(s, 200);
    expect((d['data'] as List).length, 60);
    expect(d['meta']['total'], 60);
    final a = (d['data'] as List).first as Map;
    for (final cle in ['id', 'type', 'commune', 'quartier', 'pieces', 'loyer', 'estimation_min', 'equipements', 'annonceur', 'age_jours', 'verdict']) {
      expect(a.containsKey(cle), isTrue, reason: cle);
    }
  });

  test('Verdicts identiques à l\'app mobile', () async {
    expect((await appel('GET', '/api/annonces/BL-1001')).$2['data']['verdict'], 'juste');
    expect((await appel('GET', '/api/annonces/BL-1002')).$2['data']['verdict'], 'bonne_affaire');
    expect((await appel('GET', '/api/annonces/BL-1004')).$2['data']['verdict'], 'au_dessus');
    expect((await appel('GET', '/api/annonces/INCONNUE')).$1, 404);
  });

  test('Filtres commune, pièces, budget, équipements', () async {
    final (_, d) = await appel('GET', '/api/annonces?commune=Cocody&pieces=3&budget_max=260000&equipements%5B%5D=Gardien');
    final l = d['data'] as List;
    expect(l, isNotEmpty);
    for (final a in l) {
      expect(a['commune'], 'Cocody');
      expect(a['pieces'], 3);
      expect(a['loyer'] as int, lessThanOrEqualTo(260000));
      expect(a['equipements'], contains('Gardien'));
    }
  });

  test('Estimation avec verdict', () async {
    final (s, d) = await appel('POST', '/api/estimation', corps: {'commune': 'Cocody', 'type': 'Appartement', 'pieces': 3, 'loyer': 400000});
    expect(s, 200);
    expect(d['verdict'], 'au_dessus');
    expect((await appel('POST', '/api/estimation', corps: {'commune': 'Paris', 'type': 'Villa', 'pieces': 3})).$1, 422);
  });

  test('Connexion, espace annonceur, publication, administration', () async {
    expect((await appel('GET', '/api/espace')).$1, 401);
    final (s, d) = await appel('POST', '/api/connexion', corps: {'email': 'horizon@babilogis.ci', 'password': 'password'});
    expect(s, 200);
    final jeton = d['jeton'] as String;
    expect((await appel('GET', '/api/espace', jeton: jeton)).$1, 200);
    expect((await appel('GET', '/api/admin/signalements', jeton: jeton)).$1, 403);

    final quartier = base.valeur("SELECT id FROM quartiers WHERE nom = 'Angré'");
    final (s2, d2) = await appel('POST', '/api/espace/annonces', jeton: jeton, corps: {
      'quartier_id': quartier, 'type': 'Appartement', 'pieces': 3, 'chambres': 2, 'salles_bain': 1, 'loyer': 250000,
      'caution_mois': 2, 'avance_mois': 2, 'equipements': ['Parking'], 'action': 'publier',
    });
    expect(s2, 201);
    expect(d2['annonce']['statut'], 'publiee');
    expect(d2['annonce']['equipements'], ['Parking']);

    expect((await appel('POST', '/api/deconnexion', jeton: jeton)).$1, 200);
    expect((await appel('GET', '/api/moi', jeton: jeton)).$1, 401);

    final (_, admin) = await appel('POST', '/api/connexion', corps: {'email': 'admin@babilogis.ci', 'password': 'password'});
    final (s3, d3) = await appel('GET', '/api/admin/signalements', jeton: admin['jeton'] as String);
    expect(s3, 200);
    expect(d3['compteurs']['a_traiter'], 4);
  });

  test('Suppression du compte : mot de passe exigé, données effacées', () async {
    final (_, d) = await appel('POST', '/api/connexion', corps: {'email': 'awa@babilogis.ci', 'password': 'password'});
    final jeton = d['jeton'] as String;
    final (sv, v) = await appel('POST', '/api/visites', jeton: jeton, corps: {
      'annonce': 'BL-1001', 'nom': 'Awa Koné', 'telephone': '+225 0799887766', 'date_visite': '2026-10-20', 'heure': '10 h',
    });
    expect(sv, 201);
    int visites() => base.valeur('SELECT COUNT(*) FROM visites WHERE telephone = ?', ['+225 0799887766']) as int;
    expect(visites(), 1);

    expect((await appel('DELETE', '/api/moi', corps: {'password': 'password'})).$1, 401);
    final (s1, e1) = await appel('DELETE', '/api/moi', jeton: jeton, corps: {'password': 'mauvais'});
    expect(s1, 422);
    expect(e1['errors']['password'], isNotEmpty);
    expect((await appel('DELETE', '/api/moi', jeton: jeton)).$1, 422);
    expect((await appel('GET', '/api/moi', jeton: jeton)).$1, 200);
    expect(visites(), 1);

    expect((await appel('DELETE', '/api/moi', jeton: jeton, corps: {'password': 'password'})).$1, 200);
    expect((await appel('GET', '/api/moi', jeton: jeton)).$1, 401);
    expect((await appel('POST', '/api/connexion', corps: {'email': 'awa@babilogis.ci', 'password': 'password'})).$1, 422);
    expect(visites(), 0);
    expect(v['id'], isNotNull);
    expect(base.valeur('SELECT COUNT(*) FROM visites WHERE id = ?', [v['id']]), 0);
  });

  test('Suppression refusée pour un annonceur avec annonces et pour un administrateur', () async {
    Future<String> jetonDe(String email) async =>
        (await appel('POST', '/api/connexion', corps: {'email': email, 'password': 'password'})).$2['jeton'] as String;
    int annonces() => base.valeur('SELECT COUNT(*) FROM annonces') as int;
    final avant = annonces();

    final horizon = await jetonDe('horizon@babilogis.ci');
    expect((await appel('DELETE', '/api/moi', jeton: horizon, corps: {'password': 'password'})).$1, 409);
    expect((await appel('GET', '/api/moi', jeton: horizon)).$1, 200);
    expect(annonces(), avant);

    final admin = await jetonDe('admin@babilogis.ci');
    expect((await appel('DELETE', '/api/moi', jeton: admin, corps: {'password': 'password'})).$1, 403);
    expect((await appel('GET', '/api/moi', jeton: admin)).$1, 200);
  });

  test('Visite et signalement', () async {
    expect((await appel('POST', '/api/visites', corps: {
      'annonce': 'BL-1001', 'nom': 'Test', 'telephone': '0700000001', 'date_visite': '2026-10-20', 'heure': '10 h', 'canal': 'web',
    })).$1, 201);
    expect((await appel('POST', '/api/visites', corps: {'annonce': 'BL-1001', 'nom': '', 'telephone': 'x', 'date_visite': '2020-01-01', 'heure': ''})).$1, 422);
    expect((await appel('POST', '/api/signalements', corps: {'annonce': 'BL-1004', 'motif': 'Prix ou informations trompeurs'})).$1, 201);
  });

  test('Mots de passe', () {
    final h = hacherMotDePasse('secret123');
    expect(verifierMotDePasse('secret123', h), isTrue);
    expect(verifierMotDePasse('autre', h), isFalse);
  });

  test('Photos : illustrations automatiques, ajout et suppression par l\'annonceur', () async {
    final dossier = Directory.systemTemp.createTempSync('babilogis_images').path;
    Directory('$dossier/illustrations/appartement').createSync(recursive: true);
    final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0)];
    for (final n in ['a1', 'a2']) {
      File('$dossier/illustrations/appartement/$n.jpg').writeAsBytesSync(jpeg);
    }
    File('$dossier/illustrations/manifeste.json').writeAsStringSync(jsonEncode({
      'photos': [
        for (final n in ['a1', 'a2'])
          {'fichier': 'illustrations/appartement/$n.jpg', 'categorie': 'appartement', 'auteur': 'Test', 'licence': 'CC0'},
      ],
    }));
    final b = Base.ouvrir(null, maintenant: DateTime(2026, 10, 16, 10), dossierImages: dossier);
    final h = Api(b, horloge: () => DateTime(2026, 10, 16, 10)).routeur.call;
    Future<(int, dynamic)> app(String m, String c, {Object? corps, String? jeton}) async {
      final r = await h(Request(m, Uri.parse('http://localhost$c'), body: corps == null ? null : jsonEncode(corps),
          headers: {'content-type': 'application/json', if (jeton != null) 'authorization': 'Bearer $jeton'}));
      final t = await r.readAsString();
      return (r.statusCode, t.isEmpty ? null : jsonDecode(t));
    }

    expect(b.nbIllustrations, 2);
    final (_, liste) = await app('GET', '/api/annonces?type=Appartement&per_page=5');
    final photos = (liste['data'] as List).first['photos'] as List;
    expect(photos, isNotEmpty);
    expect(photos.first['illustration'], isTrue);
    expect(photos.first['credit'], contains('CC0'));

    final (_, cnx) = await app('POST', '/api/connexion', corps: {'email': 'horizon@babilogis.ci', 'password': 'password'});
    final jeton = cnx['jeton'] as String;
    final ref = b.valeur("SELECT reference FROM annonces a JOIN utilisateurs u ON u.id = a.utilisateur_id "
        "WHERE u.email = 'horizon@babilogis.ci' LIMIT 1") as String;
    final (s1, d1) = await app('POST', '/api/espace/annonces/$ref/photos', jeton: jeton,
        corps: {'nom': 'salon.jpg', 'donnees': base64Encode(jpeg)});
    expect(s1, 201);
    expect((d1['photos'] as List).single['illustration'], isFalse);
    expect(File('$dossier/${(d1['photos'] as List).single['url'].toString().substring(8)}').existsSync(), isTrue);
    expect((await app('POST', '/api/espace/annonces/$ref/photos', jeton: jeton, corps: {'donnees': base64Encode([1, 2, 3])})).$1, 422);

    final (_, illus) = await app('GET', '/api/illustrations?type=Appartement');
    final (s2, d2) = await app('POST', '/api/espace/annonces/$ref/photos', jeton: jeton,
        corps: {'illustration_id': (illus['data'] as List).first['id']});
    expect(s2, 201);
    expect((d2['photos'] as List).length, 2);

    final id = (d2['photos'] as List).first['id'];
    final (s3, d3) = await app('DELETE', '/api/espace/annonces/$ref/photos/$id', jeton: jeton);
    expect(s3, 200);
    expect((d3['photos'] as List).length, 1);
    b.fermer();
  });
  test('Inscription : code de vérification par e-mail', () async {
    final envoyes = <String>[];
    var heure = DateTime(2026, 10, 16, 10);
    final api2 = Api(base, horloge: () => heure, courriel: (a, sujet, t) async => envoyes.add(t)).routeur.call;
    Future<(int, dynamic)> appel2(String chemin, Object corps) async {
      final r = await api2(Request('POST', Uri.parse('http://localhost$chemin'), body: jsonEncode(corps)));
      return (r.statusCode, jsonDecode(await r.readAsString()));
    }

    String dernierCode() => RegExp(r'\b\d{6}\b').firstMatch(envoyes.last)!.group(0)!;
    final compte = {'nom': 'Kouassi', 'email': 'Kouassi@exemple.ci', 'profil': 'locataire', 'password': 'motdepasse', 'consentement': true};

    var (s, d) = await appel2('/api/inscription', compte);
    expect(s, 201);
    expect(d['verification'], isTrue);
    expect(d.containsKey('jeton'), isFalse);
    expect(envoyes, hasLength(1));

    // Connexion refusée tant que l'e-mail n'est pas vérifié (pas de nouvel envoi avant une minute).
    (s, d) = await appel2('/api/connexion', {'email': 'kouassi@exemple.ci', 'password': 'motdepasse'});
    expect(s, 422);
    expect(d['errors'], contains('verification'));
    expect(envoyes, hasLength(1));
    expect((await appel2('/api/verification/renvoyer', {'email': 'kouassi@exemple.ci'})).$1, 429);

    final mauvais = dernierCode() == '000000' ? '111111' : '000000';
    expect((await appel2('/api/verification', {'email': 'kouassi@exemple.ci', 'code': mauvais})).$1, 422);

    heure = heure.add(const Duration(minutes: 2));
    expect((await appel2('/api/verification/renvoyer', {'email': 'kouassi@exemple.ci'})).$1, 200);
    expect(envoyes, hasLength(2));

    (s, d) = await appel2('/api/verification', {'email': 'kouassi@exemple.ci', 'code': dernierCode()});
    expect(s, 200);
    expect(d['jeton'], isNotEmpty);
    expect(d['utilisateur']['email_verifie'], isTrue);
    expect((await appel2('/api/connexion', {'email': 'kouassi@exemple.ci', 'password': 'motdepasse'})).$1, 200);
  });

  test('Code de vérification expiré ou trop d\'essais', () async {
    final envoyes = <String>[];
    var heure = DateTime(2026, 10, 16, 10);
    final api2 = Api(base, horloge: () => heure, courriel: (a, sujet, t) async => envoyes.add(t)).routeur.call;
    Future<int> statut(String chemin, Object corps) async =>
        (await api2(Request('POST', Uri.parse('http://localhost$chemin'), body: jsonEncode(corps)))).statusCode;

    await statut('/api/inscription', {'nom': 'Ama', 'email': 'ama@exemple.ci', 'profil': 'agence', 'password': 'motdepasse', 'consentement': true});
    final code = RegExp(r'\b\d{6}\b').firstMatch(envoyes.last)!.group(0)!;
    final mauvais = code == '000000' ? '111111' : '000000';
    for (var i = 0; i < Api.essaisMaxCode; i++) {
      expect(await statut('/api/verification', {'email': 'ama@exemple.ci', 'code': mauvais}), 422);
    }
    expect(await statut('/api/verification', {'email': 'ama@exemple.ci', 'code': code}), 422); // bloqué même avec le bon code

    heure = heure.add(const Duration(minutes: 2));
    await statut('/api/verification/renvoyer', {'email': 'ama@exemple.ci'});
    final nouveau = RegExp(r'\b\d{6}\b').firstMatch(envoyes.last)!.group(0)!;
    heure = heure.add(Api.dureeCode + const Duration(seconds: 1));
    expect(await statut('/api/verification', {'email': 'ama@exemple.ci', 'code': nouveau}), 422);
  });

  test('Messagerie locataire ↔ agence et notifications (visite, message)', () async {
    Future<String> jeton(String email) async =>
        (await appel('POST', '/api/connexion', corps: {'email': email, 'password': 'password'})).$2['jeton'] as String;
    final awa = await jeton('awa@babilogis.ci');
    final horizon = await jeton('horizon@babilogis.ci');
    final ref = base.valeur("SELECT a.reference FROM annonces a JOIN utilisateurs u ON u.id = a.utilisateur_id "
        "WHERE u.email = 'horizon@babilogis.ci' AND a.statut = 'publiee' LIMIT 1") as String;

    expect((await appel('POST', '/api/conversations', corps: {'annonce': ref})).$1, 401);
    final (s1, d1) = await appel('POST', '/api/conversations', jeton: awa, corps: {'annonce': ref, 'message': 'Bonjour, est-il disponible ?'});
    expect(s1, 201);
    final id = d1['conversation']['id'];
    expect(d1['conversation']['je_suis'], 'locataire');
    // même annonce : même conversation
    expect((await appel('POST', '/api/conversations', jeton: awa, corps: {'annonce': ref})).$2['conversation']['id'], id);
    // Un annonceur (propriétaire ou agence) ne peut ni contacter ni demander de visite.
    expect((await appel('POST', '/api/conversations', jeton: horizon, corps: {'annonce': ref})).$1, 403);
    expect((await appel('POST', '/api/visites', jeton: horizon, corps: {
      'annonce': ref, 'nom': 'Horizon', 'telephone': '07 01 02 03 04', 'date_visite': '2099-01-01', 'heure': '10:00'})).$1, 403);

    final (_, n1) = await appel('GET', '/api/notifications', jeton: horizon);
    expect(n1['messages_non_lus'], 1);
    expect((n1['data'] as List).first['type'], 'message');
    expect((n1['data'] as List).first['lien'], '/messages/$id');

    final (_, liste) = await appel('GET', '/api/conversations', jeton: horizon);
    expect((liste['data'] as List).single['non_lus'], 1);
    final (_, msgs) = await appel('GET', '/api/conversations/$id/messages', jeton: horizon);
    expect((msgs['messages'] as List).single['moi'], isFalse);
    expect((await appel('GET', '/api/notifications', jeton: horizon)).$2['messages_non_lus'], 0);

    expect((await appel('POST', '/api/conversations/$id/messages', jeton: horizon, corps: {'texte': 'Oui, visite samedi ?'})).$1, 201);
    final (_, n2) = await appel('GET', '/api/notifications', jeton: awa);
    expect((n2['data'] as List).first['titre'], contains('Nouveau message'));
    expect((await appel('POST', '/api/conversations/$id/messages', jeton: awa, corps: {'texte': ''})).$1, 422);

    // un tiers n'a pas accès à la conversation
    final kouadio = await jeton('kouadio@babilogis.ci');
    expect((await appel('GET', '/api/conversations/$id/messages', jeton: kouadio)).$1, 403);

    // demande de visite → notification à l'agence
    final (sv, _) = await appel('POST', '/api/visites', jeton: awa, corps: {
      'annonce': ref, 'nom': 'Awa Koné', 'telephone': '0102030405', 'date_visite': '2026-10-20', 'heure': '10 h', 'canal': 'web'});
    expect(sv, 201);
    final (_, n3) = await appel('GET', '/api/notifications', jeton: horizon);
    final visite = (n3['data'] as List).firstWhere((n) => n['type'] == 'visite');
    expect(visite['texte'], contains('Awa Koné'));
    expect(visite['lien'], '/espace');
    expect((await appel('POST', '/api/notifications/lues', jeton: horizon, corps: {})).$2['non_lues'], 0);
  });

  test('Mot de passe oublié : code par e-mail puis nouveau mot de passe', () async {
    final envoyes = <String>[];
    final api2 = Api(base, courriel: (a, sujet, t) async => envoyes.add(t)).routeur.call;
    Future<(int, dynamic)> appel2(String chemin, Object corps) async {
      final r = await api2(Request('POST', Uri.parse('http://localhost$chemin'), body: jsonEncode(corps)));
      return (r.statusCode, jsonDecode(await r.readAsString()));
    }

    // Même réponse pour une adresse inconnue (aucun e-mail envoyé).
    expect((await appel2('/api/mot-de-passe/oublie', {'email': 'inconnu@exemple.ci'})).$1, 200);
    expect(envoyes, isEmpty);
    expect((await appel2('/api/mot-de-passe/oublie', {'email': 'pas-une-adresse'})).$1, 422);

    expect((await appel2('/api/mot-de-passe/oublie', {'email': 'fatou@babilogis.ci'})).$1, 200);
    expect(envoyes, hasLength(1));
    final code = RegExp(r'\b\d{6}\b').firstMatch(envoyes.last)!.group(0)!;
    final mauvais = code == '000000' ? '111111' : '000000';
    expect((await appel2('/api/mot-de-passe/reinitialiser',
            {'email': 'fatou@babilogis.ci', 'code': mauvais, 'password': 'nouveaumdp'}))
        .$1, 422);
    expect((await appel2('/api/mot-de-passe/reinitialiser', {'email': 'fatou@babilogis.ci', 'code': code, 'password': 'court'})).$1,
        422);
    expect((await appel2('/api/mot-de-passe/reinitialiser',
            {'email': 'fatou@babilogis.ci', 'code': code, 'password': 'nouveaumdp'}))
        .$1, 200);
    // Le code ne sert qu'une fois ; l'ancien mot de passe ne marche plus.
    expect((await appel2('/api/mot-de-passe/reinitialiser',
            {'email': 'fatou@babilogis.ci', 'code': code, 'password': 'autremdp1'}))
        .$1, 422);
    expect((await appel2('/api/connexion', {'email': 'fatou@babilogis.ci', 'password': 'password'})).$1, 422);
    expect((await appel2('/api/connexion', {'email': 'fatou@babilogis.ci', 'password': 'nouveaumdp'})).$1, 200);
  });

  test('Sécurité : blocage après 8 mots de passe erronés, session expirée après 30 jours', () async {
    for (var i = 0; i < 8; i++) {
      expect((await appel('POST', '/api/connexion', corps: {'email': 'awa@babilogis.ci', 'password': 'mauvais$i'})).$1, 422);
    }
    // Même le bon mot de passe est refusé tant que le compte est bloqué.
    expect((await appel('POST', '/api/connexion', corps: {'email': 'awa@babilogis.ci', 'password': 'password'})).$1, 429);

    // Session : valable 30 jours (horloge avancée de 31 jours → 401).
    var heure = DateTime(2026, 10, 16, 10);
    final api2 = Api(base, horloge: () => heure).routeur.call;
    final r = await api2(Request('POST', Uri.parse('http://localhost/api/connexion'),
        body: jsonEncode({'email': 'horizon@babilogis.ci', 'password': 'password'})));
    final jeton = (jsonDecode(await r.readAsString()) as Map)['jeton'] as String;
    Future<int> moi() async =>
        (await api2(Request('GET', Uri.parse('http://localhost/api/moi'), headers: {'authorization': 'Bearer $jeton'}))).statusCode;
    expect(await moi(), 200);
    heure = heure.add(const Duration(days: 31));
    expect(await moi(), 401);
  });

  test('Sécurité HTTP : en-têtes, CORS limité, limitation par IP, taille des requêtes', () async {
    var t = DateTime(2026, 10, 16, 10);
    final config = ConfigSecurite.depuis({'CORS_ORIGINES': 'https://babilogis.up.railway.app', 'CONFIANCE_PROXY': '1'});
    final h = const Pipeline()
        .addMiddleware(entetesSecurite(config))
        .addMiddleware(cors(config))
        .addMiddleware(tailleMax())
        .addMiddleware(limiteur(config, horloge: () => t))
        .addHandler((Request q) => Response.ok('ok'));
    Request req(String m, String chemin, {String ip = '1.2.3.4', String? origine, Map<String, String> plus = const {}}) =>
        Request(m, Uri.parse('http://localhost$chemin'),
            headers: {'x-forwarded-for': ip, if (origine != null) 'origin': origine, ...plus});

    final r = await h(req('GET', '/api/annonces', origine: 'https://babilogis.up.railway.app'));
    expect(r.headers['x-content-type-options'], 'nosniff');
    expect(r.headers['x-frame-options'], 'DENY');
    expect(r.headers['access-control-allow-origin'], 'https://babilogis.up.railway.app');
    expect((await h(req('GET', '/api/annonces', origine: 'https://pirate.example'))).headers['access-control-allow-origin'], isNull);

    // 10 connexions par IP en 5 minutes, puis 429 ; une autre IP n'est pas touchée.
    for (var i = 0; i < 10; i++) {
      expect((await h(req('POST', '/api/connexion'))).statusCode, 200);
    }
    expect((await h(req('POST', '/api/connexion'))).statusCode, 429);
    expect((await h(req('POST', '/api/connexion', ip: '5.6.7.8'))).statusCode, 200);
    t = t.add(const Duration(minutes: 6));
    expect((await h(req('POST', '/api/connexion'))).statusCode, 200);

    final lourde = Request('POST', Uri.parse('http://localhost/api/visites'),
        headers: {'x-forwarded-for': '9.9.9.9'}, body: List<int>.filled(9 * 1024 * 1024, 32));
    expect((await h(lourde)).statusCode, 413);
  });
}
