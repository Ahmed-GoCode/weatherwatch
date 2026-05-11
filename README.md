# WeatherWatch 🌤️

WeatherWatch is a Flutter weather app for Android that displays current weather, hourly forecasts, and daily outlook details in a clean UI.

## ✨ Key Features

- Current weather conditions with temperature, humidity, wind, and description
- Hour-by-hour forecast for the next hours
- Daily weather summary for the coming days
- City search and location-based weather lookup
- Metric and imperial unit toggle
- Prepared for Codemagic release signing

## 🚀 Local setup

1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Clone the repository:
   ```bash
   git clone https://github.com/Ahmed-GoCode/weatherwatch.git
   cd weatherwatch
   ```
3. Add your OpenWeather API key:
   - Using Dart define:
     ```bash
     flutter run --dart-define=OPENWEATHER_API_KEY=YOUR_API_KEY
     ```
   - Or update the placeholder in `lib/main.dart`.
4. Install dependencies:
   ```bash
   flutter pub get
   ```
5. Run the app:
   ```bash
   flutter run
   ```

## 🧩 Codemagic

This project includes a `codemagic.yaml` workflow configured for release signing.

Create the environment group and add these secret variables in Codemagic:

- `CM_KEYSTORE_PASSWORD`
- `CM_KEY_PASSWORD`
- `CM_KEYSTORE_B64`

Then run the Codemagic workflow to build a signed APK.

## 🔧 Notes

- The OpenWeather API key is not included in the repository.
- `android/release-key.jks` and `android/key.properties` are ignored by Git.
- Android SDK 36 is recommended for building the app.
