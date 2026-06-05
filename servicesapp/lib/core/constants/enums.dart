enum JobStatus {
  open,
  proposalReceived,
  confirmed,
  completed,
  noResponse,
  cancelled;

  String get value => switch (this) {
        JobStatus.open => 'open',
        JobStatus.proposalReceived => 'proposal_received',
        JobStatus.confirmed => 'confirmed',
        JobStatus.completed => 'completed',
        JobStatus.noResponse => 'no_response',
        JobStatus.cancelled => 'cancelled',
      };

  static JobStatus fromValue(String value) => switch (value) {
        'open' => JobStatus.open,
        'proposal_received' => JobStatus.proposalReceived,
        'confirmed' => JobStatus.confirmed,
        'completed' => JobStatus.completed,
        'no_response' => JobStatus.noResponse,
        'cancelled' => JobStatus.cancelled,
        _ => throw ArgumentError('Unknown JobStatus: $value'),
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
}
