import '../../../core/constants/enums.dart';
import '../../../core/config/storage_urls.dart';
import 'worker_showcase.dart';

/// Perfil público mínimo do worker — fonte: view `worker_public_card`
/// (migration 0033, definer-style, GRANT a `anon`). Sem telefone nem
/// localização exata.
class WorkerPublicCard {
  final String workerId;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final String locationName;
  final List<String> serviceNames;
  final double avgRating;
  final int ratingCount;

  /// Destaques e links (0051); vazios antes de a migration ser aplicada.
  final List<String> highlights;
  final List<WorkerSocialLink> socialLinks;

  /// Serviços do jardineiro por id (0059): o passo 1 do pedido pelo cartão
  /// só mostra estes. Vazio antes da 0059 ou sem serviços.
  final List<String> serviceTypeIds;

  /// Acesso às funcionalidades do cartão, decidido no servidor (0059).
  /// Sem a coluna conta como ligado.
  final bool canUsePublicCard;
  final bool canReceiveDirectRequests;

  /// Comentário mais recente com 4 ou 5 estrelas, primeiro nome de quem
  /// avaliou e data.
  final String? latestReviewComment;
  final String? latestReviewAuthor;
  final DateTime? latestReviewAt;

  /// Plano em vigor, para o selo (0067). Grátis antes da 0067.
  final WorkerPlanTier planTier;

  const WorkerPublicCard({
    required this.workerId,
    required this.fullName,
    this.avatarUrl,
    this.bio,
    required this.locationName,
    required this.serviceNames,
    required this.avgRating,
    required this.ratingCount,
    this.highlights = const [],
    this.socialLinks = const [],
    this.serviceTypeIds = const [],
    this.canUsePublicCard = true,
    this.canReceiveDirectRequests = true,
    this.latestReviewComment,
    this.latestReviewAuthor,
    this.latestReviewAt,
    this.planTier = WorkerPlanTier.free,
  });

  factory WorkerPublicCard.fromJson(Map<String, dynamic> json) =>
      WorkerPublicCard(
        workerId: json['worker_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        avatarUrl: StorageUrls.trustedOrNull(json['avatar_url'] as String?),
        bio: json['bio'] as String?,
        locationName: json['location_name'] as String? ?? '',
        serviceNames: List<String>.from(json['service_names'] as List? ?? []),
        avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
        highlights: highlightsFromJson(json['highlights']),
        socialLinks: WorkerSocialLink.listFromJson(json['social_links']),
        serviceTypeIds:
            List<String>.from(json['service_type_ids'] as List? ?? const []),
        canUsePublicCard: json['can_use_public_card'] as bool? ?? true,
        canReceiveDirectRequests:
            json['can_receive_direct_requests'] as bool? ?? true,
        latestReviewComment: json['latest_review_comment'] as String?,
        latestReviewAuthor: json['latest_review_author'] as String?,
        latestReviewAt: json['latest_review_at'] != null
            ? DateTime.parse(json['latest_review_at'] as String)
            : null,
        planTier: WorkerPlanTier.fromValue(json['plan_tier'] as String?),
      );
}
