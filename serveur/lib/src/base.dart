/// Base de données SQLite (modèle MERISE) et données de démonstration.
///
///   COMMUNE (1,n) ── QUARTIER (1,n) ── ANNONCE (n,1) ── UTILISATEUR (annonceur)
///   ANNONCE (n,n) ── EQUIPEMENT          ANNONCE (1,n) ── VISITE, SIGNALEMENT
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'donnees_demo.dart' as demo;
import 'securite.dart';

const schema = '''
CREATE TABLE IF NOT EXISTS communes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS quartiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  commune_id INTEGER NOT NULL REFERENCES communes(id) ON DELETE CASCADE,
  nom TEXT NOT NULL,
  UNIQUE (commune_id, nom)
);
CREATE TABLE IF NOT EXISTS utilisateurs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  telephone TEXT NOT NULL DEFAULT '',
  mot_de_passe TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'locataire',          -- locataire | annonceur | admin
  type_annonceur TEXT,                             -- agence | particulier
  jeton TEXT UNIQUE,                               -- empreinte SHA-256 du jeton d'API
  email_verifie_le TEXT,                           -- NULL tant que le code reçu par e-mail n'est pas saisi
  cree_le TEXT NOT NULL
);
-- Code de vérification de l'e-mail (un seul en cours par compte ; on ne garde que son empreinte).
CREATE TABLE IF NOT EXISTS codes_email (
  utilisateur_id INTEGER PRIMARY KEY REFERENCES utilisateurs(id) ON DELETE CASCADE,
  empreinte TEXT NOT NULL,
  expire_le TEXT NOT NULL,
  essais INTEGER NOT NULL DEFAULT 0,
  envoye_le TEXT NOT NULL
);
-- Code de réinitialisation du mot de passe (« mot de passe oublié ») : un seul en cours par compte.
CREATE TABLE IF NOT EXISTS codes_mot_de_passe (
  utilisateur_id INTEGER PRIMARY KEY REFERENCES utilisateurs(id) ON DELETE CASCADE,
  empreinte TEXT NOT NULL,
  expire_le TEXT NOT NULL,
  essais INTEGER NOT NULL DEFAULT 0,
  envoye_le TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS equipements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS annonces (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reference TEXT NOT NULL UNIQUE,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  quartier_id INTEGER NOT NULL REFERENCES quartiers(id),
  type TEXT NOT NULL,
  pieces INTEGER NOT NULL,
  chambres INTEGER NOT NULL,
  salles_bain INTEGER NOT NULL DEFAULT 1,
  meuble INTEGER NOT NULL DEFAULT 0,
  loyer INTEGER NOT NULL,
  estimation_min INTEGER,
  estimation_max INTEGER,
  source_estimation TEXT,
  caution_mois INTEGER NOT NULL DEFAULT 2,
  avance_mois INTEGER NOT NULL DEFAULT 2,
  description TEXT NOT NULL DEFAULT '',
  statut TEXT NOT NULL DEFAULT 'publiee',          -- brouillon | publiee | masquee
  vues INTEGER NOT NULL DEFAULT 0,
  publiee_le TEXT,
  modifiee_le TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_annonces_recherche ON annonces(statut, type, pieces, loyer);
CREATE TABLE IF NOT EXISTS annonce_equipement (
  annonce_id INTEGER NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  equipement_id INTEGER NOT NULL REFERENCES equipements(id) ON DELETE CASCADE,
  PRIMARY KEY (annonce_id, equipement_id)
);
CREATE TABLE IF NOT EXISTS visites (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  annonce_id INTEGER NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  utilisateur_id INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  nom TEXT NOT NULL,
  telephone TEXT NOT NULL,
  date_visite TEXT NOT NULL,
  heure TEXT NOT NULL,
  canal TEXT NOT NULL DEFAULT 'web',               -- web | mobile | assistant
  statut TEXT NOT NULL DEFAULT 'en_attente',       -- en_attente | confirmee | refusee | annulee
  cree_le TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS signalements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  annonce_id INTEGER NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  utilisateur_id INTEGER REFERENCES utilisateurs(id) ON DELETE SET NULL,
  motif TEXT NOT NULL,
  details TEXT,
  source TEXT NOT NULL DEFAULT 'utilisateur',      -- utilisateur | modele
  risque TEXT,                                     -- faible | moyen | eleve
  statut TEXT NOT NULL DEFAULT 'a_traiter',        -- a_traiter | annonce_masquee | rejete
  cree_le TEXT NOT NULL,
  modifie_le TEXT NOT NULL
);
-- PHOTO : bibliothèque d'illustrations (annonce_id NULL) et photos des annonces.
-- Les fichiers sont dans donnees/images/ ; la base garde le chemin, l'auteur et la licence.
CREATE TABLE IF NOT EXISTS photos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  annonce_id INTEGER REFERENCES annonces(id) ON DELETE CASCADE,
  categorie TEXT NOT NULL,                         -- studio | appartement | villa
  fichier TEXT NOT NULL,                           -- chemin relatif à donnees/images
  source TEXT NOT NULL DEFAULT 'annonceur',        -- annonceur | illustration
  titre TEXT,
  auteur TEXT,
  licence TEXT,
  lien_source TEXT,
  ordre INTEGER NOT NULL DEFAULT 0,
  cree_le TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_photos_annonce ON photos(annonce_id, ordre);
CREATE UNIQUE INDEX IF NOT EXISTS idx_photos_bibliotheque ON photos(fichier) WHERE annonce_id IS NULL;
-- MESSAGERIE : une conversation par (annonce, locataire) avec l'annonceur de l'annonce.
CREATE TABLE IF NOT EXISTS conversations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  annonce_id INTEGER NOT NULL REFERENCES annonces(id) ON DELETE CASCADE,
  locataire_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  annonceur_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  cree_le TEXT NOT NULL,
  maj_le TEXT NOT NULL,
  UNIQUE (annonce_id, locataire_id)
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  auteur_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  texte TEXT NOT NULL,
  lu_le TEXT,
  cree_le TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, id);
-- NOTIFICATION : demandes de visite, réponses, nouveaux messages… (lues par le site, le mobile et le desktop)
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  utilisateur_id INTEGER NOT NULL REFERENCES utilisateurs(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                              -- visite | visite_reponse | message
  titre TEXT NOT NULL,
  texte TEXT NOT NULL,
  lien TEXT,                                       -- page à ouvrir : /espace, /messages/12…
  lue_le TEXT,
  cree_le TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notifications ON notifications(utilisateur_id, id);
''';

