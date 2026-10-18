import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/enums.dart';
import '../../auth/application/auth_providers.dart';

/// Marca "não mexer" do `copyWith` para campos que podem voltar a `null`.
const _unset = Object();

/// Dados acumulados ao longo do wizard de 3 passos de criação de pedido.
///
/// Existe para que o utilizador não perca a seleção de um passo ao voltar
/// atrás para outro (cada ecrã lê o seu `initialX` a partir daqui e escreve
/// de volta em `onContinue`/`onReviewAndPublish`) — mesmo padrão já usado em
/// `pending_signup_provider.dart` para o fluxo de registo.
class ClientCreateJobWizardState {
  const ClientCreateJobWizardState({
    this.serviceTypeId,
    this.dateMode = DateMode.flexible,
    this.preferredDate,
    this.urgency = Urgency.normal,
    this.sizeEstimate,
    this.addressText = '',
    this.addressAutoFilled = false,
    this.locationArea,
    this.locationLat,
    this.locationLng,
    this.description = '',
    this.photos = const [],
  });

  final String? serviceTypeId;

  final DateMode dateMode;
  final DateTime? preferredDate;
  final Urgency urgency;
  final SizeEstimate? sizeEstimate;

  final String addressText;

  /// `true` quando [addressText] veio do reverse geocoding do pin e não foi
  /// escrita/alterada à mão: ao mover o pin, a morada é substituída.
  final bool addressAutoFilled;
  final String? locationArea;
  final double? locationLat;
  final double? locationLng;

  final String description;
  final List<XFile> photos;

  ClientCreateJobWizardState copyWith({
    String? serviceTypeId,
    DateMode? dateMode,
    DateTime? preferredDate,
    Urgency? urgency,
    SizeEstimate? sizeEstimate,
    String? addressText,
    bool? addressAutoFilled,
    Object? locationArea = _unset,
    double? locationLat,
    double? locationLng,
    String? description,
    List<XFile>? photos,
  }) {
    return ClientCreateJobWizardState(
      serviceTypeId: serviceTypeId ?? this.serviceTypeId,
      dateMode: dateMode ?? this.dateMode,
      preferredDate: preferredDate ?? this.preferredDate,
      urgency: urgency ?? this.urgency,
      sizeEstimate: sizeEstimate ?? this.sizeEstimate,
      addressText: addressText ?? this.addressText,
      addressAutoFilled: addressAutoFilled ?? this.addressAutoFilled,
      // `null` explícito apaga a localidade (o pin mudou e ainda não há
      // localidade nova); omitido mantém a atual.
      locationArea: identical(locationArea, _unset)
          ? this.locationArea
          : locationArea as String?,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      description: description ?? this.description,
      photos: photos ?? this.photos,
    );
  }
}

class ClientCreateJobWizardNotifier
    extends Notifier<ClientCreateJobWizardState> {
  @override
  ClientCreateJobWizardState build() {
    // Rascunho por utilizador: ao terminar sessão ou trocar de conta o
    // provider reconstrói-se e o rascunho do anterior desaparece.
    ref.watch(currentUserIdProvider);
    return const ClientCreateJobWizardState();
  }

  void setService(String serviceTypeId) {
    state = state.copyWith(serviceTypeId: serviceTypeId);
  }

  void setSchedule({
    required DateMode dateMode,
    DateTime? preferredDate,
    required Urgency urgency,
    required SizeEstimate sizeEstimate,
  }) {
    state = ClientCreateJobWizardState(
      serviceTypeId: state.serviceTypeId,
      dateMode: dateMode,
      preferredDate: preferredDate,
      urgency: urgency,
      sizeEstimate: sizeEstimate,
      addressText: state.addressText,
      addressAutoFilled: state.addressAutoFilled,
      locationArea: state.locationArea,
      locationLat: state.locationLat,
      locationLng: state.locationLng,
      description: state.description,
      photos: state.photos,
    );
  }

  void setLocation({
    required String addressText,
    required bool addressAutoFilled,
    required String? locationArea,
    required double locationLat,
    required double locationLng,
  }) {
    state = state.copyWith(
      addressText: addressText,
      addressAutoFilled: addressAutoFilled,
      locationArea: locationArea,
      locationLat: locationLat,
      locationLng: locationLng,
    );
  }

  void setDescriptionAndPhotos({
    required String description,
    required List<XFile> photos,
  }) {
    state = state.copyWith(description: description, photos: photos);
  }

  void reset() => state = const ClientCreateJobWizardState();
}

final clientCreateJobWizardProvider = NotifierProvider<
    ClientCreateJobWizardNotifier, ClientCreateJobWizardState>(
  ClientCreateJobWizardNotifier.new,
);
