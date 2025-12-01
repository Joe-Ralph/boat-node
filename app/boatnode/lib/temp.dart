import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(const BoatNodeApp());
}

// --- THEME CONSTANTS (Tailwind Mappings) ---
const kZinc950 = Color(0xFF09090B);
const kZinc900 = Color(0xFF18181B);
const kZinc800 = Color(0xFF27272A);
const kZinc500 = Color(0xFF71717A);
const kBlue600 = Color(0xFF2563EB);
const kRed600 = Color(0xFFDC2626);
const kGreen500 = Color(0xFF22C55E);

class BoatNodeApp extends StatelessWidget {
  const BoatNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoatNode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kZinc950,
        primaryColor: kBlue600,
        useMaterial3: true,
        fontFamily: 'Inter', // Ensure you add Google Fonts or assets
        colorScheme: const ColorScheme.dark(
          primary: kBlue600,
          surface: kZinc900,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// --- MODELS ---

class Boat {
  final String id;
  final String name;
  final int batteryLevel;
  final Map<String, dynamic> connection;
  final Map<String, dynamic> lastFix;

  Boat({required this.id, required this.name, required this.batteryLevel, required this.connection, required this.lastFix});
}

class NearbyBoat {
  final String id;
  final String name;
  final int distance;
  final String bearing;
  final int lastSeen;

  NearbyBoat({required this.id, required this.name, required this.distance, required this.bearing, required this.lastSeen});
}

// --- MOCK HARDWARE SERVICE ---

class HardwareService {
  static Future<Boat> getBoatStatus(String id) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return Boat(
      id: id,
      name: "Raja's Boat",
      batteryLevel: 85,
      connection: {'wifi': true, 'lora': false, 'mesh': 3},
      lastFix: {'lat': 13.0827, 'lng': 80.2707},
    );
  }

  static Future<List<NearbyBoat>> scanMesh() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return [
      NearbyBoat(id: 'B101', name: "Kumar's Boat", distance: 250, bearing: "NE", lastSeen: 1),
      NearbyBoat(id: 'B102', name: "Mani's Boat", distance: 800, bearing: "S", lastSeen: 5),
      NearbyBoat(id: 'B202', name: "Boat 202", distance: 1200, bearing: "NW", lastSeen: 12),
    ];
  }
}

// --- SCREENS ---

// 1. Login Screen
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // Mock API
    if (mounted) {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const DashboardScreen())
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: kBlue600, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.sailing, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text("BoatNode", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const Text("Fisherman Login", style: TextStyle(color: kZinc500)),
            const SizedBox(height: 48),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: "Phone Number",
                filled: true,
                fillColor: kZinc900,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.phone, color: kZinc500),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("Login", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// 2. Dashboard Screen
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Boat? _boat;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final boat = await HardwareService.getBoatStatus('123');
    setState(() => _boat = boat);
  }

  @override
  Widget build(BuildContext context) {
    if (_boat == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildStatusCard(),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildActionButton(
                      "RESCUE MODE", Icons.support, kRed600, 
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueScreen())),
                      isRescue: true
                    ),
                    _buildActionButton(
                      "Nearby Boats", Icons.radar, kZinc800, 
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyScreen()))
                    ),
                    _buildActionButton(
                      "Settings", Icons.settings, kZinc800, 
                      () {}
                    ),
                    _buildActionButton(
                      "Sync Status", Icons.refresh, kZinc800, 
                      _loadData
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kZinc900,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kZinc800),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status", style: TextStyle(color: kZinc500, fontSize: 12)),
                  Text(_boat!.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("ID: ${_boat!.id}", style: const TextStyle(color: kZinc500, fontFamily: 'monospace')),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF14532D), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF166534))),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, color: kGreen500, size: 16),
                    Text("${_boat!.batteryLevel}%", style: const TextStyle(color: kGreen500, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBadge(Icons.wifi, "Wi-Fi", true),
              _buildBadge(Icons.cell_tower, "LoRa", false),
              _buildBadge(Icons.group, "Mesh (3)", true),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, bool active) {
    return Column(
      children: [
        Icon(icon, color: active ? kGreen500 : kZinc500),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? kGreen500 : kZinc500)),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color bg, VoidCallback onTap, {bool isRescue = false}) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            if (isRescue) ...[
              const SizedBox(height: 4),
              Text("Broadcasting Signal", style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7))),
            ]
          ],
        ),
      ),
    );
  }
}

// 3. Rescue Screen
class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen> with SingleTickerProviderStateMixin {  
  bool _isActive = false;
  late AnimationController _controller;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _addLog("System Ready.");
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleBeacon() {
    setState(() => _isActive = !_isActive);
    if (_isActive) {
      _addLog("INITIATING DISTRESS PROTOCOL...");
      _addLog("Buzzer: ON");
      Future.delayed(const Duration(seconds: 1), () => _addLog("GPS: FIX ACQUIRED"));
    } else {
      _addLog("DISTRESS PROTOCOL CANCELLED.");
    }
  }

  void _addLog(String log) {
    if (mounted) setState(() => _logs.insert(0, "> $log"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isActive)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(color: kRed600.withOpacity(_controller.value * 0.2));
                },
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: _toggleBeacon,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 240, height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isActive ? kRed600 : kZinc800,
                          boxShadow: _isActive ? [BoxShadow(color: kRed600.withOpacity(0.5), blurRadius: 50, spreadRadius: 10)] : [],
                          border: Border.all(color: kZinc900, width: 8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.surround_sound, size: 64, color: Colors.white),
                            const SizedBox(height: 12),
                            Text(_isActive ? "ACTIVE" : "ACTIVATE", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 200,
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.black,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("SYSTEM LOG", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kZinc500)),
                      const Divider(color: kZinc800),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) => Text(_logs[index], style: const TextStyle(fontFamily: 'monospace', color: kGreen500, fontSize: 12)),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 4. Nearby Screen
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  List<NearbyBoat> _boats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final boats = await HardwareService.scanMesh();
    if (mounted) setState(() { _boats = boats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Nearby Boats"),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF14532D), borderRadius: BorderRadius.circular(12)),
            child: const Text("MESH ACTIVE", style: TextStyle(fontSize: 10, color: kGreen500, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kZinc800))),
                Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kZinc800))),
                const Icon(Icons.navigation, color: kBlue600),
                // Simulated Dots
                 Positioned(top: 40, right: 60, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: kZinc500, shape: BoxShape.circle))),
                 Positioned(bottom: 50, left: 40, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: kZinc500, shape: BoxShape.circle))),
              ],
            ),
          ),
          Expanded(
            child: _loading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _boats.length,
                  itemBuilder: (context, index) {
                    final boat = _boats[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kZinc900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kZinc800),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: kZinc800, borderRadius: BorderRadius.circular(8)),
                            alignment: Alignment.center,
                            child: Text(boat.bearing, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(boat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("ID: ${boat.id} • ${boat.lastSeen}m ago", style: const TextStyle(color: kZinc500, fontSize: 12)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("${boat.distance}m", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const Text("Strong Signal", style: TextStyle(color: kGreen500, fontSize: 10)),
                            ],
                          )
                        ],
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}