class Base {
  Base._(this.db, this.dossierImages);

  final Database db;

  /// Dossier des images (donnees/images) ; null pour une base en mémoire sans images.
  final String? dossierImages;

  /// Ouvre (ou crée) la base. [chemin] null = base en mémoire (tests).
  /// Au premier démarrage, si donnees/annonces_reelles.json existe (Blocs 1 et 2),
  /// ce sont ces vraies annonces qui sont chargées ; sinon, les annonces de démonstration.
  factory Base.ouvrir(String? chemin, {DateTime? maintenant, String? fichierReel, String? dossierImages}) {
    final Database db;
    if (chemin == null) {
      db = sqlite3.openInMemory();
    } else {
      File(chemin).parent.createSync(recursive: true);
      db = sqlite3.open(chemin);
    }
    db.execute('PRAGMA foreign_keys = ON');
    db.execute(schema);
    // Bases créées avant la vérification de l'e-mail : les comptes existants sont considérés vérifiés.
    if (!db.select('PRAGMA table_info(utilisateurs)').any((c) => c['name'] == 'email_verifie_le')) {
      db.execute('ALTER TABLE utilisateurs ADD COLUMN email_verifie_le TEXT');
      db.execute('UPDATE utilisateurs SET email_verifie_le = cree_le');
    }
    // Expiration des jetons de session (30 jours).
    if (!db.select('PRAGMA table_info(utilisateurs)').any((c) => c['name'] == 'jeton_expire_le')) {
      db.execute('ALTER TABLE utilisateurs ADD COLUMN jeton_expire_le TEXT');
    }
    // Lien vers l'annonce d'origine (annonces collectées sur le web).
    if (!db.select('PRAGMA table_info(annonces)').any((c) => c['name'] == 'lien_origine')) {
      db.execute('ALTER TABLE annonces ADD COLUMN lien_origine TEXT');
    }
    final images = dossierImages ?? (chemin == null ? null : '${File(chemin).parent.path}/images');
    final b = Base._(db, images);
    final reel = fichierReel ?? (chemin == null ? null : '${File(chemin).parent.path}/annonces_reelles.json');
    if (b.valeur('SELECT COUNT(*) FROM annonces') == 0) {
      b.remplirDemo(maintenant ?? DateTime.now(),
          fichierReel: reel != null && File(reel).existsSync() ? reel : null,
          demoOuverte: chemin == null || Platform.environment['BABILOGIS_DEMO'] == '1');
    }
    // Vraies données : plus de comptes de démonstration, seulement les vrais comptes.
    if (b.nbAnnoncesReelles > 0) b.supprimerComptesDemo();
    if (reel != null && File(reel).existsSync()) b.completerLiensOrigine(reel);
    b.importerIllustrations();
    b.retirerMentionsCollecte();
    return b;
  }

