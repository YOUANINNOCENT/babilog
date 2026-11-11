import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Le navigateur sait-il afficher des notifications système ?
bool get notificationsDisponibles {
  try {
    web.Notification.permission; // lève une erreur si l'API n'existe pas (ancien navigateur)
    return true;
  } catch (_) {
    return false;
  }
}

/// « granted », « denied » ou « default » (pas encore demandé).
String get permissionNotifications => notificationsDisponibles ? web.Notification.permission : 'denied';

Future<String> demanderPermissionNotifications() async {
  if (!notificationsDisponibles) return 'denied';
  final r = await web.Notification.requestPermission().toDart;
  return r.toDart;
}

/// Affiche une notification système (même si l'onglet est en arrière-plan), si elle est autorisée.
void afficherNotificationSysteme(String titre, String texte) {
  if (permissionNotifications != 'granted') return;
  web.Notification(titre, web.NotificationOptions(body: texte, icon: '/icons/Icon-192.png', tag: 'babilogis'));
}
