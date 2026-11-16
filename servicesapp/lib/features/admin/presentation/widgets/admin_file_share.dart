import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Entrega um ficheiro de texto gerado no painel (JSON, CSV): folha de
/// partilha do sistema (no browser, descarrega ou partilha). Se não houver
/// folha de partilha, copia o texto e devolve `false`.
Future<bool> adminShareTextFile({
  required String name,
  required String mimeType,
  required String text,
}) async {
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(utf8.encode(text), mimeType: mimeType, name: name),
        ],
        fileNameOverrides: [name],
      ),
    );
    return true;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }
}
