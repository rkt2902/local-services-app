import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/picked_photo.dart';
import 'job_model.dart';
import '../../../core/config/storage_urls.dart';

class JobRepository {
  const JobRepository(this._client);

  final SupabaseClient _client;

  Future<String> createJob({
    required String clientId,
    required String serviceTypeId,
    required String addressText,
    String? locationArea,
    required double locationLat,
    required double locationLng,
    required DateMode dateMode,
    DateTime? preferredDate,
    String? availabilityText,
    Urgency? urgency,
    SizeEstimate? sizeEstimate,
    required String description,
  }) async {
    final payload = <String, dynamic>{
      'client_id': clientId,
      'service_type_id': serviceTypeId,
      'address_text': addressText,
      if (locationArea != null && locationArea.isNotEmpty)
        'location_area': locationArea,
      'location_lat': locationLat,
      'location_lng': locationLng,
      'description': description,
      'status': 'open',
      'date_mode': dateMode.value,
      if (preferredDate != null)
        'preferred_date': preferredDate.toIso8601String().substring(0, 10),
      if (availabilityText != null && availabilityText.isNotEmpty)
        'availability_text': availabilityText,
      if (urgency != null) 'urgency': urgency.value,
      if (sizeEstimate != null) 'size_estimate': sizeEstimate.value,
    };

    final result = await _client
        .from('job_requests')
        .insert(payload)
        .select('id')
        .maybeSingle();
    if (result == null) throw Exception('Job criado mas SELECT não devolveu dados.');
    return result['id'] as String;
  }

  Future<String> uploadJobPhoto({
    required String jobId,
    required String clientId,
    required XFile file,
  }) async {
    final photo = await photoBytesForUpload(file);

    final storagePath = '$clientId/$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage.from('job-photos').uploadBinary(
          storagePath,
          photo.bytes,
          fileOptions: FileOptions(
            contentType: photo.contentType,
            upsert: true,
          ),
        );

    await _client.from('job_photos').insert({
      'job_id': jobId,
      'storage_path': storagePath,
    });

