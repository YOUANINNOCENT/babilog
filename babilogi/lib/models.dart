int _int(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
int? _intN(dynamic v) => v == null ? null : _int(v);

/// Photo d'une annonce : photo de l'annonceur, ou illustration libre de droits.
class PhotoAnnonce {
  PhotoAnnonce.fromJson(Map<String, dynamic> j)
      : id = _intN(j['id']),
        url = '${j['url']}',
        illustration = j['illustration'] == true,
        automatique = j['automatique'] == true,
        credit = j['credit'] as String?,
        lienSource = j['lien_source'] as String?,
        categorie = j['categorie'] as String?;

  final int? id; // null = illustration ajoutée automatiquement (pas encore choisie)
  final String url;
  final bool illustration, automatique;
  final String? credit, lienSource, categorie;

  static List<PhotoAnnonce> liste(dynamic v) =>
      ((v as List?) ?? const []).map((e) => PhotoAnnonce.fromJson(e as Map<String, dynamic>)).toList();
}

/// Annonce (format de l'API, le même que pour l'app mobile).
class Annonce {
  Annonce.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        type = '${j['type']}',
        commune = '${j['commune']}',
        quartier = '${j['quartier']}',
        quartierId = _intN(j['quartier_id']),
        pieces = _int(j['pieces']),
        chambres = _int(j['chambres']),
        sallesBain = _int(j['salles_bain']),
        meuble = j['meuble'] == true || j['meuble'] == 1,
        loyer = _int(j['loyer']),
        estMin = _intN(j['estimation_min']),
        estMax = _intN(j['estimation_max']),
        equipements = ((j['equipements'] as List?) ?? const []).map((e) => '$e').toList(),
        annonceur = '${j['annonceur'] ?? ''}',
        description = '${j['description'] ?? ''}',
        cautionMois = _int(j['caution_mois']),
        avanceMois = _int(j['avance_mois']),
        ageJours = _int(j['age_jours']),
        titre = '${j['titre'] ?? j['type']}',
        verdict = j['verdict'] as String?,
        verdictLibelle = '${j['verdict_libelle'] ?? ''}',
        sourceEstimation = j['source_estimation'] as String?,
        statut = '${j['statut'] ?? 'publiee'}',
        vues = _int(j['vues']),
        nbVisites = _int(j['visites_count']),
        photos = PhotoAnnonce.liste(j['photos']),
        contactPossible = j['contact_possible'] != false,
        lienOrigine = j['lien_origine'] as String?;

  final String id, type, commune, quartier, annonceur, description, titre, verdictLibelle, statut;

  /// Annonce publiée par un vrai compte (propriétaire ou agence) : messages et visites possibles.
  /// false = annonce collectée sur le web, dont l'annonceur n'est pas inscrit.
  final bool contactPossible;
  final String? lienOrigine;
  final int? quartierId, estMin, estMax;
  final int pieces, chambres, sallesBain, loyer, cautionMois, avanceMois, ageJours, vues, nbVisites;
  final bool meuble;
  final List<String> equipements;
  final String? verdict, sourceEstimation;
  final List<PhotoAnnonce> photos;

  /// Vraies photos de l'annonceur (et non des illustrations).
  bool get aDesPhotosReelles => photos.any((p) => !p.illustration);

  String get lieu => commune == quartier ? commune : '$commune, $quartier';

  String get details {
    final d = <String>[lieu];
    if (type != 'Studio') d.add('$chambres chambre${chambres > 1 ? 's' : ''}');
    d.add(meuble ? 'meublé' : (equipements.isNotEmpty && type != 'Studio' ? equipements.first.toLowerCase() : 'non meublé'));
    return d.join(' · ');
  }

  String get publiee => switch (ageJours) {
        0 => 'Publiée aujourd\'hui',
        1 => 'Publiée hier',
        _ => 'Publiée il y a $ageJours jours',
      };

  int? get estimationCentrale => estMin == null || estMax == null ? null : ((estMin! + estMax!) / 2).round();

  String get statutLibelle => switch (statut) {
        'publiee' => 'Publiée',
        'brouillon' => 'Brouillon',
        'masquee' => 'Masquée',
        _ => statut,
      };
}

/// Page de résultats (pagination de l'API).
class Resultats<T> {
  Resultats(this.elements, {required this.page, required this.derniere, required this.total});

  factory Resultats.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) lire) {
    final meta = (j['meta'] as Map?) ?? const {};
    final data = ((j['data'] as List?) ?? const []).map((e) => lire(e as Map<String, dynamic>)).toList();
    return Resultats(data,
        page: _int(meta['current_page'] ?? 1), derniere: _int(meta['last_page'] ?? 1), total: _int(meta['total'] ?? data.length));
  }

  final List<T> elements;
  final int page, derniere, total;
}