  /// Phrase technique ajoutée aux annonces collectées (« Annonce publique collectée sur … Annonce d'origine : URL ») :
  /// elle n'est plus affichée aux visiteurs.
  static final _mentionCollecte =
      RegExp(r"\s*Annonce publique collectée sur .*?Annonce d'origine\s*:\s*\S+", dotAll: true);

  /// Description sans la mention technique de collecte.
  static String sansMentionCollecte(String description) => description.replaceAll(_mentionCollecte, '').trim();

  /// Retire une fois pour toutes la mention de collecte des descriptions enregistrées.
  void retirerMentionsCollecte() {
    final lignes = this.lignes("SELECT id, description FROM annonces WHERE description LIKE '%Annonce publique collectée sur%'");
    if (lignes.isEmpty) return;
    transaction(() {
      for (final l in lignes) {
        executer('UPDATE annonces SET description = ? WHERE id = ?', [sansMentionCollecte('${l['description']}'), l['id']]);
      }
    });
  }

  void fermer() => db.dispose();

  // ── Photos ──────────────────────────────────────────────────────────────
  /// Catégorie de photo d'un type de logement.
  static String categoriePhoto(String type) => switch (type) {
        'Studio' => 'studio',
        'Villa' => 'villa',
        _ => 'appartement',
      };

  /// Ajoute à la bibliothèque les illustrations listées dans images/illustrations/manifeste.json
  /// (créé par outils/collecter_images.py). Renvoie le nombre de nouvelles photos.
  int importerIllustrations() {
    final dossier = dossierImages;
    if (dossier == null) return 0;
    final manifeste = File('$dossier/illustrations/manifeste.json');
    if (!manifeste.existsSync()) return 0;
    final avant = valeur('SELECT COUNT(*) FROM photos WHERE annonce_id IS NULL') as int;
    final donnees = jsonDecode(manifeste.readAsStringSync()) as Map<String, dynamic>;
    final iso = DateTime.now().toIso8601String();
    final presents = <String>{};
    transaction(() {
      for (final brut in (donnees['photos'] as List? ?? const [])) {
        final p = brut as Map<String, dynamic>;
        final fichier = '${p['fichier']}';
        if (!File('$dossier/$fichier').existsSync()) continue;
        presents.add(fichier);
        executer('''INSERT OR IGNORE INTO photos (annonce_id, categorie, fichier, source, titre, auteur, licence, lien_source, cree_le)
            VALUES (NULL, ?, ?, 'illustration', ?, ?, ?, ?, ?)''',
            [p['categorie'], fichier, p['titre'], p['auteur'], p['licence'], p['lien_source'], iso]);
      }
      // Illustrations retirées du manifeste (nouvelle collecte) : on les enlève de la bibliothèque.
      for (final r in lignes('SELECT id, fichier FROM photos WHERE annonce_id IS NULL')) {
        if (!presents.contains(r['fichier'])) executer('DELETE FROM photos WHERE id = ?', [r['id']]);
      }
    });
    return (valeur('SELECT COUNT(*) FROM photos WHERE annonce_id IS NULL') as int) - avant;
  }

  int get nbIllustrations => valeur('SELECT COUNT(*) FROM photos WHERE annonce_id IS NULL') as int;

  // ── Outils ──────────────────────────────────────────────────────────────
  List<Map<String, Object?>> lignes(String sql, [List<Object?> params = const []]) =>
      [for (final r in db.select(sql, params)) Map<String, Object?>.from(r)];

