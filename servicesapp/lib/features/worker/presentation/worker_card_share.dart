import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_links.dart';

/// Partilha do cartão público pelo próprio jardineiro (conta e
/// pré-visualização do cartão). O link leva `?src=link` e o QR `?src=qr`,
/// para o servidor separar as visitas (A7, migration 0059).
Future<void> shareWorkerPublicCard(String workerId) =>
    SharePlus.instance.share(
      ShareParams(
        text: 'Vê o meu perfil na ProJardim: '
            '${AppLinks.publicWorkerProfileUrl(workerId, source: 'link')}',
      ),
    );

/// Endereço codificado no QR do cartão.
String workerPublicCardQrUrl(String workerId) =>
    AppLinks.publicWorkerProfileUrl(workerId, source: 'qr');
