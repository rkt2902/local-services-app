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
    this.availabilityText = '',
    this.urgency = Urgency.normal,
    this.sizeEstimate,
    this.addressText = '',
    this.addressAutoFilled = false,
    this.locationArea,
    this.locationLat,
    this.locationLng,
    this.description = '',
    this.photos = const [],
    this.directSourceJobId,
    this.directWorkerName = '',
    this.directWorkerAvatarUrl = '',
    this.directCardWorkerId,
    this.directShowAllServices = false,
    this.directAutoRelease = true,
    this.cardVisitId,
  });

  final String? serviceTypeId;

  final DateMode dateMode;
  final DateTime? preferredDate;

  /// Texto livre de disponibilidade (`DateMode.availability`), ex.:
  /// "Sábados de manhã". Vazio nos outros modos.
  final String availabilityText;
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

  /// "Pedir de novo" (migration 0057): trabalho concluído de onde vem o
  /// pedido. Com isto, o servidor reserva o pedido ao jardineiro desse
  /// trabalho durante 24 horas. `null` num pedido normal.
  final String? directSourceJobId;

  /// Nome e foto do jardineiro escolhido, só para a faixa da revisão.
  final String directWorkerName;
  final String directWorkerAvatarUrl;

  /// Pedido pelo cartão público `/w/:id` (A7, migration 0059): o
  /// jardineiro a quem o pedido vai primeiro. O servidor valida-o; o
  /// cliente continua a ser sempre `auth.uid()`.
  final String? directCardWorkerId;

  /// Pedido pelo cartão: o passo 1 mostra só os serviços do jardineiro,
  /// até o cliente escolher "Ver todos os serviços" (fica `true`).
  final bool directShowAllServices;

  /// Interruptor do passo 4 "Se não puder, mostrar a outros jardineiros".
  /// `false`: depois de recusa ou fim do prazo o pedido fica parado até o
  /// cliente decidir.
  final bool directAutoRelease;

  /// Visita ao cartão que trouxe este pedido (tracking do QR/link).
  final String? cardVisitId;

  bool get isCardRequest => directCardWorkerId != null;

  bool get isDirectRequest => directSourceJobId != null || isCardRequest;

  ClientCreateJobWizardState copyWith({
    String? serviceTypeId,
    DateMode? dateMode,
    DateTime? preferredDate,
    String? availabilityText,
    Urgency? urgency,
    SizeEstimate? sizeEstimate,
    String? addressText,
    bool? addressAutoFilled,
    Object? locationArea = _unset,
    double? locationLat,
    double? locationLng,
    String? description,
    List<XFile>? photos,
    bool? directShowAllServices,
    bool? directAutoRelease,
  }) {
    return ClientCreateJobWizardState(
      serviceTypeId: serviceTypeId ?? this.serviceTypeId,
      dateMode: dateMode ?? this.dateMode,
      preferredDate: preferredDate ?? this.preferredDate,
      availabilityText: availabilityText ?? this.availabilityText,
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
      directSourceJobId: directSourceJobId,
      directWorkerName: directWorkerName,
      directWorkerAvatarUrl: directWorkerAvatarUrl,
      directCardWorkerId: directCardWorkerId,
      directShowAllServices:
          directShowAllServices ?? this.directShowAllServices,
      directAutoRelease: directAutoRelease ?? this.directAutoRelease,
      cardVisitId: cardVisitId,
    );
  }

  /// O mesmo rascunho como pedido normal, para todos os jardineiros.
  ClientCreateJobWizardState withoutDirectWorker() => ClientCreateJobWizardState(
        serviceTypeId: serviceTypeId,
        dateMode: dateMode,
        preferredDate: preferredDate,
        availabilityText: availabilityText,
        urgency: urgency,
        sizeEstimate: sizeEstimate,
        addressText: addressText,
        addressAutoFilled: addressAutoFilled,
        locationArea: locationArea,
        locationLat: locationLat,
        locationLng: locationLng,
        description: description,
        photos: photos,
      );
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
    String availabilityText = '',
    required Urgency urgency,
    required SizeEstimate sizeEstimate,
  }) {
    state = ClientCreateJobWizardState(
      serviceTypeId: state.serviceTypeId,
      dateMode: dateMode,
      preferredDate: preferredDate,
      availabilityText: availabilityText,
      urgency: urgency,
      sizeEstimate: sizeEstimate,
      addressText: state.addressText,
      addressAutoFilled: state.addressAutoFilled,
      locationArea: state.locationArea,
      locationLat: state.locationLat,
      locationLng: state.locationLng,
      description: state.description,
      photos: state.photos,
      directSourceJobId: state.directSourceJobId,
      directWorkerName: state.directWorkerName,
      directWorkerAvatarUrl: state.directWorkerAvatarUrl,
      directCardWorkerId: state.directCardWorkerId,
      directShowAllServices: state.directShowAllServices,
      directAutoRelease: state.directAutoRelease,
      cardVisitId: state.cardVisitId,
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

  /// Começa o wizard já preenchido (ex.: "Publicar de novo" a partir de um
  /// pedido antigo, ver `republishWizardState`).
  void startFrom(ClientCreateJobWizardState draft) => state = draft;

  /// Passo 4 do pedido direto: o que acontece se o jardineiro não puder.
  void setDirectAutoRelease(bool value) {
    state = state.copyWith(directAutoRelease: value);
  }

  /// "Ver todos os serviços" no passo 1 de um pedido pelo cartão: o pedido
  /// continua a ir primeiro para o mesmo jardineiro.
  void showAllServices() {
    state = state.copyWith(directShowAllServices: true);
  }

  /// "Criar pedido" a partir do Início, da aba Pedidos ou do botão central:
  /// mantém o rascunho, mas um "Pedir de novo" abandonado deixa de ir só
  /// para aquele jardineiro.
  void clearDirectWorker() {
    if (state.isDirectRequest) state = state.withoutDirectWorker();
  }

  void reset() => state = const ClientCreateJobWizardState();
}

final clientCreateJobWizardProvider = NotifierProvider<
    ClientCreateJobWizardNotifier, ClientCreateJobWizardState>(
  ClientCreateJobWizardNotifier.new,
);
