import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/password_policy.dart';

/// Deteção de falha de rede — fiável para o Supabase Auth via tipo
/// (`AuthRetryableFetchException` com `statusCode == null`; o gotrue só o
/// lança assim quando nem chega a obter resposta HTTP, ver `fetch.dart
/// _handleError`), com correspondência de texto como fallback para as
/// restantes exceções (Postgrest, sockets do Dart, etc.), onde não há um
/// tipo estruturado a verificar.
bool isNetworkError(Object e) {
  if (e is AuthRetryableFetchException && e.statusCode == null) return true;
  final msg = e.toString().toLowerCase();
  return msg.contains('network') ||
      msg.contains('socket') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('timeout');
}

/// Ponto único de mapeamento de exceções para mensagens em português.
/// Cobre os casos genéricos da app e os de autenticação — antes
/// duplicados/divergentes entre esta função e `AuthController._mapError`
/// (ver decisions_log.md).
String friendlyError(Object e) {
  if (isNetworkError(e)) {
    return 'Sem ligação à internet. Verifica a tua conexão e tenta novamente.';
  }

  final msg = e.toString().toLowerCase();

  // Autenticação (antes em AuthController._mapError)
  if (msg.contains('invalid login')) return 'Email ou password incorretos.';
  if (msg.contains('email already')) return 'Este email já está registado.';
  if (msg.contains('email not confirmed') || msg.contains('email_not_confirmed')) {
    return 'Confirma o teu email antes de entrar. Verifica a tua caixa de entrada.';
  }
  if (msg.contains('weak_password') || msg.contains('password')) {
    return weakPasswordMessage;
  }
  if (msg.contains('too many requests') ||
      msg.contains('rate_limit') ||
      msg.contains('over_request_rate_limit') ||
      msg.contains('over_email_send_rate_limit')) {
    return 'Demasiadas tentativas. Aguarda alguns minutos e tenta novamente.';
  }

  // Limite anti-spam da policy de INSERT de job_requests (migration 0042):
  // é a única razão realista para a RLS recusar um pedido criado pela app.
  if (msg.contains('row-level security') && msg.contains('job_requests')) {
    return 'Já criaste vários pedidos na última hora. Aguarda um pouco e tenta novamente.';
  }
  // Validações novas das RPCs (migration 0042): a mensagem já é para o
  // utilizador.
  if (msg.contains('pelo menos amanhã')) {
    return 'A nova data tem de ser pelo menos amanhã.';
  }
  if (msg.contains('maior que zero')) {
    return 'O valor tem de ser maior que zero.';
  }

  // Genéricos
  if (msg.contains('24') && (msg.contains('hour') || msg.contains('hora'))) {
    return 'Esta ação requer pelo menos 24h de antecedência.';
  }
  if (msg.contains('already') && msg.contains('proposal')) {
    return 'Já enviaste uma proposta para este pedido.';
  }
  if (msg.contains('duplicate') || msg.contains('unique constraint')) {
    return 'Este registo já existe.';
  }
  if (msg.contains('permission denied') ||
      msg.contains('row-level security') ||
      msg.contains('insufficient_privilege')) {
    return 'Não tens permissão para esta ação.';
  }
  if (msg.contains('dia do trabalho')) {
    return 'Só podes marcar como concluído a partir do dia do trabalho.';
  }
  if (msg.contains('foto de conclusão')) {
    return 'Não foi possível guardar a foto. Tenta novamente ou conclui sem foto.';
  }
  if (msg.contains('não autorizado') ||
      msg.contains('não está a aguardar') ||
      msg.contains('not authorized') ||
      msg.contains('invalid state') ||
      msg.contains('estado inválido')) {
    return 'Esta ação já não é válida — o estado do pedido pode ter mudado. Atualiza e tenta novamente.';
  }

  return 'Ocorreu um erro inesperado. Tenta novamente.';
}
