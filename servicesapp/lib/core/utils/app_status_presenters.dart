import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/core/theme/app_status_presentation.dart';

import '../constants/enums.dart';

extension JobStatusPresentationExtension on JobStatus {
  AppStatusPresentation presentation({
    int proposalCount = 0,
  }) {
    switch (this) {
      case JobStatus.open:
        if (proposalCount <= 0) {
          return const AppStatusPresentation(
            label: 'À espera de proposta',
            color: AppStatusColor.waiting,
          );
        }

        return AppStatusPresentation(
          label: proposalCount == 1
              ? '1 proposta'
              : '$proposalCount propostas',
          color: AppStatusColor.waiting,
        );

      case JobStatus.awaitingConfirmation:
        return const AppStatusPresentation(
          label: 'A aguardar confirmação',
          color: AppStatusColor.info,
        );

      case JobStatus.confirmed:
        return const AppStatusPresentation(
          label: 'Confirmado',
          color: AppStatusColor.success,
        );

      case JobStatus.completed:
        return const AppStatusPresentation(
          label: 'Concluído',
          color: AppStatusColor.success,
        );

      case JobStatus.noResponse:
        return const AppStatusPresentation(
          label: 'Sem resposta',
          color: AppStatusColor.neutral,
        );

      case JobStatus.cancelled:
        return const AppStatusPresentation(
          label: 'Cancelado',
          color: AppStatusColor.cancelled,
        );
    }
  }
}

extension ProposalStatusPresentationExtension on ProposalStatus {
  AppStatusPresentation get presentation {
    switch (this) {
      case ProposalStatus.pending:
        return const AppStatusPresentation(
          label: 'Aguarda resposta',
          color: AppStatusColor.waiting,
        );

      case ProposalStatus.accepted:
        return const AppStatusPresentation(
          label: 'Aceite',
          color: AppStatusColor.success,
        );

      case ProposalStatus.rejected:
        return const AppStatusPresentation(
          label: 'Não selecionada',
          color: AppStatusColor.neutral,
        );

      case ProposalStatus.superseded:
        return const AppStatusPresentation(
          label: 'Substituída',
          color: AppStatusColor.neutral,
        );
    }
  }
}

extension HelpAcceptanceStatusPresentationExtension
    on HelpAcceptanceStatus {
  AppStatusPresentation get presentation {
    switch (this) {
      case HelpAcceptanceStatus.pending:
        return const AppStatusPresentation(
          label: 'À espera de decisão',
          color: AppStatusColor.waiting,
        );

      case HelpAcceptanceStatus.accepted:
        return const AppStatusPresentation(
          label: 'Na equipa',
          color: AppStatusColor.success,
        );

      case HelpAcceptanceStatus.rejected:
        return const AppStatusPresentation(
          label: 'Não selecionado',
          color: AppStatusColor.neutral,
        );

      case HelpAcceptanceStatus.cancelled:
        return const AppStatusPresentation(
          label: 'Desististe',
          color: AppStatusColor.neutral,
        );
    }
  }
}

extension HelpRequestStatusPresentationExtension on HelpRequestStatus {
  AppStatusPresentation get presentation {
    switch (this) {
      case HelpRequestStatus.pendingApproval:
        return const AppStatusPresentation(
          label: 'A aguardar aprovação',
          color: AppStatusColor.waiting,
        );

      case HelpRequestStatus.open:
        return const AppStatusPresentation(
          label: 'A recrutar',
          color: AppStatusColor.info,
        );

      case HelpRequestStatus.filled:
        return const AppStatusPresentation(
          label: 'Equipa completa',
          color: AppStatusColor.success,
        );

      case HelpRequestStatus.cancelled:
        return const AppStatusPresentation(
          label: 'Vaga cancelada',
          color: AppStatusColor.cancelled,
        );
    }
  }
}

extension RescheduleStatusPresentationExtension on RescheduleStatus {
  AppStatusPresentation get presentation {
    switch (this) {
      case RescheduleStatus.pending:
        return const AppStatusPresentation(
          label: 'Remarcação pendente',
          color: AppStatusColor.waiting,
        );

      case RescheduleStatus.accepted:
        return const AppStatusPresentation(
          label: 'Remarcação aceite',
          color: AppStatusColor.success,
        );

      case RescheduleStatus.rejected:
        return const AppStatusPresentation(
          label: 'Remarcação recusada',
          color: AppStatusColor.neutral,
        );
    }
  }
}

const AppStatusPresentation urgentStatusPresentation =
    AppStatusPresentation(
  label: 'Urgente',
  color: AppStatusColor.cancelled,
);
