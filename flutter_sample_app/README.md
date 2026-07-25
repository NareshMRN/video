# Flutter Video Editor Sample

This repository contains a sample Flutter app (flutter_sample_app) that demonstrates basic video editing features on Android:

- Pick a video from device storage
- Preview with playback speed changes
- Trim using a RangeSlider
- Apply simple visual effects (Grayscale, Sepia, Blur) for export
- Add captions (editable) and generate simple captions using on-device speech_to_text
- Export (re-encode) using FFmpeg (ffmpeg_kit_flutter_full_gpl) with video filters and drawtext burn-in captions

Notes
- This sample targets Android. iOS may need additional FFmpegKit setup.
- ffmpeg_kit_flutter_full_gpl is GPL-licensed — ensure the GPL license is acceptable for your distribution.

How to run
1. Ensure you have Flutter installed and an Android device or emulator ready.
2. Open the flutter_sample_app folder and run `flutter pub get`.
3. Add a real TTF font at `flutter_sample_app/assets/fonts/Roboto-Regular.ttf` (the project includes a placeholder). FFmpeg drawtext requires a font file to be available on the device — the app copies this asset to app documents at runtime.
4. Run the app:
   flutter run -d <device>

Android manifest / permissions
- The sample requests storage permission at runtime. Add the following to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

- For Android 11+ you may need to adapt to Scoped Storage or use SAF for file selection. This sample uses the FilePicker plugin for convenience.

FFmpegKit notes
- The project uses `ffmpeg_kit_flutter_full_gpl`. See the package docs for details on packaging (ABI splits) and ProGuard rules.

Integrating the `video_editor` package
- This sample provides a minimal editor UI using `video_player`. If you'd like, I can replace the UI with the `video_editor` package (https://github.com/LeGoffMael/video_editor) for a more complete timeline & trimming experience.

License
- Files added here are licensed MIT by default, but note that ffmpeg_kit is GPL and may affect distribution.
