import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Resultado do OCR local — os 3 campos são heurísticas best-effort, nunca
/// garantidas. Ver `FleetCardTextExtractor._parse` para o raciocínio de
/// cada um e `fleet_card_scan_screen.dart` para onde isto é usado.
class FleetCardExtractedData {
  const FleetCardExtractedData({
    this.barcodeValue,
    this.cardNumber,
    this.holderName,
  });

  final String? barcodeValue;
  final String? cardNumber;
  final String? holderName;

  bool get barcodeWasRead =>
      barcodeValue != null && barcodeValue!.isNotEmpty;
}

/// OCR local (google_mlkit_text_recognition) sobre a foto do cartão. A
/// imagem NUNCA é persistida — nem localmente além do necessário para o
/// reconhecimento, nem no Supabase Storage. `extract()` apaga sempre o
/// ficheiro recebido antes de devolver, com sucesso ou falha do OCR.
class FleetCardTextExtractor {
  const FleetCardTextExtractor();

  static final RegExp _onlyDigitsAndSeparators = RegExp(r'^[\d\s\-]+$');
  static final RegExp _digitsRun = RegExp(r'\d{4,}');
  static final RegExp _anyDigit = RegExp(r'\d');
  static final RegExp _nonLetters = RegExp(r'[^A-Za-zÀ-ÿ]');

  Future<FleetCardExtractedData> extract(File imageFile) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognizedText = await recognizer.processImage(inputImage);
      return _parse(recognizedText.text);
    } catch (_) {
      // OCR falhou (imagem ilegível, formato inesperado, etc.) — devolve
      // tudo vazio, o worker preenche à mão no ecrã de confirmação.
      return const FleetCardExtractedData();
    } finally {
      await recognizer.close();
      // Best-effort: nunca deixar uma falha ao apagar bloquear o fluxo —
      // é um ficheiro temporário do image_picker, o SO limpa-o mais tarde
      // de qualquer forma, mas apagamos já para não depender disso.
      try {
        if (await imageFile.exists()) await imageFile.delete();
      } catch (_) {
        // ignorado de propósito
      }
    }
  }

  /// Heurísticas (nenhuma garantida com cartões reais — ver relatório):
  ///
  /// a. barcode_value — a sequência de 4+ dígitos mais longa entre as que
  ///    estão sozinhas numa linha (linha só com dígitos/espaços/traços,
  ///    sem letras) — assume-se que é a mais "isolada visualmente", como
  ///    o número impresso mesmo por baixo do código de barras costuma
  ///    estar. Se nenhuma linha for puramente numérica, cai para a
  ///    sequência mais longa entre TODAS as encontradas (menos confiança).
  /// b. card_number — outra sequência numérica distinta da já escolhida
  ///    para o barcode, preferindo a mais curta (nº de cliente costuma
  ///    ser mais curto que o código de barras).
  /// c. holder_name — a primeira linha sem nenhum dígito, com 2+ palavras
  ///    e pelo menos 80% dos caracteres alfabéticos em maiúscula (nomes
  ///    impressos em cartões físicos são tipicamente só maiúsculas).
  FleetCardExtractedData _parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final numericCandidates = <({String digits, bool isolatedLine})>[];
    for (final line in lines) {
      final isIsolatedLine = _onlyDigitsAndSeparators.hasMatch(line);
      for (final match in _digitsRun.allMatches(line.replaceAll(' ', ''))) {
        numericCandidates.add((digits: match.group(0)!, isolatedLine: isIsolatedLine));
      }
    }

    String? barcodeValue;
    final isolatedOnly =
        numericCandidates.where((c) => c.isolatedLine).toList();
    final barcodePool = isolatedOnly.isNotEmpty ? isolatedOnly : numericCandidates;
    if (barcodePool.isNotEmpty) {
      barcodePool.sort((a, b) => b.digits.length.compareTo(a.digits.length));
      barcodeValue = barcodePool.first.digits;
    }

    String? cardNumber;
    final remaining = numericCandidates
        .where((c) => c.digits != barcodeValue)
        .toList()
      ..sort((a, b) => a.digits.length.compareTo(b.digits.length));
    if (remaining.isNotEmpty) cardNumber = remaining.first.digits;

    String? holderName;
    for (final line in lines) {
      if (_anyDigit.hasMatch(line)) continue;
      final words =
          line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 2) continue;
      final lettersOnly = line.replaceAll(_nonLetters, '');
      if (lettersOnly.isEmpty) continue;
      final upperCount = lettersOnly
          .split('')
          .where((c) => c == c.toUpperCase() && c != c.toLowerCase())
          .length;
      if (upperCount / lettersOnly.length >= 0.8) {
        holderName = line;
        break;
      }
    }

    return FleetCardExtractedData(
      barcodeValue: barcodeValue,
      cardNumber: cardNumber,
      holderName: holderName,
    );
  }
}
