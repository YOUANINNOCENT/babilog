import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Erreur renvoyée par l'API (message lisible + erreurs par champ).
class ApiException implements Exception {
  ApiException(this.message, {this.statut = 0, this.erreurs = const {}});

  final String message;
  final int statut;
  final Map<String, String> erreurs;

  String? champ(String nom) => erreurs[nom];

  @override
  String toString() => message;
}

/// Client de l'API BabiLogis (serveur Dart).
class Api {
  Api._();
  static final Api instance = Api._();

  String? jeton;

  Map<String, String> get _entetes => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (jeton != null) 'Authorization': 'Bearer $jeton',
      };

  Uri _uri(String chemin, [Map<String, dynamic>? params]) {
    final propres = <String, dynamic>{};
    params?.forEach((k, v) {
      if (v == null) return;
      if (v is List) {
        if (v.isNotEmpty) propres['$k[]'] = v.map((e) => '$e').toList();
      } else if ('$v'.isNotEmpty) {
        propres[k] = '$v';
      }
    });
    final base = Uri.parse('$apiUrl$chemin');
    return propres.isEmpty ? base : base.replace(queryParameters: propres);
  }

  Future<dynamic> get(String chemin, [Map<String, dynamic>? params]) =>
      _envoyer(() => http.get(_uri(chemin, params), headers: _entetes));

  Future<dynamic> post(String chemin, [Map<String, dynamic>? corps]) =>
      _envoyer(() => http.post(_uri(chemin), headers: _entetes, body: jsonEncode(corps ?? {})));

  Future<dynamic> put(String chemin, Map<String, dynamic> corps) =>
      _envoyer(() => http.put(_uri(chemin), headers: _entetes, body: jsonEncode(corps)));

  Future<dynamic> patch(String chemin, Map<String, dynamic> corps) =>
      _envoyer(() => http.patch(_uri(chemin), headers: _entetes, body: jsonEncode(corps)));

  Future<dynamic> delete(String chemin) => _envoyer(() => http.delete(_uri(chemin), headers: _entetes));

  Future<dynamic> _envoyer(Future<http.Response> Function() requete) async {
    http.Response r;
    try {
      r = await requete().timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(
        'Impossible de joindre le serveur BabiLogis. Vérifiez que le serveur est lancé (dart run bin/serveur.dart dans le dossier serveur).',
      );
    }
    dynamic corps;
    try {
      corps = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      corps = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return corps;

    final erreurs = <String, String>{};
    if (corps is Map && corps['errors'] is Map) {
      (corps['errors'] as Map).forEach((k, v) {
        final cle = '$k'.replaceAll(RegExp(r'\.\d+$'), '');
        erreurs[cle] = v is List && v.isNotEmpty ? '${v.first}' : '$v';
      });
    }
    final message = switch (r.statusCode) {
      401 => 'Connectez-vous pour continuer.',
      403 => 'Accès réservé.',
      // « Adresse inconnue » = route absente : le serveur lancé est une ancienne version.
      404 when corps is Map && corps['message'] == 'Adresse inconnue.' =>
        'Fonction indisponible : le serveur BabiLogis lancé est une ancienne version. '
            'Redémarrez-le (Ctrl + C puis dart run bin/serveur.dart).',
      404 => corps is Map && corps['message'] is String ? corps['message'] as String : 'Page ou annonce introuvable.',
      429 => 'Trop de tentatives. Patientez une minute.',
      422 => erreurs.isNotEmpty ? erreurs.values.first : 'Vérifiez les informations saisies.',
      _ => corps is Map && corps['message'] is String ? corps['message'] as String : 'Une erreur est survenue (${r.statusCode}).',
    };
    throw ApiException(message, statut: r.statusCode, erreurs: erreurs);
  }
}
