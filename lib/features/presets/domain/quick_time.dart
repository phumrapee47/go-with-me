/// One chip of the time row (F-15, Q8). [at] null = "ตอนนี้เลย".
class TimeOption {
  const TimeOption(this.at);
  final DateTime? at;

  bool get isNow => at == null;

  /// Stable id, also used to remember the last choice: minutes since midnight or -1 for now.
  int get minutes => at == null ? -1 : at!.hour * 60 + at!.minute;

  String get hm => at == null ? '' : '${at!.hour.toString().padLeft(2, '0')}:${at!.minute.toString().padLeft(2, '0')}';
}

/// Q8: "ตอนนี้เลย" + fixed 17:30 and 18:00 of today. A fixed time that has already passed is dropped;
/// if fewer than [minOptions] remain, the list is filled with the next 30-minute slots after [now]
/// (rounded UP; a slot equal to an existing one is skipped). No learning of user behaviour.
List<TimeOption> quickTimeOptions(DateTime now, {int minOptions = 3}) {
  final today = DateTime(now.year, now.month, now.day);
  final fixed = [today.add(const Duration(hours: 17, minutes: 30)), today.add(const Duration(hours: 18))];
  final times = <DateTime>[for (final t in fixed) if (t.isAfter(now)) t];

  if (times.length + 1 < minOptions) {
    // Next 30-minute boundary strictly after now.
    final sinceMidnight = now.difference(today).inMinutes;
    var slot = today.add(Duration(minutes: (sinceMidnight ~/ 30 + 1) * 30));
    while (times.length + 1 < minOptions) {
      if (!times.any((t) => t.isAtSameMomentAs(slot))) times.add(slot);
      slot = slot.add(const Duration(minutes: 30));
    }
    times.sort();
  }
  return [const TimeOption(null), for (final t in times) TimeOption(t)];
}
