import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/log_service.dart';

class SosService {
  /// Sends an SOS signal to nearby users.
  static Future<void> sendSos() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      await Supabase.instance.client.rpc(
        'broadcast_sos',
        params: {'p_lat': position.latitude, 'p_long': position.longitude},
      );

      LogService.i(
        "SOS broadcast sent successfully from ${position.latitude}, ${position.longitude}",
      );
    } catch (e) {
      LogService.e("Error sending SOS", e);
      rethrow;
    }
  }

  /// Cancels an active SOS signal.
  static Future<void> cancelSos() async {
    try {
      await Supabase.instance.client.rpc('cancel_sos');
      LogService.i("SOS broadcast cancelled successfully");
    } catch (e) {
      LogService.e("Error cancelling SOS", e);
      rethrow;
    }
  }

  // Incoming call listeners (foreground) would typically go here or in a controller,
  // but CallKit handles most of the UI.
}
