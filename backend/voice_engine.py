"""
JARVIS Voice Engine
Uses Coqui XTTS-v2 — free, local, open source voice cloning.
Clones the voice from your 3 audio recordings.
No ElevenLabs. No API key. No cost.

Install: pip install TTS torch torchaudio
"""

import os
import asyncio
import tempfile
from pathlib import Path

VOICE_SAMPLES_DIR = Path(__file__).parent.parent / "assets" / "audio"
VOICE_SAMPLES = [
    str(VOICE_SAMPLES_DIR / "jarvis_boot.mp3"),        # Best quality: 33.6dB SNR
    str(VOICE_SAMPLES_DIR / "jarvis_request_root.mp3"), # Good: 27dB SNR
    str(VOICE_SAMPLES_DIR / "jarvis_app_closed.mp3"),   # Marginal but adds texture
]
OUTPUT_DIR = Path(__file__).parent / "audio_cache"
OUTPUT_DIR.mkdir(exist_ok=True)


class VoiceEngine:
    def __init__(self):
        self._tts = None
        self._ready = False
        self._load()

    def _load(self):
        try:
            from TTS.api import TTS
            print("🔊 Loading XTTS-v2 voice model (first run downloads ~2GB — free)...")
            self._tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)
            # Verify voice samples exist
            missing = [f for f in VOICE_SAMPLES if not os.path.exists(f)]
            if missing:
                print(f"⚠️  Missing voice samples: {missing}")
            else:
                self._ready = True
                print("✅ XTTS-v2 loaded — JARVIS voice cloned from your recordings")
        except ImportError:
            print("⚠️  TTS not installed. Run: pip install TTS torch torchaudio")
        except Exception as e:
            print(f"⚠️  Voice engine error: {e}")

    async def synthesise(self, text: str) -> str | None:
        """Generate speech using cloned voice. Returns path to audio file."""
        if not self._ready or not self._tts:
            print(f"[Voice] Would say: {text}")
            return None

        # Clean text for TTS
        text = self._clean(text)
        if not text:
            return None

        try:
            output_path = str(OUTPUT_DIR / f"response_{hash(text) % 99999}.wav")

            # Run in thread pool to avoid blocking async loop
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(
                None,
                self._generate,
                text,
                output_path,
            )
            return output_path
        except Exception as e:
            print(f"[Voice] Synthesis error: {e}")
            return None

    def _generate(self, text: str, output_path: str):
        # Use the best quality sample as primary, others for reference
        speaker_wav = [f for f in VOICE_SAMPLES if os.path.exists(f)]
        if not speaker_wav:
            raise FileNotFoundError("No voice samples found")

        self._tts.tts_to_file(
            text=text,
            speaker_wav=speaker_wav,
            language="en",
            file_path=output_path,
        )

    def _clean(self, text: str) -> str:
        """Remove markdown and symbols that sound bad when spoken."""
        import re
        text = re.sub(r'[*_`#\[\]()]', '', text)
        text = re.sub(r'\s+', ' ', text)
        return text.strip()
