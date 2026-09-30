# Throttle (Flutter)

Flutter port of the Throttle React app (motorcycle social feed: ride, record, share).

The original web app remains in `../pixel-perfect-match-main`.

## First-time setup

This folder contains the Dart app. Generate iOS/Android project files, then add location permission strings used by Record.

```bash
cd throttle
flutter create . --org com.throttle --project-name throttle --platforms ios,android
flutter pub get
```

**Android** — in `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

**iOS** — in `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Throttle uses your location to record ride distance and speed.</string>
```

```bash
flutter run
```

## What’s included

- Home feed, nearby route, kudos, join group ride
- Discover (routes / riders / clubs + search)
- Record with GPS, start / pause / resume / finish, bike & privacy
- Activity stats, weekly chart, challenge
- Profile garage and privacy