    return _client.storage.from('job-photos').getPublicUrl(storagePath);
  }

  /// Foto de conclusão do worker (migration 0046). Vai para
  /// `job-photos/<worker_id>/<job_id>/`, a única pasta que a policy de
  /// upload e a validação de `mark_job_done` aceitam. Devolve o caminho no
  /// bucket, que se passa a `ProposalRepository.markJobCompleted`.
  /// Foto de "antes" ([before] = true, ao iniciar) ou de "depois" (ao
  /// concluir). O caminho tem de começar por `<worker>/<job>/` para as RPCs
  /// `start_job`/`mark_job_done` a aceitarem (migration 0052).
  Future<String> uploadWorkPhoto({
    required String jobId,
    required XFile file,
    required bool before,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Não autenticado');
    final photo = await photoBytesForUpload(file);
    final prefix = before ? 'before' : 'done';
    final storagePath =
        '$userId/$jobId/${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from('job-photos').uploadBinary(
          storagePath,
          photo.bytes,
          fileOptions: FileOptions(contentType: photo.contentType),
        );
    return storagePath;
  }

  /// "Iniciar trabalho" (migration 0052): a partir de 1h antes da hora.
  Future<void> startJob(String jobId, {List<String> photoPaths = const []}) async {
    await _client.rpc('start_job', params: {
      'p_job_id': jobId,
      'p_photo_paths': photoPaths,
    });
  }

  String jobPhotoPublicUrl(String storagePath) =>
      _client.storage.from('job-photos').getPublicUrl(storagePath);

  Future<List<JobRequest>> fetchJobsInRadius({
    required double workerLat,
    required double workerLng,
    required int radiusKm,
  }) async {
    final data = await _client.rpc('get_jobs_in_radius', params: {
      'worker_lat': workerLat,
      'worker_lng': workerLng,
      'radius_km': radiusKm,
    });
    return (data as List).map((e) => JobRequest.fromJson(e)).toList();
  }

  Future<List<JobRequest>> fetchClientJobs(String clientId) async {
    final data = await _client
        .from('job_requests')
        .select()
        .eq('client_id', clientId)
        .order('created_at', ascending: false);
    return (data as List).map((e) => JobRequest.fromJson(e)).toList();
  }

  Future<String?> cancelJob({
    required String jobId,
    required String reason,
    String? reasonDetail,
    bool? clientWantsReopen,
  }) async {
    final params = <String, dynamic>{
      'p_job_id': jobId,
      'p_reason': reason,
      'p_reason_detail': reasonDetail,
    };
    if (clientWantsReopen != null) {
      params['p_client_wants_reopen'] = clientWantsReopen;
    }
    final result = await _client.rpc('cancel_job', params: params);
    return result as String?;
  }

  /// Editar um pedido ainda `open` (RPC `update_job_request`, migration
  /// 0049). Só o próprio cliente: a identidade vem de `auth.uid()` dentro
  /// da função, nunca daqui. Os jardineiros com proposta pendente são
  /// avisados pelo servidor. As fotos não mudam.
  Future<void> updateJobRequest({
    required String jobId,
    required String description,
    required DateMode dateMode,
    DateTime? preferredDate,
    String? availabilityText,
    required String addressText,
    required double locationLat,
    required double locationLng,
    String? locationArea,
  }) async {
    await _client.rpc('update_job_request', params: {
      'p_job_id': jobId,
      'p_description': description,
      'p_date_mode': dateMode.value,
      'p_preferred_date': dateMode == DateMode.fixed && preferredDate != null
          ? preferredDate.toIso8601String().substring(0, 10)
          : null,
      'p_availability_text':
          dateMode == DateMode.availability ? availabilityText : null,
      'p_address_text': addressText,
      'p_location_lat': locationLat,
      'p_location_lng': locationLng,
      'p_location_area':
          locationArea == null || locationArea.isEmpty ? null : locationArea,
    });
  }

  Future<void> proposeReschedule({
    required String jobId,
    required DateTime newDate,
    String? newTime,
    required bool newFlexible,
  }) async {
    await _client.rpc('propose_reschedule', params: {
      'p_job_id': jobId,
      'p_new_date': newDate.toIso8601String().split('T')[0],
      'p_new_time': newTime,
      'p_new_flexible': newFlexible,
    });
  }

  Future<void> acceptReschedule(String jobId) async {
    await _client.rpc('accept_reschedule', params: {'p_job_id': jobId});
  }

  Future<void> rejectReschedule(String jobId) async {
    await _client.rpc('reject_reschedule', params: {'p_job_id': jobId});
  }

  Future<List<String>> fetchJobPhotos(String jobId) async {
    final data = await _client
        .from('job_photos')
        .select('storage_path')
        .eq('job_id', jobId);
    return (data as List).map((e) {
      final path = e['storage_path'] as String;
      return _client.storage.from('job-photos').getPublicUrl(path);
    }).toList();
  }

  /// RPC e não SELECT direto (migration 0043): o worker só lê `job_requests`
  /// por RLS quando é o aceite. Para oportunidades e propostas pendentes,
  /// `get_job_by_id` devolve a versão com a zona aproximada em vez da
  /// morada exata. O cliente e o worker aceite recebem tudo.
  Future<JobRequest?> fetchJobById(String jobId) async {
    final data = await _client
        .rpc('get_job_by_id', params: {'p_job_id': jobId})
        .maybeSingle();
    if (data == null) return null;
    return JobRequest.fromJson(data);
  }

  /// Nome/avatar do cliente para a oportunidade (job `open`, ainda sem
  /// proposta aceite) — a policy de SELECT de `profiles` só deixa um worker
  /// ler o perfil do cliente quando já tem proposta `accepted` nesse job,
  /// por isso um SELECT direto a `profiles` falha aqui (RLS, não bug de
  /// dados). RPC `get_open_job_client_identity` (migration 0040, NÃO
  /// aplicada) expõe só estas duas colunas, com a mesma condição da policy
  /// "Worker vê jobs abertos" (`status = 'open'`) — nunca o telefone.
  Future<Map<String, String>> fetchOpenJobClientIdentity(String jobId) async {
    final data = await _client
        .rpc('get_open_job_client_identity', params: {'p_job_id': jobId})
        .maybeSingle();
    if (data == null) return {'full_name': '', 'avatar_url': ''};
    return {
      'full_name': data['client_name'] as String? ?? '',
      'avatar_url':
          StorageUrls.trustedOrEmpty(data['client_avatar_url'] as String?),
    };
  }
}
