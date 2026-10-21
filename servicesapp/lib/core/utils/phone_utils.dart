import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_toast.dart';

/// Telefones: validação nos formulários e link de WhatsApp.
///
/// O WhatsApp (`wa.me`) só funciona com o número em formato internacional,
/// sem `+` nem espaços (`351912345678`). Os números são guardados como o
/// utilizador os escreveu, por isso a normalização acontece aqui, ao abrir
/// o link, e também cobre os números antigos já gravados sem indicativo.

/// Mensagem de erro do campo de telefone, ou `null` se for válido.
///
/// Aceita números portugueses de 9 dígitos (começados por 2, 3 ou 9),
/// com ou sem indicativo (`+351`, `00351`), e números estrangeiros com
/// indicativo (`+` ou `00`). Espaços, hífenes, pontos e parênteses são
/// ignorados.
String? phoneValidator(
  String? value, {
  String emptyMessage = 'Introduz o teu telefone.',
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return emptyMessage;
  if (whatsAppNumber(text) == null) return invalidPhoneMessage;
  return null;
}

const invalidPhoneMessage =
    'Número inválido. Ex.: 912 345 678 ou +351 912 345 678.';

/// Aviso quando o WhatsApp não abre (número gravado inválido ou sem app).
const whatsAppUnavailableMessage =
    'Não foi possível abrir o WhatsApp para este número.';

/// Número em formato internacional só com dígitos (`351912345678`), ou
/// `null` se não der para obter um número válido.
String? whatsAppNumber(String phone) {
  final trimmed = phone.trim();
  final hasPlus = trimmed.startsWith('+');
  var digits = trimmed.replaceAll(RegExp(r'[\s\-().]'), '');
  if (hasPlus) digits = digits.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;

  if (!hasPlus && digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (!hasPlus) {
    // Sem `+` nem `00`: número português, com ou sem o 351 à frente.
    if (_isPortugueseNational(digits)) return '351$digits';
    return digits.startsWith('351') &&
            _isPortugueseNational(digits.substring(3))
        ? digits
        : null;
  }

  if (digits.startsWith('351')) {
    return _isPortugueseNational(digits.substring(3)) ? digits : null;
  }
  // Estrangeiro: indicativo + número, 8 a 15 dígitos no total (E.164).
  return digits.length >= 8 && digits.length <= 15 ? digits : null;
}

bool _isPortugueseNational(String digits) =>
    RegExp(r'^[239]\d{8}$').hasMatch(digits);

/// Link `wa.me` para o número, ou `null` se o número não for válido.
Uri? whatsAppUri(String phone) {
  final number = whatsAppNumber(phone);
  return number == null ? null : Uri.parse('https://wa.me/$number');
}

/// Abre a conversa de WhatsApp. Devolve `false` se o número for inválido ou
/// não houver nada que abra o link, para o ecrã poder avisar.
Future<bool> openWhatsApp(String phone) async {
  final uri = whatsAppUri(phone);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// [openWhatsApp] com aviso em SnackBar quando não abre.
Future<void> openWhatsAppOrWarn(BuildContext context, String phone) async {
  final toast = AppToast.maybeOf(context);
  if (await openWhatsApp(phone)) return;
  toast?.error(whatsAppUnavailableMessage);
}

/// Telefone no formato em que se grava em `profiles.phone`: `+351912345678`
/// (ou `+<indicativo><número>` para estrangeiros). Todos os ecrãs que
/// gravam o telefone (registo, perfil do cliente, perfil do jardineiro)
/// passam por aqui, para a base de dados ter um só formato. Se o número
/// não for válido (os formulários já o impedem), fica como foi escrito.
String phoneForStorage(String phone) {
  final number = whatsAppNumber(phone);
  return number == null ? phone.trim() : '+$number';
}
