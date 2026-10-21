import 'package:geolocator/geolocator.dart';

/// Coarse location for the morning weather. Asks once; returns null when the
/// user declines or location is off — weather is then simply not shown.
Future<(double, double)?> coarseLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
    );
    return (pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}
