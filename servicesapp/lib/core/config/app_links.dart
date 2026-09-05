/// Domínio público da app — placeholder até haver um domínio real registado
/// (ver `docs/improvements.md`, "Nome próprio em português").
abstract final class AppLinks {
  const AppLinks._();

  static const String _publicDomain = 'https://projardim.pt';

  static String publicWorkerProfileUrl(String workerId) =>
      '$_publicDomain/w/$workerId';
}
