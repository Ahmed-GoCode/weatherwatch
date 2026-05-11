# WeatherWatch 🌤️

WeatherWatch is a Flutter weather app that shows current weather, hourly forecast, and daily outlook.

## Features

- Current weather details
- Hourly weather forecast
- Daily weather summary
- Location search
- Metric / imperial toggle
- Release signing ready for Codemagic

## Local setup

1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Clone the repository:
   ```bash
   git clone https://github.com/Ahmed-GoCode/weatherwatch.git
   cd weatherwatch
   ```
3. Add your OpenWeather API key:
   - Set it with Dart define:
     ```bash
     flutter run --dart-define=OPENWEATHER_API_KEY=YOUR_API_KEY
     ```
   - Or replace the placeholder in `lib/main.dart`.
4. Install dependencies:
   ```bash
   flutter pub get
   ```
5. Run the app:
   ```bash
   flutter run
   ```

## Codemagic

This repository includes a `codemagic.yaml` workflow with a `release-signing` environment group.

Create the group in Codemagic and add these secret variables:

- `CM_KEYSTORE_PASSWORD`
- `CM_KEY_PASSWORD`
- `CM_KEYSTORE_B64`

Then run the Codemagic workflow to build a signed APK.

## Notes

- The OpenWeather API key is intentionally removed from source.
- `android/release-key.jks` and `android/key.properties` are ignored by Git.
- Make sure Android SDK 36 is installed for the build.
