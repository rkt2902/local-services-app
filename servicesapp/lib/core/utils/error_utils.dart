String friendlyError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('network') ||
      msg.contains('socket') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection refused')) {
    return 'Sem ligação à internet. Verifica a tua conexão e tenta novamente.';
  }
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
  return 'Ocorreu um erro inesperado. Tenta novamente.';
}
