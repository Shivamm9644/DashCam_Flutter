# Inurum Dashcam & Telematics - Flutter Mobile App

Enterprise multi-tenant dashcam and fleet telematics mobile application built with Flutter.

## 📱 Features
- **Live Fleet & Telematics**: Real-time vehicle tracking with Google Maps SDK.
- **Dual Camera Live Stream**: Road facing camera (CH1) and Driver Cabin DMS (CH2).
- **Footage Playback**: Video playback with time scrubber and calendar picker.
- **Safety Incidents**: Real-time ADAS / DMS alerts with video proof.
- **Role-Based Auth**: Super Admin, Fleet Manager, and Driver accounts.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (v3.0.0 or higher)
- Android Studio / Xcode
- Dart 3+

### Installation & Run

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run on Android / iOS**:
   ```bash
   flutter run
   ```

3. **Run on Web Browser**:
   ```bash
   flutter run -d chrome
   ```
   Or use the standalone web runner:
   ```bash
   node web_server.js
   ```

---

## 🔑 Configuration
- **Google Maps API Key**: Configured in `android/app/src/main/AndroidManifest.xml` and `web/index.html`:
  `AIzaSyBa6Sfh7UbFlueqmLXSJbWEEoIYoeIpEXs`
- **Backend API Base URL**: Configured in `lib/services/api_service.dart` (Default: `http://localhost:8080` for Java Spring Boot or `http://localhost:3000` for Node backend).
