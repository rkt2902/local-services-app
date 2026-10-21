import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/worker/presentation/worker_jobs_screen.dart';

void main() {
  String? label(String entry, String? job) =>
      workerBoardJobPresentation(entry, job)?.label;

  test('sem job_status (BD antiga) usa o estado da proposta', () {
    expect(label('accepted', null), isNull);
  });

  test('proposta aceite mostra o estado do trabalho', () {
    expect(label('accepted', 'confirmed'), 'Agendado');
    expect(label('accepted', 'awaiting_confirmation'), 'À espera do cliente');
    expect(label('accepted', 'completed'), 'Concluído');
    expect(label('accepted', 'cancelled'), 'Cancelado');
  });

  test('pedido fechado sem escolha', () {
    expect(label('rejected', 'cancelled'), 'Cancelado');
    expect(label('pending', 'no_response'), 'Expirado');
  });

  test('não escolhida num pedido que seguiu com outro fica com o estado da proposta', () {
    expect(label('rejected', 'confirmed'), isNull);
    expect(label('pending', 'open'), isNull);
  });
}
