# JARVIS AI by CassimTV

> *"At your service, sir."*

A fully functional personal AI assistant for Android TV and Android mobile.
**100% free. 100% local. Zero paid APIs. Zero subscriptions.**

---

## What's Inside

| Component | Technology | Cost |
|---|---|---|
| AI Brain | Ollama + Phi-3 (runs on your machine) | FREE |
| Voice Cloning | Coqui XTTS-v2 (your 3 recordings) | FREE |
| Wake Word | openWakeWord ("Jarvis!") | FREE |
| Speech-to-Text | Faster-Whisper | FREE |
| System Monitoring | psutil | FREE |
| App Framework | Flutter | FREE |

---

## Setup — Step by Step

### STEP 1: Install Ollama (the AI brain)

Download from: https://ollama.com (free, runs locally)

```bash
# After installing, pull the free Phi-3 model
ollama pull phi3
```

> You can also use `ollama pull mistral` or `ollama pull llama3` — all free.

---

### STEP 2: Set Up the Python Backend

```bash
cd backend
pip install -r requirements.txt
```

> First run will download:
> - Faster-Whisper base model (~150MB)
> - XTTS-v2 voice model (~2GB) — this clones your JARVIS voice
> - openWakeWord model (~50MB)
>
> **All one-time downloads. All free.**

---

### STEP 3: Start the Backend

```bash
cd backend
python main.py
```

You will see:
```
⚡ JARVIS AI — by CassimTV
✅ Ollama ready — using phi3
✅ Faster-Whisper STT ready
✅ Wake word engine ready — listening for 'Jarvis!'
✅ XTTS-v2 loaded — JARVIS voice cloned from your recordings
✅ JARVIS AI backend online
```

Note your machine's local IP address (e.g. `192.168.1.100`).

---

### STEP 4: Build the Flutter App

Install Flutter: https://flutter.dev/docs/get-started/install (free)

```bash
# In the project root
flutter pub get

# Build APK for Android mobile
flutter build apk --release

# Build APK for Android TV
flutter build apk --release --target-platform android-arm64
```

APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

---

### STEP 5: Configure the App

1. Install the APK on your phone or TV box
2. Open **JARVIS AI**
3. Go to **Settings**
4. Enter your backend IP address: `http://192.168.1.100:8000`
5. Save

> Both your phone/TV and the backend machine must be on the **same WiFi network**.

---

## Usage

| Action | How |
|---|---|
| Wake JARVIS | Say **"Jarvis!"** out loud |
| Ask a question | Speak after activation OR type in the text bar |
| System stats | Tap RAM / CPU / STORAGE / NETWORK buttons |
| View memories | Tap MEMORY in the sidebar |
| Adjust settings | Tap SETTINGS |

---

## Voice Cloning Notes

JARVIS will speak using the voice cloned from your 3 audio files:
- `jarvis_boot.mp3` — primary reference (best quality)
- `jarvis_request_root.mp3` — secondary reference
- `jarvis_app_closed.mp3` — additional texture

XTTS-v2 analyses all three and generates new speech in that voice.

---

## Troubleshooting

**"Backend Offline" in app**
→ Make sure `python main.py` is running
→ Check the IP address in Settings matches your machine's actual local IP
→ Both devices must be on the same WiFi

**Wake word not triggering**
→ Make sure your machine has a working microphone connected
→ Speak clearly: "Jarvis!" with a slight pause after

**Voice sounds wrong**
→ The XTTS-v2 model downloads on first use — wait for it to complete
→ Check the `backend/audio_cache/` folder — files should appear there

**Slow responses**
→ Ollama performance depends on your machine's RAM/CPU
→ For faster responses: `ollama pull phi3:mini` (smaller model)

---

## Project Structure

```
jarvis_ai/
├── lib/                    # Flutter app
│   ├── main.dart
│   ├── screens/            # UI screens
│   ├── widgets/            # UI components
│   ├── services/           # App logic
│   ├── models/             # Data models
│   └── utils/              # Constants
├── backend/                # Python backend
│   ├── main.py             # FastAPI server
│   ├── intelligence.py     # Ollama AI brain
│   ├── voice_engine.py     # XTTS-v2 voice cloning
│   ├── stt_engine.py       # Faster-Whisper STT
│   ├── wakeword_engine.py  # openWakeWord
│   ├── actions.py          # System commands
│   └── requirements.txt
├── assets/
│   └── audio/              # Your 3 voice recordings
└── android/
    └── app/src/main/
        └── AndroidManifest.xml
```

---

## JARVIS AI by CassimTV
*Built entirely with free, open-source tools.*
