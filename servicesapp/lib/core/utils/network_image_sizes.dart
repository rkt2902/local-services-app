import 'package:flutter/widgets.dart';

/// Imagens da rede descodificadas perto do tamanho em que aparecem
/// (AUD-25). Sem isto, um avatar de 40 px descodificava a foto original
/// inteira e gastava memória em listas longas.

/// Avatares (círculos até cerca de 96 px).
ImageProvider networkAvatar(String url) =>
    ResizeImage(NetworkImage(url), width: 256);

/// Miniaturas de fotos de pedidos em cartões e grelhas.
ImageProvider networkThumbnail(String url) =>
    ResizeImage(NetworkImage(url), width: 600);