  Map<String, Object?>? ligne(String sql, [List<Object?> params = const []]) {
    final l = lignes(sql, params);
    return l.isEmpty ? null : l.first;
  }

  Object? valeur(String sql, [List<Object?> params = const []]) {
    final r = db.select(sql, params);
    return r.isEmpty ? null : r.first.values.first;
  }

  void executer(String sql, [List<Object?> params = const []]) => db.execute(sql, params);

  int inserer(String sql, [List<Object?> params = const []]) {
    db.execute(sql, params);
    return db.lastInsertRowId;
  }

  T transaction<T>(T Function() f) {
    db.execute('BEGIN');
    try {
      final r = f();
      db.execute('COMMIT');
      return r;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  int? idEquipement(String nom) => valeur('SELECT id FROM equipements WHERE nom = ?', [nom]) as int?;

  void definirEquipements(int annonceId, Iterable<String> noms) {
    executer('DELETE FROM annonce_equipement WHERE annonce_id = ?', [annonceId]);
    for (final n in noms) {
      final id = idEquipement(n);
      if (id != null) executer('INSERT OR IGNORE INTO annonce_equipement VALUES (?, ?)', [annonceId, id]);
    }
  }

  String nouvelleReference() {
    final refs = lignes("SELECT reference FROM annonces WHERE reference LIKE 'BL-%'");
    var maxi = 5000;
    for (final r in refs) {
      final n = int.tryParse('${r['reference']}'.substring(3)) ?? 0;
      if (n > maxi) maxi = n;
    }
    return 'BL-${maxi + 1}';
  }

  // ── Données de démonstration ────────────────────────────────────────────
  /// Nombre d'annonces réelles chargées (0 = mode démonstration).
  int get nbAnnoncesReelles =>
      valeur("SELECT COUNT(*) FROM annonces a JOIN utilisateurs u ON u.id = a.utilisateur_id WHERE u.email = 'collecte@babilogis.ci'") as int;

  void remplirDemo(DateTime maintenant, {String? fichierReel, bool demoOuverte = true}) {
    final iso = maintenant.toIso8601String();
    transaction(() {
      for (final c in demo.communes) {
        final cid = inserer('INSERT INTO communes (nom) VALUES (?)', [c]);
        for (final q in demo.quartiers[c]!) {
          executer('INSERT INTO quartiers (commune_id, nom) VALUES (?, ?)', [cid, q]);
        }
      }
      for (final e in demo.equipements) {
        executer('INSERT INTO equipements (nom) VALUES (?)', [e]);
      }
      if (fichierReel != null) {
        // Vraies annonces : aucun compte de démonstration, seulement le compte technique « collecte ».
        _importerAnnoncesReelles(fichierReel, maintenant, motDePasseDesactive, iso);
        return;
      }
      // Comptes de démo : mot de passe « password » seulement en mémoire (tests) ou avec BABILOGIS_DEMO=1.
      // Sinon (base sur disque, donc potentiellement en ligne) : mot de passe aléatoire, inutilisable.
      final mdp = hacherMotDePasse(demoOuverte ? 'password' : nouveauJeton());
      for (final (nom, email, tel, role, typeA) in demo.comptes) {
        executer(
            'INSERT INTO utilisateurs (nom, email, telephone, mot_de_passe, role, type_annonceur, email_verifie_le, cree_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [nom, email, tel, mdp, role, typeA, iso, iso]);
      }

      {
        final agences = {for (final r in lignes("SELECT id, nom FROM utilisateurs WHERE type_annonceur = 'agence'")) '${r['nom']}': r['id'] as int};
        final particuliers = [for (final r in lignes("SELECT id FROM utilisateurs WHERE type_annonceur = 'particulier' ORDER BY id")) r['id'] as int];
        final r = Random(7);
        var p = 0;
        for (final a in [...demo.annoncesEcrites, ...demo.annoncesSimulees()]) {
          final uid = a.annonceur == 'Particulier' ? particuliers[p++ % particuliers.length] : agences[a.annonceur]!;
          final qid = valeur(
              'SELECT q.id FROM quartiers q JOIN communes c ON c.id = q.commune_id WHERE c.nom = ? AND q.nom = ?', [a.commune, a.quartier]) as int;
          final publiee = maintenant.subtract(Duration(days: a.ageJours, hours: r.nextInt(10)));
          final id = inserer('''INSERT INTO annonces (reference, utilisateur_id, quartier_id, type, pieces, chambres, salles_bain, meuble,
              loyer, estimation_min, estimation_max, source_estimation, description, statut, vues, publiee_le, modifiee_le)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'regles', ?, 'publiee', ?, ?, ?)''', [
            a.reference, uid, qid, a.type, a.pieces, a.chambres, a.sdb, a.meuble ? 1 : 0, a.loyer, a.estMin, a.estMax,
            a.description, 10 + r.nextInt(290), publiee.toIso8601String(), publiee.toIso8601String(),
          ]);
          definirEquipements(id, a.equipements);
        }
      }

      // Quelques visites et signalements pour l'espace annonceur et l'administration.
      int idAnnonce(String ref) => valeur('SELECT id FROM annonces WHERE reference = ?', [ref]) as int;
      final awa = valeur("SELECT id FROM utilisateurs WHERE email = 'awa@babilogis.ci'") as int;
      DateTime prochain(int jourSemaine) {
        var d = DateTime(maintenant.year, maintenant.month, maintenant.day).add(const Duration(days: 1));
        while (d.weekday != jourSemaine) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      }

      final visites = [
        ('BL-1002', prochain(DateTime.saturday), '10 h', 'mobile', 'confirmee'),
        ('BL-1001', prochain(DateTime.saturday), '11 h', 'mobile', 'en_attente'),
        ('BL-1006', prochain(DateTime.monday), '17 h', 'assistant', 'en_attente'),
        ('BL-1009', maintenant.add(const Duration(days: 3)), '15 h', 'web', 'en_attente'),
        ('BL-1007', maintenant.add(const Duration(days: 4)), '9 h', 'web', 'en_attente'),
      ];
      for (final (ref, date, heure, canal, statut) in visites) {
        executer('INSERT INTO visites (annonce_id, utilisateur_id, nom, telephone, date_visite, heure, canal, statut, cree_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', [
          idAnnonce(ref), awa, 'Awa Koné', '0102030405',
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}', heure, canal, statut, iso,
        ]);
      }
      final signalements = [
        ('BL-1004', 'Prix ou informations trompeurs', 'Le loyer est bien au-dessus des autres appartements du quartier.', 'utilisateur', 'moyen', 2),
        ('BL-1006', 'Photos qui ne correspondent pas', null, 'utilisateur', 'faible', 1),
        ('BL-1009', 'Prix très supérieur à la fourchette estimée', 'Le loyer dépasse nettement la fourchette estimée par le modèle.', 'modele', 'moyen', 0),
        ('BL-1010', 'On me demande de l\'argent avant la visite', 'L\'annonceur demande 10 000 FCFA de « frais de visite ».', 'utilisateur', 'eleve', 0),
      ];
      for (final (ref, motif, details, source, risque, ilYa) in signalements) {
        final quand = maintenant.subtract(Duration(days: ilYa, hours: 2)).toIso8601String();
        executer('INSERT INTO signalements (annonce_id, utilisateur_id, motif, details, source, risque, cree_le, modifie_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [idAnnonce(ref), source == 'utilisateur' ? awa : null, motif, details, source, risque, quand, quand]);
      }
    });
  }

  /// Compte technique propriétaire des annonces collectées sur le web : personne ne peut s'y connecter,
  /// donc ces annonces ne peuvent pas recevoir de messages ni de demandes de visite.
  static const compteCollecte = 'collecte@babilogis.ci';

  /// Renseigne le lien de l'annonce d'origine des annonces collectées (champ « url » du fichier).
  void completerLiensOrigine(String fichier) {
    final manquants = valeur('''SELECT COUNT(*) FROM annonces a JOIN utilisateurs u ON u.id = a.utilisateur_id
        WHERE u.email = ? AND a.lien_origine IS NULL''', [compteCollecte]) as int;
    if (manquants == 0) return;
    final donnees = jsonDecode(File(fichier).readAsStringSync()) as Map<String, dynamic>;
    transaction(() {
      for (final brut in donnees['annonces'] as List) {
        final a = brut as Map<String, dynamic>;
        final url = '${a['url'] ?? ''}';
        if (url.startsWith('http')) {
          executer('UPDATE annonces SET lien_origine = ? WHERE reference = ? AND lien_origine IS NULL', [url, a['reference']]);
        }
      }
    });
  }

  /// Mot de passe impossible à saisir (format non reconnu) : le compte ne peut pas se connecter.
  static const motDePasseDesactive = 'desactive';

  /// Supprime les comptes de démonstration (…@babilogis.ci, mot de passe « password ») quand
  /// les vraies données sont chargées. Un compte qui possède encore des annonces est conservé.
  /// Leurs demandes de visite (nom, téléphone) sont effacées ; conversations, messages et
  /// notifications partent en cascade. Le compte technique « collecte », propriétaire des
  /// annonces collectées, est gardé mais ne peut plus se connecter.
  /// Renvoie les adresses supprimées.
  List<String> supprimerComptesDemo() {
    final supprimes = <String>[];
    transaction(() {
      for (final (_, email, _, _, _) in demo.comptes) {
        final id = valeur('SELECT id FROM utilisateurs WHERE email = ?', [email]) as int?;
        if (id == null) continue;
        if (valeur('SELECT 1 FROM annonces WHERE utilisateur_id = ? LIMIT 1', [id]) != null) continue;
        executer('DELETE FROM visites WHERE utilisateur_id = ?', [id]);
        executer('DELETE FROM utilisateurs WHERE id = ?', [id]);
        supprimes.add(email);
      }
      executer("UPDATE utilisateurs SET mot_de_passe = ?, jeton = NULL WHERE email = 'collecte@babilogis.ci'", [motDePasseDesactive]);
    });
    return supprimes;
  }

  /// Donne le rôle administrateur au compte [email] (option --admin du serveur). Renvoie false s'il n'existe pas.
  bool nommerAdministrateur(String email) {
    final id = valeur('SELECT id FROM utilisateurs WHERE email = ?', [email.trim().toLowerCase()]) as int?;
    if (id == null) return false;
    executer("UPDATE utilisateurs SET role = 'admin' WHERE id = ?", [id]);
    return true;
  }

  /// Vraies annonces collectées (Bloc 1) avec l'estimation du modèle (Bloc 2).
  void _importerAnnoncesReelles(String fichier, DateTime maintenant, String mdp, String iso) {
    final donnees = jsonDecode(File(fichier).readAsStringSync()) as Map<String, dynamic>;
    final uid = inserer(
        'INSERT INTO utilisateurs (nom, email, telephone, mot_de_passe, role, type_annonceur, email_verifie_le, cree_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ['Annonces collectées (web)', 'collecte@babilogis.ci', '0700000001', mdp, 'annonceur', 'agence', iso, iso]);
    for (final e in const ['Piscine', 'Jardin', 'Terrasse', 'Ascenseur']) {
      executer('INSERT OR IGNORE INTO equipements (nom) VALUES (?)', [e]);
    }
    final r = Random(7);
    for (final brut in donnees['annonces'] as List) {
      final a = brut as Map<String, dynamic>;
      final cid = valeur('SELECT id FROM communes WHERE nom = ?', [a['commune']]) as int?;
      if (cid == null) continue;
      executer('INSERT OR IGNORE INTO quartiers (commune_id, nom) VALUES (?, ?)', [cid, a['quartier']]);
      final qid = valeur('SELECT id FROM quartiers WHERE commune_id = ? AND nom = ?', [cid, a['quartier']]) as int;
      final publiee = maintenant.subtract(Duration(days: (a['age_jours'] as num).toInt(), hours: r.nextInt(10))).toIso8601String();
      final id = inserer('''INSERT INTO annonces (reference, utilisateur_id, quartier_id, type, pieces, chambres, salles_bain, meuble,
          loyer, estimation_min, estimation_max, source_estimation, description, statut, vues, publiee_le, modifiee_le)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'modele', ?, 'publiee', ?, ?, ?)''', [
        a['reference'], uid, qid, a['type'], a['pieces'], a['chambres'], a['salles_bain'], a['meuble'] == true ? 1 : 0,
        a['loyer'], a['estimation_min'], a['estimation_max'], a['description'], 5 + r.nextInt(200), publiee, publiee,
      ]);
      definirEquipements(id, [for (final e in (a['equipements'] as List? ?? const [])) '$e']);
    }
  }
}
