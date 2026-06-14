enum JobStatus {
  open,
  confirmed,
  awaitingConfirmation,
  completed,
  noResponse,
  cancelled;

  String get value => switch (this) {
        JobStatus.open => 'open',
        JobStatus.confirmed => 'confirmed',
        JobStatus.awaitingConfirmation => 'awaiting_confirmation',
        JobStatus.completed => 'completed',
        JobStatus.noResponse => 'no_response',
        JobStatus.cancelled => 'cancelled',
      };

  static JobStatus fromValue(String value) => switch (value) {
        'open' => JobStatus.open,
        'proposal_received' => JobStatus.open,
        'confirmed' => JobStatus.confirmed,
        'awaiting_confirmation' => JobStatus.awaitingConfirmation,
        'completed' => JobStatus.completed,
        'no_response' => JobStatus.noResponse,
        'cancelled' => JobStatus.cancelled,
        _ => throw ArgumentError('Unknown JobStatus: $value'),
      };

  static JobStatus fromString(String value) => fromValue(value);
}

enum DateMode {
  fixed,
  flexible,
  availability;

  String get value => switch (this) {
        DateMode.fixed => 'fixed',
        DateMode.flexible => 'flexible',
        DateMode.availability => 'availability',
      };

  static DateMode fromString(String value) => switch (value) {
        'fixed' => DateMode.fixed,
        'flexible' => DateMode.flexible,
        'availability' => DateMode.availability,
        _ => throw ArgumentError('Unknown DateMode: $value'),
      };
}

enum ProposalStatus {
  pending,
  accepted,
  rejected,
  superseded;

  String get value => switch (this) {
        ProposalStatus.pending => 'pending',
        ProposalStatus.accepted => 'accepted',
        ProposalStatus.rejected => 'rejected',
        ProposalStatus.superseded => 'superseded',
      };

  static ProposalStatus fromValue(String value) => switch (value) {
        'pending' => ProposalStatus.pending,
        'accepted' => ProposalStatus.accepted,
        'rejected' => ProposalStatus.rejected,
        'superseded' => ProposalStatus.superseded,
        _ => throw ArgumentError('Unknown ProposalStatus: $value'),
      };

  static ProposalStatus fromString(String value) => fromValue(value);
}

enum UserRole {
  client,
  worker;

  String get value => switch (this) {
        UserRole.client => 'client',
        UserRole.worker => 'worker',
      };

  static UserRole fromValue(String value) => switch (value) {
        'client' => UserRole.client,
        'worker' => UserRole.worker,
        _ => throw ArgumentError('Unknown UserRole: $value'),
      };

  static UserRole fromString(String value) => fromValue(value);
}

enum HelpRequestStatus {
  open,
  filled,
  cancelled;

  String get value => switch (this) {
        HelpRequestStatus.open => 'open',
        HelpRequestStatus.filled => 'filled',
        HelpRequestStatus.cancelled => 'cancelled',
      };

  static HelpRequestStatus fromValue(String value) => switch (value) {
        'open' => HelpRequestStatus.open,
        'filled' => HelpRequestStatus.filled,
        'cancelled' => HelpRequestStatus.cancelled,
        _ => throw ArgumentError('Unknown HelpRequestStatus: $value'),
      };

  static HelpRequestStatus fromString(String value) => fromValue(value);
}

enum HelpAcceptanceStatus {
  accepted,
  cancelled;

  String get value => switch (this) {
        HelpAcceptanceStatus.accepted => 'accepted',
        HelpAcceptanceStatus.cancelled => 'cancelled',
      };

  static HelpAcceptanceStatus fromValue(String value) => switch (value) {
        'accepted' => HelpAcceptanceStatus.accepted,
        'cancelled' => HelpAcceptanceStatus.cancelled,
        _ => throw ArgumentError('Unknown HelpAcceptanceStatus: $value'),
      };

  static HelpAcceptanceStatus fromString(String value) => fromValue(value);
}

enum Urgency {
  normal,
  urgent;

  String get value => switch (this) {
        Urgency.normal => 'normal',
        Urgency.urgent => 'urgent',
      };

  static Urgency fromValue(String value) => switch (value) {
        'normal' => Urgency.normal,
        'urgent' => Urgency.urgent,
        _ => throw ArgumentError('Unknown Urgency: $value'),
      };

  static Urgency fromString(String value) => fromValue(value);
}

enum SizeEstimate {
  small,
  medium,
  large;

  String get value => switch (this) {
        SizeEstimate.small => 'small',
        SizeEstimate.medium => 'medium',
        SizeEstimate.large => 'large',
      };

  static SizeEstimate fromValue(String value) => switch (value) {
        'small' => SizeEstimate.small,
        'medium' => SizeEstimate.medium,
        'large' => SizeEstimate.large,
        _ => throw ArgumentError('Unknown SizeEstimate: $value'),
      };

  static SizeEstimate fromString(String value) => fromValue(value);
}
