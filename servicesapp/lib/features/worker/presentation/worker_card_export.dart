import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Exportar o cartão partilhável (imagem e PDF). Funciona igual em
/// Android, iOS e web: os ficheiros são gerados em memória (`XFile.fromData`)
/// e entregues à folha de partilha do sistema, sem escrever no disco.

/// Desenha o widget dentro do [RepaintBoundary] de [boundaryKey] como PNG.
/// [pixelRatio] 3 dá uma imagem nítida para imprimir.
Future<Uint8List> captureCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// PDF A6 com o cartão centrado, pronto a imprimir ou enviar.
Future<Uint8List> buildCardPdf(Uint8List cardPng) async {
  final doc = pw.Document(title: 'Cartão ProJardim', creator: 'ProJardim');
  final image = pw.MemoryImage(cardPng);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ),
  );
  return doc.save();
}

Future<void> shareCardImage(Uint8List png, {required String text}) =>
    SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [
          XFile.fromData(png, mimeType: 'image/png', name: 'cartao-projardim.png'),
        ],
        fileNameOverrides: const ['cartao-projardim.png'],
      ),
    );

Future<void> shareCardPdf(Uint8List pdf) => SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(pdf,
              mimeType: 'application/pdf', name: 'cartao-projardim.pdf'),
        ],
        fileNameOverrides: const ['cartao-projardim.pdf'],
      ),
    );
