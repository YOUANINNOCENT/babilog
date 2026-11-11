/// Adresse de l'API BabiLogis (serveur Dart du dossier ../serveur).
///
/// - Site servi par le serveur BabiLogis (port 8000, ou en ligne sur Railway) : même adresse, /api.
/// - Site lancé avec « flutter run -d chrome » : http://127.0.0.1:8000/api.
/// - Autre adresse : flutter run -d chrome --dart-define=API_URL=http://…/api
const String _apiUrlForcee = String.fromEnvironment('API_URL');

String get apiUrl {
  if (_apiUrlForcee.isNotEmpty) return _apiUrlForcee;
  final ici = Uri.base;
  if (ici.scheme.startsWith('http')) {
    // Développement : site lancé par « flutter run » sur localhost (port 5000…) → API locale.
    final local = ici.host == 'localhost' || ici.host == '127.0.0.1';
    if (local && ici.port != 8000) return 'http://127.0.0.1:8000/api';
    // Site servi par le serveur BabiLogis (port 8000 en local, ou en ligne : Railway…) → même adresse.
    return '${ici.origin}/api';
  }
  return 'http://127.0.0.1:8000/api';
}

/// Adresse du serveur (sans /api) : les images sont servies sur /images/...
String get origineServeur => apiUrl.replaceFirst(RegExp(r'/api/?$'), '');

/// URL complète d'une image renvoyée par l'API (« /images/... »).
String urlImage(String chemin) => chemin.startsWith('http') ? chemin : '$origineServeur$chemin';
