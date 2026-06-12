import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/enums.dart';
import 'job_model.dart';

class JobRepository {
  const JobRepository(this._client);

  final SupabaseClient _client;

  Future<String> createJob({
    required String clientId,
    required String serviceTypeId,
    required String addressText,
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
        .single();

    return result['id'] as String;
  }

  Future<String> uploadJobPhoto({
    required String jobId,
    required File file,
  }) async {
    final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1280,
      minHeight: 1280,
      quality: 72,
      format: CompressFormat.jpeg,
    );

    if (compressed == null) {
      throw Exception('Image compression failed for ${file.path}');
    }

    final storagePath = '$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage.from('job-photos').uploadBinary(
          storagePath,
          compressed,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    await _client.from('job_photos').insert({
      'job_id': jobId,
      'storage_path': storagePath,
    });

    return _client.storage.from('job-photos').getPublicUrl(storagePath);
  }

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

  Future<void> cancelJob(String jobId) async {
    await _client.from('job_requests').update({
      'status': JobStatus.cancelled.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', jobId);
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
}
