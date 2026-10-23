/// O que o cartão público de um jardineiro deixa fazer (A7). A UI recebe
/// capacidades, nunca regras de subscrição: quando o plano Pro existir, só
/// muda quem preenche isto (o servidor, em `worker_can_use_public_card` e
/// `worker_can_receive_direct_requests`, migration 0059), não os ecrãs.
class WorkerPublicCardFeatureAccess {
  const WorkerPublicCardFeatureAccess({
    required this.canUsePublicCard,
    required this.canSharePublicCard,
    required this.canReceiveDirectRequests,
  });

  /// Estado atual do produto: todos os jardineiros têm cartão, partilha e
  /// pedidos diretos.
  const WorkerPublicCardFeatureAccess.allEnabled()
      : canUsePublicCard = true,
        canSharePublicCard = true,
        canReceiveDirectRequests = true;

  final bool canUsePublicCard;
  final bool canSharePublicCard;
  final bool canReceiveDirectRequests;
}
