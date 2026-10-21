/// Human readable byte sizes, matching the original `ByteSize.ToString`
/// (largest whole unit, binary multiples, two decimals at most).
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value.abs() >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text ${units[unit]}';
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// Formats like the original's `MMMM dd, yyyy - hh:mm tt`.
String formatDate(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  String two(int n) => n.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${_months[d.month - 1]} ${two(d.day)}, ${d.year} - ${two(hour12)}:${two(d.minute)} $ampm';
}
