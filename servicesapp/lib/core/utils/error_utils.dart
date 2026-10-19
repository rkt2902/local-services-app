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
  if (msg.contains('email already') || msg.contains('user already registered')) {
    return 'Este email já está registado.';
  }
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
    return 'Demasiadas tentativas. Espera alguns minutos e tenta novamente.';
  }

  // Limite anti-spam da policy de INSERT de job_requests (migration 0042):
  // é a única razão realista para a RLS recusar um pedido criado pela app.
  if (msg.contains('row-level security') && msg.contains('job_requests')) {
    return 'Já criaste vários pedidos na última hora. Espera um pouco e tenta novamente.';
  }
  // Validações novas das RPCs (migration 0042): a mensagem já é para o
  // utilizador.
  if (msg.contains('pelo menos amanhã')) {
    return 'A nova data tem de ser pelo menos amanhã.';
  }
  if (msg.contains('maior que zero')) {
    return 'O valor tem de ser maior que zero.';
  }

  // Regra da véspera de `cancel_job` e `propose_reschedule`: a mensagem
  // do servidor diz "24h de antecedência" mas compara datas (só até ao dia
  // anterior ao trabalho).
  if (msg.contains('antecedência')) {
    if (msg.contains('remarcar')) {
      return 'Só podes remarcar até à véspera do trabalho.';
    }
    if (msg.contains('cancelamento')) {
      return 'Só podes cancelar até à véspera do trabalho.';
    }
    return 'Esta ação só é possível até à véspera do trabalho.';
  }
  if (msg.contains('remarcação pendente')) {
    if (msg.contains('sem remarcação')) {
      return 'Esta remarcação já foi respondida. Atualiza o pedido.';
    }
    return 'Já existe uma remarcação pendente. Espera pela resposta.';
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

/// `true` quando a RPC chamada não existe na base de dados (o PostgREST
/// responde `PGRST202`): a app já conhece uma função cuja migration ainda
/// não foi aplicada.
bool isMissingRpcError(Object e) =>
    e is PostgrestException && e.code == 'PGRST202';

/// Mensagem para o erro de uma RPC recente (ex.: `delete_my_account`,
/// `update_job_request`, migration 0049):
/// - função em falta (migration por aplicar) → [unavailableMessage];
/// - recusa levantada pela própria função (`RAISE EXCEPTION`, código
///   `P0001`) → a mensagem dela, que já vem escrita em português para o
///   utilizador;
/// - o resto → [friendlyError].
String rpcErrorMessage(Object e, {required String unavailableMessage}) {
  if (isMissingRpcError(e)) return unavailableMessage;
  if (e is PostgrestException && e.code == 'P0001') {
    final message = e.message.trim();
    if (message.isNotEmpty) return message;
  }
  return friendlyError(e);
}
