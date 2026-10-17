import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Fotos escolhidas com o `image_picker` circulam pela app como [XFile]
/// (nunca `dart:io` `File`), porque no browser não há sistema de ficheiros:
/// o `path` de um [XFile] na web é um URL `blob:` e `File(path)` rebenta.
///
/// Largura máxima pedida ao `image_picker` só na web. No telemóvel a foto
/// é comprimida depois por [photoBytesForUpload]; na web essa compressão
/// não existe, por isso é o próprio picker do browser que redimensiona.
double? get webPickMaxWidth => kIsWeb ? 1600 : null;

/// Qualidade JPEG pedida ao `image_picker` só na web (ver [webPickMaxWidth]).
int? get webPickImageQuality => kIsWeb ? 70 : null;

/// Pré-visualização local de uma foto ainda não enviada.
ImageProvider pickedPhotoImage(XFile file) =>
    kIsWeb ? NetworkImage(file.path) : FileImage(File(file.path));

/// Bytes prontos para o Storage: JPEG 800px qualidade 60 no telemóvel
/// (comportamento de sempre), bytes tal como vêm do picker na web.
Future<({Uint8List bytes, String contentType})> photoBytesForUpload(
  XFile file,
) async {
  if (kIsWeb) {
    return (
      bytes: await file.readAsBytes(),
      contentType: file.mimeType ?? 'image/jpeg',
    );
  }
  final compressed = await FlutterImageCompress.compressWithFile(
    File(file.path).absolute.path,
    minWidth: 800,
    minHeight: 800,
    quality: 60,
    format: CompressFormat.jpeg,
  );
  if (compressed == null) {
    throw Exception('Image compression failed for ${file.path}');
  }
  return (bytes: compressed, contentType: 'image/jpeg');
}
