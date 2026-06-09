/// 数字紧凑化（万 / 亿）—— 与 iOS Theme.compactCount 对齐
String compactCount(int n) {
  if (n < 10000) return '$n';
  if (n < 100000000) {
    final v = n / 10000.0;
    return v >= 100 ? '${v.toStringAsFixed(0)}万' : '${v.toStringAsFixed(1)}万';
  }
  final v = n / 100000000.0;
  return v >= 100 ? '${v.toStringAsFixed(0)}亿' : '${v.toStringAsFixed(1)}亿';
}

/// 时长格式化 mm:ss / hh:mm:ss
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
