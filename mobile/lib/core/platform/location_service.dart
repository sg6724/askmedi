import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum LocationFailure { serviceOff, denied, unavailable }

class LocationException implements Exception {
  const LocationException(this.failure);
  final LocationFailure failure;
}

abstract interface class LocationService {
  /// Asks for permission just in time. Throws [LocationException].
  Future<LatLng> current();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LatLng> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationException(LocationFailure.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const LocationException(LocationFailure.denied);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } on LocationException {
      rethrow;
    } catch (_) {
      throw const LocationException(LocationFailure.unavailable);
    }
  }
}

final locationServiceProvider =
    Provider<LocationService>((ref) => GeolocatorLocationService());
