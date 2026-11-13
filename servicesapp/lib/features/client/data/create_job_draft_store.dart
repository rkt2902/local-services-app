import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/enums.dart';
import '../application/client_create_job_wizard_provider.dart';

/// Rascunho de "Criar pedido" guardado no dispositivo, por conta, para não
/// se perder ao fechar a app a meio (testes manuais de 12/11, TM-017).
///
/// Só um pedido normal: um pedido direto ("Pedir de novo" ou cartão) tem
/// prazos e reservas que não fazem sentido dias depois. As fotos ficam de
/// fora (são ficheiros temporários do telemóvel).
class CreateJobDraftStore {
  const CreateJobDraftStore();

  static String _key(String userId) => 'create_job_draft_$userId';

  Future<ClientCreateJobWizardState?> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      return createJobDraftFromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        now: DateTime.now(),
      );
    } catch (_) {
      await prefs.remove(_key(userId));
      return null;
    }
  }

  Future<void> save(String userId, ClientCreateJobWizardState state) async {
    final prefs = await SharedPreferences.getInstance();
    final json = createJobDraftToJson(state, now: DateTime.now());
    if (json == null) {
      await prefs.remove(_key(userId));
    } else {
      await prefs.setString(_key(userId), jsonEncode(json));
    }
  }
}

/// Um rascunho com mais de 7 dias já não é recuperado.
const createJobDraftMaxAge = Duration(days: 7);

/// `null` quando não há nada a guardar (vazio ou pedido direto).
Map<String, dynamic>? createJobDraftToJson(
  ClientCreateJobWizardState s, {
  required DateTime now,
}) {
  if (s.isDirectRequest) return null;
  final empty = s.serviceTypeId == null &&
      s.description.trim().isEmpty &&
      s.addressText.trim().isEmpty &&
      s.locationLat == null;
  if (empty) return null;
  return {
    'saved_at': now.toIso8601String(),
    'service_type_id': s.serviceTypeId,
    'date_mode': s.dateMode.name,
    'preferred_date': s.preferredDate?.toIso8601String(),
    'availability_text': s.availabilityText,
    'urgency': s.urgency.name,
    'size_estimate': s.sizeEstimate?.name,
    'address_text': s.addressText,
    'address_auto_filled': s.addressAutoFilled,
    'location_area': s.locationArea,
    'location_lat': s.locationLat,
    'location_lng': s.locationLng,
    'description': s.description,
  };
}

/// `null` quando é velho demais. Uma data fixa que já passou é apagada
/// (o cliente escolhe outra), o resto mantém-se.
ClientCreateJobWizardState? createJobDraftFromJson(
  Map<String, dynamic> j, {
  required DateTime now,
}) {
  final savedAt = DateTime.tryParse(j['saved_at'] as String? ?? '');
  if (savedAt == null || now.difference(savedAt) > createJobDraftMaxAge) {
    return null;
  }
  final today = DateTime(now.year, now.month, now.day);
  var preferred = DateTime.tryParse(j['preferred_date'] as String? ?? '');
  if (preferred != null && preferred.isBefore(today)) preferred = null;
  T? byName<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  return ClientCreateJobWizardState(
    serviceTypeId: j['service_type_id'] as String?,
    dateMode: byName(DateMode.values, j['date_mode']) ?? DateMode.flexible,
    preferredDate: preferred,
    availabilityText: j['availability_text'] as String? ?? '',
    urgency: byName(Urgency.values, j['urgency']) ?? Urgency.normal,
    sizeEstimate: byName(SizeEstimate.values, j['size_estimate']),
    addressText: j['address_text'] as String? ?? '',
    addressAutoFilled: j['address_auto_filled'] as bool? ?? false,
    locationArea: j['location_area'] as String?,
    locationLat: (j['location_lat'] as num?)?.toDouble(),
    locationLng: (j['location_lng'] as num?)?.toDouble(),
    description: j['description'] as String? ?? '',
  );
}
