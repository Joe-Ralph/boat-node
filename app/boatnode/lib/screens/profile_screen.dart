import 'package:flutter/material.dart';
import 'package:boatnode/models/user.dart';
import 'package:boatnode/services/auth_service.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/theme/app_theme.dart';
import 'package:boatnode/screens/dashboard_screen.dart';
import '../utils/ui_utils.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _boatRegistrationController;
  String? _selectedRole;
  String? _selectedVillageId;
  List<Map<String, dynamic>> _villages = [];
  bool _isLoading = false;

  final List<Map<String, String>> _roles = [
    {'value': 'owner', 'label': 'Boat Owner'},
    {'value': 'joiner', 'label': 'Boat Joiner'},
    {'value': 'land_user', 'label': 'Land User'},
    {'value': 'land_admin', 'label': 'Land Admin'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.displayName);
    _boatRegistrationController = TextEditingController();
    _selectedRole = widget.user.role;
    _selectedVillageId = widget.user.villageId;
    _loadVillages();
  }

  Future<void> _loadVillages() async {
    final villages = await BackendService.getVillages();
    if (mounted) {
      setState(() {
        _villages = villages;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _boatRegistrationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == null) {
      UiUtils.showSnackBar(context, 'Please select a role', isError: true);
      return;
    }
    if (_selectedVillageId == null) {
      UiUtils.showSnackBar(context, 'Please select a village', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthService.updateProfile(
        widget.user,
        displayName: _nameController.text,
        role: _selectedRole,
        villageId: _selectedVillageId,
        boatRegistrationNumber: _boatRegistrationController.text,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar(
          context,
          'Error updating profile: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kZinc950,
      appBar: AppBar(
        title: const Text('Complete Profile'),
        backgroundColor: kZinc950,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Tell us about yourself",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please fill in your details to continue.",
                style: TextStyle(color: kZinc500),
              ),
              const SizedBox(height: 32),

              // Name Field
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Full Name",
                  labelStyle: const TextStyle(color: kZinc500),
                  filled: true,
                  fillColor: kZinc900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.person, color: kZinc500),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Role Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                dropdownColor: kZinc900,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Role",
                  labelStyle: const TextStyle(color: kZinc500),
                  filled: true,
                  fillColor: kZinc900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.work, color: kZinc500),
                ),
                items: _roles.map((role) {
                  return DropdownMenuItem(
                    value: role['value'],
                    child: Text(role['label']!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedRole = value);
                },
              ),
              const SizedBox(height: 8),
              if (_selectedRole != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kBlue600.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBlue600.withOpacity(0.3)),
                  ),
                  child: Text(
                    _getRoleDescription(_selectedRole!),
                    style: const TextStyle(color: kBlue600, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              // Boat Registration Number (Only for Owners)
              if (_selectedRole == 'owner') ...[
                TextFormField(
                  controller: _boatRegistrationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Boat Registration Number",
                    labelStyle: const TextStyle(color: kZinc500),
                    filled: true,
                    fillColor: kZinc900,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.directions_boat,
                      color: kZinc500,
                    ),
                  ),
                  validator: (value) {
                    if (_selectedRole == 'owner' &&
                        (value == null || value.isEmpty)) {
                      return 'Please enter boat registration number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Village Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedVillageId,
                dropdownColor: kZinc900,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Village",
                  labelStyle: const TextStyle(color: kZinc500),
                  filled: true,
                  fillColor: kZinc900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.location_city, color: kZinc500),
                ),
                items: _villages.map<DropdownMenuItem<String>>((village) {
                  return DropdownMenuItem<String>(
                    value: village['id'].toString(),
                    child: Text(village['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedVillageId = value);
                },
              ),
              const SizedBox(height: 48),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Continue",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRoleDescription(String role) {
    switch (role) {
      case 'owner':
        return "Boat Owner: Manage your boat, pair devices, and generate QR codes.";
      case 'joiner':
        return "Boat Joiner: Join a boat for fishing, view status, and use SOS.";
      case 'land_user':
        return "Land User: Track a specific boat from land (Internet required).";
      case 'land_admin':
        return "Land Admin: Monitor all boats in your village (Requires approval).";
      default:
        return "";
    }
  }
}
