import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/client_job_next_step.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

JobRequest _job(JobStatus status) => JobRequest(
      id: 'j1',
      clientId: 'c1',
      serviceTypeId: 's1',
      addressText: 'Rua A, Braga',
      locationLat: 0,
      locationLng: 0,
      description: 'Cortar a relva',
      status: status,
      proposalCount: 1,
      dateMode: DateMode.flexible,
      expiresAt: DateTime(2026, 11, 20),
      createdAt: DateTime(2026, 11, 13),
    );

void main() {
  test('ajudantes por aprovar aparecem em "Precisa de ti"', () {
    final job = _job(JobStatus.confirmed);
    expect(clientJobAttention(job), isNull);
    final kind = clientJobAttention(job, pendingHelperApproval: true);
    expect(kind, ClientJobAttention.approveHelpers);
    expect(clientJobAttentionTitle(kind!, job), 'Aprovar ajudantes');
  });

  test('só em trabalhos marcados', () {
    expect(
      clientJobAttention(_job(JobStatus.open), pendingHelperApproval: true),
      ClientJobAttention.seeProposals,
    );
  });
}
