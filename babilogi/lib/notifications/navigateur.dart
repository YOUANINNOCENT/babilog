/// Notifications système du navigateur (API Notification), seulement sur le web.
library;

export 'navigateur_stub.dart' if (dart.library.js_interop) 'navigateur_web.dart';
