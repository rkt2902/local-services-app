/// Fase do stepper do fluxo do pedido (design A12): Pedido · Proposta ·
/// Equipa · No dia · Feito. É só apresentação, não é `JobStatus`; quem a
/// calcula é o presenter de cada papel, nunca o widget nem o relógio.
enum JobFlowStage { request, proposal, team, onTheDay, completed }

extension JobFlowStageLabel on JobFlowStage {
  String get label => switch (this) {
    JobFlowStage.request => 'Pedido',
    JobFlowStage.proposal => 'Proposta',
    JobFlowStage.team => 'Equipa',
    JobFlowStage.onTheDay => 'No dia',
    JobFlowStage.completed => 'Feito',
  };
}
