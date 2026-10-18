import '../../../core/constants/enums.dart';
import '../../jobs/data/job_model.dart';
import 'client_create_job_wizard_provider.dart';

// Regras dos campos de um pedido, partilhadas pelo wizard de criar pedido
// e pelo ecrã "Editar pedido" (para os dois validarem o mesmo), e o
// mapeamento de "Publicar de novo" (pedido antigo → rascunho do wizard).
// Sem Flutter nem Riverpod: testado em test/job_request_form_test.dart.

/// Mínimo e máximo da descrição do pedido.
const jobDescriptionMinLength = 10;
const jobDescriptionMaxLength = 500;

/// Máximo do texto livre de disponibilidade. A coluna `availability_text`
/// não tem CHECK na base de dados (0001/0042); o limite é só da app, para
/// o texto caber nos cartões.
const availabilityTextMaxLength = 200;

const availabilityTextHint =
    'Ex.: Sábados de manhã ou dias úteis depois das 18h';

/// Erro do campo de disponibilidade, ou `null` se for válido.
String? availabilityTextError(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 'Indica quando estás disponível.';
  if (trimmed.length > availabilityTextMaxLength) {
    return 'Máximo $availabilityTextMaxLength caracteres.';
  }
  return null;
}

/// `true` quando a data (sem horas) já passou em relação a [now].
bool isPastDay(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  return day.isBefore(today);
}

/// "Publicar de novo": pedidos que acabaram sem nenhum jardineiro escolhido
/// (expirados sem resposta, ou cancelados pelo próprio cliente enquanto
/// estavam abertos, sem proposta aceite).
bool canRepublishJob(JobRequest job) {
  if (job.status == JobStatus.noResponse) return true;
  if (job.status != JobStatus.cancelled) return false;
  if (job.acceptedProposalId != null) return false;
  return job.cancelledBy == null || job.cancelledBy == job.clientId;
}

/// Rascunho do wizard a partir de um pedido antigo: mesmo serviço, morada,
/// localização, descrição, dimensão e modo de data. Uma data fixa que já
/// passou fica vazia (o cliente escolhe outra). As fotos não passam: as do
/// pedido antigo ficam com ele. Com [serviceStillOffered] `false` (o
/// serviço saiu do catálogo), o serviço fica por escolher.
ClientCreateJobWizardState republishWizardState(
  JobRequest job, {
  required DateTime now,
  bool serviceStillOffered = true,
}) {
  final preferredDate = job.dateMode == DateMode.fixed &&
          job.preferredDate != null &&
          !isPastDay(job.preferredDate!, now)
      ? job.preferredDate
      : null;
  final hasLocation = job.locationLat != 0 || job.locationLng != 0;
  return ClientCreateJobWizardState(
    serviceTypeId: serviceStillOffered ? job.serviceTypeId : null,
    dateMode: job.dateMode,
    preferredDate: preferredDate,
    availabilityText: job.dateMode == DateMode.availability
        ? (job.availabilityText ?? '').trim()
        : '',
    urgency: job.urgency ?? Urgency.normal,
    sizeEstimate: job.sizeEstimate,
    addressText: job.addressText,
    addressAutoFilled: false,
    locationArea: job.locationArea,
    locationLat: hasLocation ? job.locationLat : null,
    locationLng: hasLocation ? job.locationLng : null,
    description: job.description,
  );
}

/// `true` quando o passo 2 (data, dimensão, localização) está completo.
bool wizardScheduleIsComplete(ClientCreateJobWizardState state) {
  if (state.sizeEstimate == null) return false;
  if (state.locationLat == null || state.locationLng == null) return false;
  switch (state.dateMode) {
    case DateMode.fixed:
      return state.preferredDate != null;
    case DateMode.flexible:
      return true;
    case DateMode.availability:
      return availabilityTextError(state.availabilityText) == null;
  }
}

/// Primeiro passo do wizard que ainda precisa de alguma coisa do cliente;
/// com tudo preenchido, a revisão.
String wizardFirstIncompleteRoute(ClientCreateJobWizardState state) {
  if (state.serviceTypeId == null) return '/client/create-job';
  if (!wizardScheduleIsComplete(state)) return '/client/create-job/schedule';
  final description = state.description.trim();
  if (description.length < jobDescriptionMinLength ||
      description.length > jobDescriptionMaxLength) {
    return '/client/create-job/description';
  }
  return '/client/create-job/review';
}
