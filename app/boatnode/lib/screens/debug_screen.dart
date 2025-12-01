import 'package:flutter/material.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/notification_service.dart';
import 'package:boatnode/theme/app_theme.dart';

import 'package:boatnode/services/hardware_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  double _batteryLevel = 85.0;
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.translate('debugMenu')),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final title = AppLocalizations.of(
                    context,
                  )!.translate('lowBatteryTitle');
                  final message = AppLocalizations.of(
                    context,
                  )!.translate('lowBatteryMessage');
                  await NotificationService().showChargingReminder(
                    title,
                    message,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kZinc800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.translate('triggerNotification'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              "Service Mode",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SwitchListTile(
              title: const Text(
                "Use Mock Services",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                HardwareService.isMockService
                    ? "Simulated Data"
                    : "Real Hardware (192.168.4.1)",
                style: const TextStyle(color: Colors.white70),
              ),
              value: HardwareService.isMockService,
              activeColor: kGreen500,
              contentPadding: EdgeInsets.zero,
              onChanged: (bool value) {
                setState(() {
                  HardwareService.setUseMockService(value);
                });
              },
            ),
            const SizedBox(height: 32),
            const Text(
              "Mock Battery Level",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  "${_batteryLevel.toInt()}%",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Expanded(
                  child: Slider(
                    value: _batteryLevel,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: _batteryLevel.round().toString(),
                    activeColor: kGreen500,
                    inactiveColor: kZinc800,
                    onChanged: (double value) {
                      setState(() {
                        _batteryLevel = value;
                      });
                      HardwareService.setMockBatteryLevel(value.toInt());
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              "Mock Location Override",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: "Latitude",
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: kZinc800,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: "Longitude",
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: kZinc800,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final lat = double.tryParse(_latController.text);
                      final lng = double.tryParse(_lngController.text);
                      if (lat != null && lng != null) {
                        HardwareService.setMockPosition(lat, lng);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Mock location set"),
                            backgroundColor: kGreen500,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Invalid coordinates"),
                            backgroundColor: kRed600,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kZinc800,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Set Location",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HardwareService.clearMockPosition();
                      _latController.clear();
                      _lngController.clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Mock location cleared"),
                          backgroundColor: kZinc800,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kRed600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Clear",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