class Quartier {
  Quartier(this.id, this.nom);
  final int id;
  final String nom;
}

class Commune {
  Commune.fromJson(Map<String, dynamic> j)
      : nom = '${j['nom']}',
        nbAnnonces = _int(j['nb_annonces']),
        quartiers = ((j['quartiers_detail'] as List?) ?? const [])
            .map((q) => Quartier(_int((q as Map)['id']), '${q['nom']}'))
            .toList();

  final String nom;
  final int nbAnnonces;
  final List<Quartier> quartiers;
}

class Referentiel {
  Referentiel.fromJson(Map<String, dynamic> j)
      : types = ((j['types'] as List?) ?? const []).map((e) => '$e').toList(),
        equipements = ((j['equipements'] as List?) ?? const []).map((e) => '$e').toList(),
        motifs = ((j['motifs_signalement'] as List?) ?? const []).map((e) => '$e').toList();

  final List<String> types, equipements, motifs;
}

class LigneMarche {
  LigneMarche.fromJson(Map<String, dynamic> j)
      : commune = '${j['commune']}',
        nbAnnonces = _int(j['nb_annonces']),
        median = _int(j['loyer_median']),
        minimum = _int(j['loyer_min']),
        maximum = _int(j['loyer_max']),
        parPiece = _int(j['prix_par_piece_median']),
        partAuDessus = _int(j['part_au_dessus']);

  final String commune;
  final int nbAnnonces, median, minimum, maximum, parPiece, partAuDessus;
}

class Utilisateur {
  Utilisateur.fromJson(Map<String, dynamic> j)
      : id = _int(j['id']),
        nom = '${j['nom']}',
        email = '${j['email']}',
        telephone = '${j['telephone'] ?? ''}',
        role = '${j['role']}',
        typeAnnonceur = j['type_annonceur'] as String?,
        initiales = '${j['initiales'] ?? ''}',
        estAnnonceur = j['est_annonceur'] == true,
        estAdmin = j['est_admin'] == true;

  final int id;
  final String nom, email, telephone, role, initiales;
  final String? typeAnnonceur;
  final bool estAnnonceur, estAdmin;
}

class VisiteAnnonceur {
  VisiteAnnonceur.fromJson(Map<String, dynamic> j)
      : id = _int(j['id']),
        annonce = '${j['annonce']}',
        annonceTitre = '${j['annonce_titre']}',
        nom = '${j['nom']}',
        telephone = '${j['telephone']}',
        dateLibelle = '${j['date_libelle']}',
        heure = '${j['heure']}',
        canal = '${j['canal']}',
        statut = '${j['statut']}',
        statutLibelle = '${j['statut_libelle']}';

  final int id;
  final String annonce, annonceTitre, nom, telephone, dateLibelle, heure, canal, statut, statutLibelle;

  String get canalLibelle => switch (canal) {
        'web' => 'le site',
        'mobile' => 'l\'application mobile',
        'assistant' => 'l\'assistant IA',
        _ => canal,
      };
}

class SignalementAdmin {
  SignalementAdmin.fromJson(Map<String, dynamic> j)
      : id = _int(j['id']),
        motif = '${j['motif']}',
        details = j['details'] as String?,
        source = '${j['source']}',
        risque = j['risque'] as String?,
        statut = '${j['statut']}',
        date = '${j['date']}',
        annonceId = '${(j['annonce'] as Map)['id']}',
        annonceTitre = '${(j['annonce'] as Map)['titre']} — ${(j['annonce'] as Map)['quartier']}',
        annonceLoyer = _int((j['annonce'] as Map)['loyer']),
        annonceVerdict = (j['annonce'] as Map)['verdict'] as String?,
        annonceVerdictLibelle = '${(j['annonce'] as Map)['verdict_libelle'] ?? ''}',
        annonceStatut = '${(j['annonce'] as Map)['statut']}';

  final int id, annonceLoyer;
  final String motif, source, statut, date, annonceId, annonceTitre, annonceVerdictLibelle, annonceStatut;
  final String? details, risque, annonceVerdict;
}
