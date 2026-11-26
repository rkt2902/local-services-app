// Estatísticas para parceiros (`admin_partner_stats`, 0084): quantos
// Profissionais há, quantos estão ativos, quanto combustível declaram e
// onde, e quantos trabalhos se concluem por mês.

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double _double(Object? v) => (v as num?)?.toDouble() ?? 0;

class AdminFuelTotal {
  const AdminFuelTotal({
    required this.id,
    required this.name,
    required this.workers,
    required this.liters,
  });

  final String id;
  final String name;

  /// Profissionais que declararam este tipo.
  final int workers;

  /// Soma dos litros por mês declarados.
  final double liters;
}

class AdminDistrictStats {
  const AdminDistrictStats({
    required this.district,
    required this.registered,
    required this.active,
    required this.answered,
    required this.litersByFuel,
  });

  final String district;
  final int registered;
  final int active;
  final int answered;
  final Map<String, double> litersByFuel;

  double get totalLiters => litersByFuel.values.fold(0, (a, b) => a + b);
}

class AdminCompletedMonth {
  const AdminCompletedMonth({required this.month, required this.byCategory});

  /// 'AAAA-MM'.
  final String month;
  final Map<String, int> byCategory;

  int get total => byCategory.values.fold(0, (a, b) => a + b);
}

class AdminPartnerStats {
  const AdminPartnerStats({
    required this.months,
    required this.registered,
    required this.active,
    required this.pro,
    required this.proPlus,
    required this.answered,
    required this.fuel,
    required this.districts,
    required this.completed,
  });

  final int months;
  final int registered;
  final int active;
  final int pro;
  final int proPlus;
  final int answered;
  final List<AdminFuelTotal> fuel;
  final List<AdminDistrictStats> districts;

  /// Um por mês, do mais antigo ao atual, incluindo meses sem trabalhos.
  final List<AdminCompletedMonth> completed;

  double get totalLiters => fuel.fold(0, (a, f) => a + f.liters);

  /// Litros se quem não respondeu gastar como quem respondeu; `null` sem
  /// respostas.
  double? get estimatedLitersAll =>
      answered == 0 ? null : totalLiters * registered / answered;

  factory AdminPartnerStats.fromJson(
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final w = (json['workers'] as Map?)?.cast<String, dynamic>() ?? const {};
    final s = (json['survey'] as Map?)?.cast<String, dynamic>() ?? const {};
    final months = _int(json['months']).clamp(1, 24);

    final byMonth = <String, Map<String, int>>{};
    for (final raw in (json['completed'] as List? ?? const [])) {
      final m = (raw as Map).cast<String, dynamic>();
      byMonth.putIfAbsent(m['month'] as String, () => {})[
          m['category'] as String] = _int(m['count']);
    }
    final today = now ?? DateTime.now();
    final completed = [
      for (var i = months - 1; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month - i);
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
          return AdminCompletedMonth(
              month: key, byCategory: byMonth[key] ?? const {});
        }(),
    ];

    return AdminPartnerStats(
      months: months,
      registered: _int(w['registered']),
      active: _int(w['active_30d']),
      pro: _int(w['pro']),
      proPlus: _int(w['pro_plus']),
      answered: _int(s['answered']),
      fuel: [
        for (final raw in (json['fuel'] as List? ?? const []))
          () {
            final f = (raw as Map).cast<String, dynamic>();
            return AdminFuelTotal(
              id: f['id'] as String,
              name: f['name'] as String,
              workers: _int(f['workers']),
              liters: _double(f['liters']),
            );
          }(),
      ],
      districts: [
        for (final raw in (json['districts'] as List? ?? const []))
          () {
            final d = (raw as Map).cast<String, dynamic>();
            final liters =
                (d['liters'] as Map?)?.cast<String, dynamic>() ?? const {};
            return AdminDistrictStats(
              district: d['district'] as String,
              registered: _int(d['registered']),
              active: _int(d['active_30d']),
              answered: _int(d['answered']),
              litersByFuel: {
                for (final e in liters.entries) e.key: _double(e.value),
              },
            );
          }(),
      ],
      completed: completed,
    );
  }
}

/// "38%" de [part] em [whole]; "—" sem base.
String adminPercent(int part, int whole) =>
    whole <= 0 ? '—' : '${(part * 100 / whole).round()}%';

/// Litros com separador de milhares: "1 240 L".
String adminLitersLabel(double liters) {
  final n = liters.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < n.length; i++) {
    if (i > 0 && (n.length - i) % 3 == 0) buf.write(' ');
    buf.write(n[i]);
  }
  return '$buf L';
}

const _monthNames = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// '2026-11' → 'nov 2026'.
String adminMonthLabel(String month) {
  final parts = month.split('-');
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  if (m < 1 || m > 12) return month;
  return '${_monthNames[m - 1]} ${parts[0]}';
}
