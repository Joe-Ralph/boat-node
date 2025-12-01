import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:boatnode/main.dart';
import 'package:boatnode/l10n/app_localizations.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/services/session_service.dart';
import 'package:boatnode/services/hardware_service.dart';
import 'package:flutter/foundation.dart';
import 'package:boatnode/screens/debug_screen.dart';
import 'package:boatnode/theme/app_theme.dart';

// Extension to handle null safety for localization
extension LocalizationExtension on BuildContext {
  String translate(String key) =>
      AppLocalizations.of(this)?.translate(key) ?? key;
}

// --- The Main Settings Screen Widget ---
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Map to store language code and display name
  final Map<String, String> _languages = {
    'en': 'English',
    'ta': 'தமிழ்',
    'ml': 'മലയാളം',
    'hi': 'हिंदी',
  };

  void _selectLanguage(String languageCode) {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    localeProvider.setLocale(Locale(languageCode));
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted) return;

    Color backgroundColor = kZinc900; // Default theme color
    if (isSuccess) backgroundColor = kGreen500;
    if (isError) backgroundColor = kRed600;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      ),
    );
  }

  Future<void> _unpairDevice() async {
    try {
      // Call hardware service to reset device
      await HardwareService.unpairDevice();

      // Clear local pairing state
      await SessionService.clearPairingState();

      if (mounted) {
        _showSnackBar('Device unpaired successfully', isSuccess: true);
        setState(() {}); // Rebuild to hide button
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to unpair: $e', isError: true);
      }
    }
  }

  Future<void> _logout() async {
    try {
      // Clear the session
      await AuthService.logout();

      // Navigate to login screen and remove all previous routes
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Logout failed: $e');
        _showSnackBar('Failed to logout. Please try again.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.translate('language').toUpperCase(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Consumer<LocaleProvider>(
              builder: (context, localeProvider, _) {
                return _buildLanguageGrid(localeProvider.locale);
              },
            ),
            const SizedBox(height: 24),
            _buildUserInfoTile(),
            const SizedBox(height: 24),
            _buildStatusIntervalSlider(),
            const SizedBox(height: 24),
            _buildGpsIntervalSlider(),
            const SizedBox(height: 24),
            if (SessionService.isPaired)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _unpairDevice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626), // Red 600
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Unpair Device',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DebugScreen()),
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
                    context.translate('debugMenu'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(), // Pushes the following widget to the bottom
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  context.translate('version'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build the language selection grid
  Widget _buildLanguageGrid(Locale currentLocale) {
    // Calculate the height needed for the grid (2 rows with spacing)
    final itemHeight = 48.0; // Height of each grid item
    final rowCount = (_languages.length / 2).ceil(); // Number of rows needed
    final gridHeight =
        (itemHeight * rowCount) +
        (30.0 * (rowCount)); // Total height with spacing

    return SizedBox(
      height: gridHeight, // Fixed height based on content
      child: GridView.builder(
        physics:
            const NeverScrollableScrollPhysics(), // Disable GridView's own scrolling
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.5,
          crossAxisSpacing: 10.0,
          mainAxisSpacing: 10.0,
        ),
        itemCount: _languages.length,
        itemBuilder: (context, index) {
          final languageCode = _languages.keys.elementAt(index);
          final languageDisplay = _languages.values.elementAt(index);

          // Check if the current language button is selected
          final isSelected = currentLocale.languageCode == languageCode;

          return ElevatedButton(
            onPressed: () => _selectLanguage(languageCode),
            style: ElevatedButton.styleFrom(
              // Conditional styling based on selection state
              backgroundColor: isSelected
                  ? Colors.blue
                  : const Color(
                      0xFF222222,
                    ), // Blue for selected, dark grey for unselected
              foregroundColor: isSelected
                  ? Colors.white
                  : Colors.white, // Text color is white
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              elevation: 0, // Remove shadow
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              minimumSize: Size(
                double.infinity,
                itemHeight,
              ), // Set fixed height
            ),
            child: Text(languageDisplay),
          );
        },
      ),
    );
  }

  Widget _buildUserInfoTile() {
    final session = SessionService.currentSession;
    final displayName = session?.displayName ?? 'Guest User';
    final userId = session?.userId ?? 'Not Logged In';

    return Container(
      decoration: BoxDecoration(
        color: const Color(
          0xFF1E1E1E,
        ), // Slightly lighter background for the tile
        borderRadius: BorderRadius.circular(10.0),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // User Information Column
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16.0,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                userId,
                style: const TextStyle(color: Colors.white70, fontSize: 14.0),
              ),
            ],
          ),
          TextButton(
            onPressed: _logout,
            style: TextButton.styleFrom(
              backgroundColor: const Color(
                0xFF440000,
              ), // Dark red background for contrast
              foregroundColor: Colors.white, // Text color is white
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIntervalSlider() {
    final Map<int, String> intervalOptions = {
      5: '5 sec',
      10: '10 sec',
      15: '15 sec',
      30: '30 sec',
      60: '1 min',
      120: '2 min',
      300: '5 min',
    };

    // Ensure current value is valid, default to 5 if not
    final currentValue =
        intervalOptions.containsKey(SessionService.statusInterval)
        ? SessionService.statusInterval
        : 5;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10.0),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate('statusUpdateInterval'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16.0,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: currentValue,
                dropdownColor: Colors.grey[900],
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: intervalOptions.entries.map((entry) {
                  return DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      SessionService.saveStatusInterval(value);
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsIntervalSlider() {
    final Map<int, String> intervalOptions = {
      5: '5 sec',
      10: '10 sec',
      15: '15 sec',
      30: '30 sec',
      60: '1 min',
      120: '2 min',
      300: '5 min',
    };

    // Ensure current value is valid, default to 30 if not
    final currentValue =
        intervalOptions.containsKey(SessionService.gpsUpdateInterval)
        ? SessionService.gpsUpdateInterval
        : 30;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10.0),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.translate('gpsUpdateInterval'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16.0,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: currentValue,
                dropdownColor: Colors.grey[900],
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                items: intervalOptions.entries.map((entry) {
                  return DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      SessionService.saveGpsUpdateInterval(value);
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
