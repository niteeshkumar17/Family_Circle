# Family Circle (formerly FamilyNest)

A comprehensive family safety and location tracking application built with Flutter. Keep your loved ones safe, track their real-time location, and get notified in case of emergencies.

## Features
- **Real-Time Location Tracking:** Uses Google Maps and background services to track family members.
- **Geofencing & Safe Zones:** Create virtual boundaries and get alerts when family members enter or leave safe zones.
- **SOS Alerts:** One-tap emergency alerts with precise location details to notify all family members instantly.
- **Battery Monitoring:** View the battery status of linked devices to know if a family member's phone is about to die.
- **Authentication:** Secure Google Sign-In and Firebase Authentication.
- **Push Notifications:** Real-time updates and communication using Firebase Cloud Messaging.
- **Cross-Platform:** Built with Flutter, ensuring a smooth experience on both Android and iOS.

## Tech Stack
- **Frontend:** Flutter & Dart
- **State Management:** BLoC (flutter_bloc)
- **Backend/Database:** Firebase (Auth, Firestore, Realtime Database, Storage)
- **Maps:** Google Maps Flutter, Geocoding, Location
- **Dependency Injection:** GetIt & Injectable
- **Background Execution:** flutter_background_service

## Getting Started

### Prerequisites
- Flutter SDK (v3.5.0 or higher)
- Android Studio / Xcode
- Firebase account for backend setup

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/niteeshkumar17/Family_Circle.git
   ```
2. Navigate to the project directory:
   ```bash
   cd Family_Circle
   ```
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Set up Firebase:
   - Configure Firebase for Android/iOS.
   - Place the `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) in their respective directories.
5. Run the app:
   ```bash
   flutter run
   ```
