import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/legal_document.dart';

/// Lê e interpreta o texto legal empacotado na app (funciona sem rede).
final legalDocumentProvider =
    FutureProvider.family<LegalDocument, LegalDocumentKind>((ref, kind) async {
  final markdown = await rootBundle.loadString(kind.asset);
  return LegalDocument.parse(markdown);
});
