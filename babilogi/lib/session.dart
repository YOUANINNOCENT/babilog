import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Utilisateur connecté (jeton gardé dans le navigateur).
class Session extends ChangeNotifier {
  Utilisateur? utilisateur;
  bool pret = false;

  bool get connecte => utilisateur != null;

  static const _cle = 'babilogis_jeton';

  Future<void> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jeton = prefs.getString(_cle);
      if (jeton != null) {
        Api.instance.jeton = jeton;
        final r = await Api.instance.get('/moi') as Map<String, dynamic>;
        utilisateur = Utilisateur.fromJson(r['utilisateur'] as Map<String, dynamic>);
      }
    } catch (_) {
      Api.instance.jeton = null;
      utilisateur = null;
    }
    pret = true;
    notifyListeners();
  }

  Future<void> _ouvrir(Map<String, dynamic> r) async {
    final jeton = '${r['jeton']}';
    Api.instance.jeton = jeton;
    utilisateur = Utilisateur.fromJson(r['utilisateur'] as Map<String, dynamic>);
    try {
      (await SharedPreferences.getInstance()).setString(_cle, jeton);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> connexion(String email, String motDePasse) async {
    final r = await Api.instance.post('/connexion', {'email': email.trim(), 'password': motDePasse});
    await _ouvrir(r as Map<String, dynamic>);
  }

  /// Crée le compte et envoie le code de vérification ; renvoie l'e-mail à vérifier.
  Future<String> inscription(Map<String, dynamic> donnees) async {
    final r = await Api.instance.post('/inscription', donnees) as Map<String, dynamic>;
    return '${r['email']}';
  }

  Future<void> verifierEmail(String email, String code) async {
    final r = await Api.instance.post('/verification', {'email': email, 'code': code.trim()});
    await _ouvrir(r as Map<String, dynamic>);
  }

  Future<void> renvoyerCode(String email) => Api.instance.post('/verification/renvoyer', {'email': email});

  Future<void> deconnexion() async {
    try {
      await Api.instance.post('/deconnexion');
    } catch (_) {}
    Api.instance.jeton = null;
    utilisateur = null;
    try {
      (await SharedPreferences.getInstance()).remove(_cle);
    } catch (_) {}
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  static Session read(BuildContext context) => context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
