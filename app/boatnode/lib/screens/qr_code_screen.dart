import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/models/boat.dart';

class QRCodeScreen extends StatelessWidget {
  final Boat boat;
  final String devicePassword; // We might need this to share Wi-Fi creds

  const QRCodeScreen({
    super.key,
    required this.boat,
    this.devicePassword = 'pairme-1234', // Default for now
  });

  @override
  Widget build(BuildContext context) {
    // Format: BOAT:boatId:deviceId:password
    // In real app, this should be signed/encrypted
    final qrData = "BOAT:${boat.id}:device_id_placeholder:$devicePassword";

    return Scaffold(
      backgroundColor: kZinc950,
      appBar: AppBar(
        title: const Text('Boat QR Code'),
        backgroundColor: kZinc950,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 250.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                boat.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "ID: ${boat.id}",
                style: const TextStyle(color: kZinc500, fontSize: 16),
              ),
              const SizedBox(height: 32),
              const Text(
                "Scan this code to join this boat.",
                style: TextStyle(color: kZinc400, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
