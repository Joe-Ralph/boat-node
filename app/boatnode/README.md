# Neduvaai 🌊⚓️

> **"Bridging the connection between the shore and the deep sea."**

Neduvaai is a lifeline for fishermen and their families, providing real-time tracking, distress signaling (SOS), and mesh-networked communication to ensure safety beyond the range of cellular networks.

---

## ❤️ Motivation & Emotion

For the families of fishermen, every journey into the sea is accompanied by a silent, lingering fear. When their loved ones cross the horizon and cellular signals fade, they enter a "black zone" of uncertainty. Hours turn into days, and the lack of communication fuels anxiety about storms, engine failures, or accidents.

**Neduvaai** (Tamil for "Long Path" or "Deep Sea Way") was born from this emotional need. It isn't just a tracking app; it is peace of mind. It is the assurance that even in the vast, unconnected ocean, they are not alone. It empowers families to know *where* their loved ones are and gives fishermen a voice to say "I'm safe" or "I need help" when it matters most.

---

## 🚩 The Problem

1.  **Communication Blackout:** Once boats venture a few kilometers off the coast, cellular towers (4G/5G) become unreachable. GPS works, but there is no way to *transmit* that location to shore.
2.  **Delayed Rescue:** In emergencies (capsizing, medical issues), fishermen often have no way to alert authorities or nearby boats instantly. Search and rescue operations often start too late, scanning vast areas blindly.
3.  **Isolation:** Small boats operate independently. If one is in trouble, a nearby boat might be unaware of their distress.

---

## 💡 The Solution: Neduvaai Ecosystem

The Neduvaai system consists of two inseparable parts: the **Mobile App** and the **Boat Module**.

### 1. The Hardware Module 📦
The heart of the system is a custom-built, low-cost hardware module designed to operate in the harsh marine environment.

*   **ESP32 Microcontroller:** The brain of the unit, handling logic, Wi-Fi connectivity for the phone, and interfacing with sensors.
*   **GPS Module:** Continuously acquires precise latitude, longitude, speed, and heading data from satellites.
*   **LoRa (RFM95w):** Long Range radio transceiver. This is the magic component that transmits small data packets over tens of kilometers without internet or cellular reception.
*   **LoRa Mesh Network:** Every boat module acts as a relay. If Boat A is too far from the shore but close to Boat B, and Boat B is within range of the shore (or Boat C), the location data hops from A -> B -> Shore. This works like a chain, effectively extending the communication range deep into the ocean.
*   **Buzzer & LED:** Visual and auditory indicators for status (pairing, error) and high-alert alarms during SOS events.
*   **Battery:** Ensures the module runs independently of the boat's main power if necessary.

### 2. The Mobile App 📱
The app serves as the interface for the fishermen (at sea) and their families (on land).

*   **Offline First:** Designed to work without internet. It connects directly to the Boat Module via Wi-Fi to display data and control settings.
*   **Real-Time Dashboard:** Shows live GPS data, battery status, and connection health (Wi-Fi, LoRa, Mesh count).
*   **Emergency SOS:** A dedicated, high-priority mode to broadcast distress signals to all nearby boats and the shore station.

---

## 📱 App Walkthrough & Features

### 1. Verification & Login (`LoginScreen`)
*   **Secure Access:** Simple OTP-based login (simulated/mock capable) to link a user to their identity (`Owner`, `Family`, etc.).
*   **Role Management:** distinguishes between *Boat Owners* (who manage the device) and *Joiners/Land Users* (who track/view).

### 2. Dashboard (`DashboardScreen`)
The central hub of the application.
*   **Status Card:** Instantly view the Boat Name, Battery Level, and Connection Status (Wi-Fi, LoRa, Mesh).
*   **Journey Mode:**
    *   **Paired:** The module handles tracking.
    *   **Unpaired:** Leverages the phone's internal GPS to track the journey if the user is on a small craft without a module (requires network).
*   **Border Alert:** Uses `GeofenceService` to proactively warn fishermen if they are approaching international maritime boundaries, preventing accidental crossings and arrests.
*   **Action Grid:** Quick access to connect, track nearby boats, or sync data.

### 3. Pairing & Setup (`PairingScreen`)
*   **Seamless Connection:** Uses Wi-Fi to scan for Neduvaai modules (SSID `BOAT-PAIR-XXXX`).
*   **One-Tap Config:** Automatically configures the hardware with the Boat ID and User details.
*   **Security:** Fetches device-specific passwords from the backend to ensure only authorized owners can pair.

### 4. Nearby Boats (`NearbyScreen`)
*   **Visualization:** A radar-like list view showing other boats in the mesh network.
*   **Mesh Insight:** Displays vital stats of other boats (Distance, ID, heading) received via LoRa. This helps fishermen know who is closest to them in case they need to ask for help physically.

### 5. SOS - Emergency Mode (`RescueScreen`)
*   **Critical Function:** A deliberate, slide-to-activate interface prevents accidental triggers.
*   **Action:**
    *   Triggers the hardware **Buzzer** (loud alarm).
    *   Broadcasts a high-priority **SOS packet** via LoRa.
    *   Updates the Mesh network status to "DISTRESS".
*   **Feedback:** A visual "System Log" terminal interface confirms that the distress signal is being broadcasted and GPS locks are acquired.

### 6. QR Code System (`QRCodeScreen` & `QRScanScreen`)
*   **Easy Sharing:** Boat owners can generate a QR code containing their Boat ID.
*   **Quick Join:** Crew members or family can scan this code to instantly "join" the boat in the app, allowing them to view its specific data without needing to be the primary owner.

---

## 🔧 Technical Deep Dive

### Connectivity Flow
1.  **Phone <-> Module:** The app connects to the module via **Wi-Fi Access Point** (hosted by ESP32). It polls for status updates (`/status`) and pushes configuration (`/pair`).
2.  **Module <-> Module:** Uses **LoRa (915/868 MHz)** to ping nearby boats. It forms an ad-hoc mesh network to relay messages.
3.  **Module <-> Shore:** The final node in the mesh transmits data to a shore-based LoRa Gateway, which pushes data to the internet (Cloud Database).

### App Services
*   `HardwareService`: Handles all HTTP communication with the ESP32 (default IP `192.168.4.1`). Manages Wi-Fi connections via `wifi_iot`.
*   `BackgroundService`: Ensures tracking continues even when the app is minimized (`flutter_background_service`), crucial for accurate journey logging.
*   `GeofenceService`: local logic to calculate distance to sensitive geolocations (Maritime Borders) and trigger high-priority alerts.
*   `BackendService`: Syncs data with the cloud (Supabase) when internet IS available (e.g., when close to shore or for land users).

---

## 🚀 Getting Started

1.  **Power On:** Turn on the Neduvaai Boat Module.
2.  **Login:** Open the app and log in with your mobile number.
3.  **Pair:** Navigate to pairing, grant Location/Wi-Fi permissions, and tap "Start Pairing". The app will find your boat module.
4.  **Go Fish:** Once paired, the dashboard will show "LOCKED" GPS status. You are ready to sail.
5.  **Monitor:** Use the dashboard to keep an eye on battery and border alerts.

---

> Built with ❤️ for the fishing community.
