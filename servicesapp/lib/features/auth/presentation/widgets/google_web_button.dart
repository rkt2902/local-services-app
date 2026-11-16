// Botão oficial da Google, só na web. Fora da web o stub devolve um widget
// vazio (o `web_only.dart` do plugin só compila para web).
export 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
