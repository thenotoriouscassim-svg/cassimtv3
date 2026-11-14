"""
JARVIS Wake Word Engine
Uses openWakeWord — free, offline, open source.
Listens for "Jarvis!" continuously in the background.

Install: pip install openwakeword sounddevice numpy
"""

import asyncio
import numpy as np
from typing import Callable, Awaitable

WAKE_WORD_MODEL = "hey_jarvis"  # Built-in model in openWakeWord
THRESHOLD       = 0.5
SAMPLE_RATE     = 16000
CHUNK_SIZE      = 1280          # ~80ms at 16kHz


class WakeWordEngine:
    def __init__(self):
        self._model = None
        self._running = False
        self._load()

    def _load(self):
        try:
            import openwakeword
            from openwakeword.model import Model
            # Download free pre-trained models on first run
            openwakeword.utils.download_models()
            self._model = Model(wakeword_models=[WAKE_WORD_MODEL], inference_framework="onnx")
            print(f"✅ Wake word engine ready — listening for 'Jarvis!'")
        except ImportError:
            print("⚠️  openwakeword not installed. Run: pip install openwakeword")
        except Exception as e:
            print(f"⚠️  Wake word engine error: {e}")

    async def listen_loop(self, on_wake: Callable[[], Awaitable[None]]):
        """Continuously listen for the wake word in the background."""
        if self._model is None:
            print("[WakeWord] Engine not available — wake word disabled")
            return

        self._running = True
        loop = asyncio.get_event_loop()

        while self._running:
            detected = await loop.run_in_executor(None, self._listen_chunk)
            if detected:
                self._running = False  # Pause while handling
                try:
                    await on_wake()
                finally:
                    await asyncio.sleep(1)  # Cooldown
                    self._running = True

    def _listen_chunk(self) -> bool:
        """Listen for one chunk and return True if wake word detected."""
        try:
            import sounddevice as sd

            audio_chunk = sd.rec(
                CHUNK_SIZE,
                samplerate=SAMPLE_RATE,
                channels=1,
                dtype="int16",
                blocking=True,
            )
            audio_flat = audio_chunk.flatten()
            prediction = self._model.predict(audio_flat)

            score = prediction.get(WAKE_WORD_MODEL, 0)
            if isinstance(score, (list, np.ndarray)):
                score = float(score[-1])

            return score >= THRESHOLD

        except Exception:
            return False

    def stop(self):
        self._running = False
