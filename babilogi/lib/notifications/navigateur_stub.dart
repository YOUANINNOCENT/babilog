/// Hors navigateur (tests) : pas de notification système.
bool get notificationsDisponibles => false;

String get permissionNotifications => 'denied';

Future<String> demanderPermissionNotifications() async => 'denied';

void afficherNotificationSysteme(String titre, String texte) {}
