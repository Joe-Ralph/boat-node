import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/services/session_service.dart';
import '../utils/ui_utils.dart';
import 'package:boatnode/theme/app_theme.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawQrData = barcodes.first.rawValue;
    if (rawQrData == null) return;

    setState(() => _isProcessing = true);
    _controller.stop(); // Pause scanning

    try {
      // Call new Backend Service for joining
      final result = await BackendService.joinBoatByQR(rawQrData);

      final boatName = result['boat_name'] ?? 'Unknown Boat';
      final boatId = result['boat_id'];

      // Persist the joined boat ID locally
      final currentUser = await AuthService.getCurrentUser();
      if (currentUser != null && boatId != null) {
        final updatedUser = currentUser.copyWith(boatId: boatId.toString());
        await SessionService.saveUser(updatedUser);
      }

      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Successfully joined boat: $boatName",
          isSuccess: true,
        );
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        // Resume scanning on error
        _controller.start();
        setState(() => _isProcessing = false);
        UiUtils.showSnackBar(
          context,
          "Failed to join boat: ${e.toString().replaceAll('Exception:', '').trim()}",
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kZinc950,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: kZinc950,
        elevation: 0,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  case TorchState.auto: // Handle auto if needed
                    return const Icon(Icons.flash_auto, color: Colors.white);
                  case TorchState.unavailable:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                  default:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _handleBarcode),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          // Overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: kBlue600, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: const Text(
              "Align QR code within the frame",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    blurRadius: 4,
                    color: Colors.black,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
