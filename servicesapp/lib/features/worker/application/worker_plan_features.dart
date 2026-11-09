import '../../../core/constants/enums.dart';

/// O que cada plano dá (decisão do Henrique a 2026-10-28). Um só sítio
/// para os ecrãs perguntarem "posso?", em vez de compararem planos soltos.
///
/// Grátis: 5 trabalhos aceites por mês, Agenda e cartão partilhável como
/// imagem e link.
/// Pro: trabalhos sem limite, selo Pro, cartão em PDF e painel de ganhos.
/// Pro+: tudo o que o Pro tem, selo Pro+ e Benefícios (cartão frota e
/// parceiros).
///
/// O limite de trabalhos e o painel de ganhos também são verificados no
/// servidor (0060 e 0067); o PDF e os Benefícios só na app.
extension WorkerPlanFeatures on WorkerPlanTier {
  bool get hasUnlimitedJobs => isPaid;
  bool get hasBadge => isPaid;
  bool get canExportCardPdf => isPaid;
  bool get hasEarnings => isPaid;
  bool get hasPartnerBenefits => this == WorkerPlanTier.proPlus;
}

/// Uma linha da comparação de planos na folha "Plano".
class WorkerPlanFeatureRow {
  const WorkerPlanFeatureRow(this.label, this.free, this.pro, this.proPlus);

  final String label;

  /// Texto em cada coluna: "✓" (incluído), "—" (não incluído) ou um valor
  /// curto ("5/mês").
  final String free;
  final String pro;
  final String proPlus;

  String valueFor(WorkerPlanTier tier) => switch (tier) {
        WorkerPlanTier.free => free,
        WorkerPlanTier.pro => pro,
        WorkerPlanTier.proPlus => proPlus,
      };
}

const String planIncluded = '✓';
const String planNotIncluded = '—';

/// [freeMonthlyLimit] vem do servidor (`get_my_plan`); sem ele, 5.
List<WorkerPlanFeatureRow> workerPlanFeatureRows({int? freeMonthlyLimit}) => [
      WorkerPlanFeatureRow(
        'Trabalhos aceites',
        '${freeMonthlyLimit ?? 5}/mês',
        'Sem limite',
        'Sem limite',
      ),
      const WorkerPlanFeatureRow(
          'Agenda', planIncluded, planIncluded, planIncluded),
      const WorkerPlanFeatureRow(
          'Cartão com QR e link', planIncluded, planIncluded, planIncluded),
      const WorkerPlanFeatureRow(
          'Cartão em PDF', planNotIncluded, planIncluded, planIncluded),
      const WorkerPlanFeatureRow(
          'Painel de ganhos', planNotIncluded, planIncluded, planIncluded),
      const WorkerPlanFeatureRow(
          'Selo no perfil e nas propostas', planNotIncluded, 'Pro', 'Pro+'),
      const WorkerPlanFeatureRow(
          'Benefícios (cartão frota e parceiros)',
          planNotIncluded,
          planNotIncluded,
          planIncluded),
    ];

/// Texto curto quando uma funcionalidade pede outro plano. Sem preços nem
/// forma de pagar (regras das lojas): o plano é contratado fora da app.
String workerPlanUpsellLabel(WorkerPlanTier required) =>
    'Disponível no plano ${required.label}. Fala com a ProJardim pelo '
    'Contacto e suporte para mudares de plano.';
