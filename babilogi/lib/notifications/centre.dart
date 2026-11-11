import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../session.dart';
import 'navigateur.dart';

/// Notification reçue du serveur (demande de visite, réponse, nouveau message…).
class NotificationBabi {
  NotificationBabi.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        type = '${j['type']}',
        titre = '${j['titre']}',
        texte = '${j['texte']}',
        lien = j['lien'] as String?,
        lue = j['lue'] == true,
        quand = '${j['quand'] ?? ''}';

  final int id;
  final String type, titre, texte, quand;
  final String? lien;
  bool lue;
}

/// Interroge le serveur toutes les 15 s quand un utilisateur est connecté, tient les compteurs
/// (cloche, messages non lus) et affiche une notification système pour chaque nouvelle notification.
class CentreNotifications extends ChangeNotifier {
  CentreNotifications._();
  static final CentreNotifications instance = CentreNotifications._();

  static const intervalle = Duration(seconds: 15);

  List<NotificationBabi> liste = [];
  int nonLues = 0, messagesNonLus = 0;
  int _dernierVu = -1;
  Timer? _minuterie;
  Session? _session;

  /// À appeler une fois au démarrage : suit les connexions et déconnexions.
  void suivre(Session session) {
    _session = session;
    session.addListener(_surSession);
    _surSession();
  }

  void _surSession() {
    if (_session?.connecte == true) {
      if (_minuterie == null) {
        _dernierVu = -1;
        rafraichir();
        _minuterie = Timer.periodic(intervalle, (_) => rafraichir());
      }
    } else {
      _minuterie?.cancel();
      _minuterie = null;
      liste = [];
      nonLues = messagesNonLus = 0;
      notifyListeners();
    }
  }

  Future<void> rafraichir() async {
    if (_session?.connecte != true) return;
    try {
      final r = await Api.instance.get('/notifications') as Map<String, dynamic>;
      final nouvelle = [for (final n in (r['data'] as List? ?? const [])) NotificationBabi.fromJson(n as Map<String, dynamic>)];
      // Notifications système seulement pour celles arrivées depuis le dernier passage (pas au premier chargement).
      if (_dernierVu >= 0) {
        for (final n in nouvelle.reversed.where((n) => n.id > _dernierVu && !n.lue)) {
          afficherNotificationSysteme(n.titre, n.texte);
        }
      }
      if (nouvelle.isNotEmpty) _dernierVu = nouvelle.map((n) => n.id).reduce((a, b) => a > b ? a : b);
      if (_dernierVu < 0) _dernierVu = 0;
      liste = nouvelle;
      nonLues = (r['non_lues'] as num?)?.toInt() ?? 0;
      messagesNonLus = (r['messages_non_lus'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {
      // serveur momentanément injoignable : on réessaiera au prochain passage
    }
  }

  Future<void> marquerLue(NotificationBabi n) async {
    if (n.lue) return;
    n.lue = true;
    nonLues = nonLues > 0 ? nonLues - 1 : 0;
    notifyListeners();
    try {
      await Api.instance.post('/notifications/lues', {'ids': [n.id]});
    } catch (_) {}
  }

  Future<void> toutMarquerLu() async {
    for (final n in liste) {
      n.lue = true;
    }
    nonLues = 0;
    notifyListeners();
    try {
      await Api.instance.post('/notifications/lues', {});
    } catch (_) {}
  }
}
