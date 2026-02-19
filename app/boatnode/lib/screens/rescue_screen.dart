import 'package:flutter/material.dart';
import 'package:slide_to_confirm/slide_to_confirm.dart';
// import 'package:slider_button/slider_button.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'package:boatnode/services/sos_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/ui_utils.dart';

// Add these to your localization files if not already present
// English (en.json):
/*
  "sosConfirmationTitle": "CONFIRM EMERGENCY SOS",
  "sosConfirmationMessage": "Are you sure you want to activate the emergency SOS? This will send your location to emergency services.",
  "cancel": "CANCEL",
  "confirm": "CONFIRM",
  "sosActive": "SOS ACTIVE",
  "cancelSOS": "CANCEL SOS",
  "slideToActivate": "SLIDE TO ACTIVATE SOS",
  "emergencyUseOnly": "FOR EMERGENCY USE ONLY"
*/

// Similar translations should be added to other language files (ta.json, ml.json, hi.json)

class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen>
    with SingleTickerProviderStateMixin {
  bool _isActive = false;
  late AnimationController _controller;
  final List<String> _logs = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _addLog(AppLocalizations.of(context)!.translate('systemReady'));
      _initialized = true;
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activateDistressSignal() async {
    setState(() => _isActive = true);
    WakelockPlus.enable();
    final localizations = AppLocalizations.of(context)!;
    _addLog(localizations.translate('initiatingDistress'));

    try {
      await SosService.sendSos();
      _addLog("SOS Broadcast Sent to Nearby Users!");
      _addLog("${localizations.translate('buzzer')}: ON");

      final gpsMessage =
          "${localizations.translate('gps')}: ${localizations.translate('fixAcquired')}";
      Future.delayed(const Duration(seconds: 1), () => _addLog(gpsMessage));
    } catch (e) {
      _addLog("Error transmitting SOS: $e");
      setState(() => _isActive = false); // Revert state on error

      if (mounted) {
        UiUtils.showSnackBar(context, "Failed to send SOS: $e", isError: true);
      }
    }
  }

  Future<void> _cancelDistressSignal() async {
    try {
      await SosService.cancelSos();
      if (mounted) {
        setState(() => _isActive = false);
        WakelockPlus.disable();
        _addLog(AppLocalizations.of(context)!.translate('distressCancelled'));
      }
    } catch (e) {
      _addLog("Error cancelling SOS: $e");
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          "Failed to cancel SOS: $e",
          isError: true,
        );
        // We might want to set isActive = false anyway if it's a network error,
        // but strictly speaking we failed to tell server.
        // For UX, usually better to force cancel locally too.
        setState(() => _isActive = false);
      }
    }
  }

  void _addLog(String log) {
    if (mounted) setState(() => _logs.insert(0, "> $log"));
  }

  @override
  Widget build(BuildContext context) {
    final sliderWidth = MediaQuery.of(context).size.width - 48;

    return PopScope(
      canPop: !_isActive,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_isActive) {
          UiUtils.showSnackBar(
            context,
            "Cannot exit while SOS is active. Please Cancel SOS first.",
            isError: true,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isActive)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Container(
                      color: kRed600.withOpacity(_controller.value * 0.2),
                    );
                  },
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: _isActive
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Active state
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        width: 200,
                                        height: 200,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: kRed600,
                                          boxShadow: [
                                            BoxShadow(
                                              color: kRed600.withOpacity(0.5),
                                              blurRadius: 50,
                                              spreadRadius: 10,
                                            ),
                                          ],
                                          border: Border.all(
                                            color: kRed900,
                                            width: 8,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.emergency,
                                              size: 64,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              AppLocalizations.of(context)!
                                                  .translate('sosActive')
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: ConfirmationSlider(
                                          width: sliderWidth,
                                          height: 70,
                                          backgroundColor: kZinc900,
                                          foregroundColor: kRed500,
                                          text: AppLocalizations.of(
                                            context,
                                          )!.translate('cancelSOS'),
                                          textStyle: const TextStyle(
                                            color: kRed500,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                          onConfirmation: _cancelDistressSignal,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Slider button
                                      SizedBox(
                                        width: double.infinity,
                                        child: Column(
                                          children: [
                                            ConfirmationSlider(
                                              stickToEnd: true,
                                              width: sliderWidth,
                                              height: 70,
                                              backgroundColor: kZinc900,
                                              onConfirmation: () {
                                                _activateDistressSignal();
                                              },
                                              text: AppLocalizations.of(
                                                context,
                                              )!.translate('slideToActivate'),
                                              foregroundColor: kRed600,
                                              textStyle: TextStyle(
                                                color: kRed600,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                              sliderButtonContent: const Icon(
                                                Icons.emergency,
                                                color: Colors.white,
                                                size: 30,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              AppLocalizations.of(
                                                context,
                                              )!.translate('emergencyUseOnly'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        Container(
                          height: 180,
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kZinc900,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kZinc800, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.terminal,
                                    color: kZinc400,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'SYSTEM LOG',
                                    style: TextStyle(
                                      color: kZinc400,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: kZinc800,
                                      width: 1,
                                    ),
                                  ),
                                  child: ListView.builder(
                                    reverse: true,
                                    itemCount: _logs.length,
                                    itemBuilder: (context, index) {
                                      return Text(
                                        _logs[index],
                                        style: const TextStyle(
                                          color: kGreen500,
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
