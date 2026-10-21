import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/client_job_next_step.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

JobRequest _job(
  String id,
  JobStatus status, {
  int proposals = 0,
  RescheduleStatus? reschedule,
  String? rescheduleBy,
  int createdDay = 1,
}) =>
    JobRequest(
      id: id,
      clientId: 'client',
      serviceTypeId: 's',
      addressText: '',
      locationLat: 0,
      locationLng: 0,
      description: '',
      status: status,
      proposalCount: proposals,
      rescheduleStatus: reschedule,
      rescheduleProposedBy: rescheduleBy,
      expiresAt: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, createdDay),
    );

void main() {
  test('Início mostra todos os pedidos em curso, o que precisa do cliente primeiro', () {
    final jobs = [
      _job('aberto', JobStatus.open, createdDay: 5),
      _job('marcado', JobStatus.confirmed),
      _job('concluido', JobStatus.completed),
      _job('cancelado', JobStatus.cancelled),
      _job('propostas', JobStatus.open, proposals: 2),
      _job('confirmar', JobStatus.awaitingConfirmation),
      _job('nova-data', JobStatus.confirmed,
          reschedule: RescheduleStatus.pending, rescheduleBy: 'worker'),
    ];
    expect(
      clientHomeActiveJobs(jobs).map((j) => j.id),
      ['confirmar', 'nova-data', 'propostas', 'marcado', 'aberto'],
    );
  });

  test('próximo passo de cada estado', () {
    expect(clientJobNextStepLabel(_job('a', JobStatus.open)),
        'À espera de propostas dos jardineiros.');
    expect(clientJobNextStepLabel(_job('a', JobStatus.open, proposals: 1)),
        'Tens 1 proposta para ver.');
    expect(clientJobNextStepLabel(_job('a', JobStatus.open, proposals: 3)),
        'Tens 3 propostas para ver.');
    expect(clientJobNextStepLabel(_job('a', JobStatus.awaitingConfirmation)),
        contains('Confirma'));
  });

  test('nova data: depende de quem a propôs', () {
    final fromWorker = _job('a', JobStatus.confirmed,
        reschedule: RescheduleStatus.pending, rescheduleBy: 'worker');
    final fromClient = _job('a', JobStatus.confirmed,
        reschedule: RescheduleStatus.pending, rescheduleBy: 'client');
    expect(clientJobNeedsAction(fromWorker), isTrue);
    expect(clientJobNextStepLabel(fromWorker), contains('Responde'));
    expect(clientJobNeedsAction(fromClient), isFalse);
    expect(clientJobNextStepLabel(fromClient), contains('À espera do jardineiro'));
  });
}
