"""
JARVIS Speech-to-Text Engine
Uses Faster-Whisper — free, offline, runs locally.
No Google Speech API. No paid service.

Install: pip install faster-whisper sounddevice numpy
"""

import asyncio
import io
import wave
import tempfile
import numpy as np

SAMPLE_RATE    = 16000
SILENCE_THRESH = 0.01
SILENCE_SECS   = 1.5     # Stop after 1.5s of silence
MAX_LISTEN     = 15      # Max recording seconds


class STTEngine:
    def __init__(self):
        self._model = None
        self._listening = False
        self._load()

    def _load(self):
        try:
            from faster_whisper import WhisperModel
            # "base.en" is small, fast, English-only, free
            self._model = WhisperModel("base.en", device="cpu", compute_type="int8")
            print("✅ Faster-Whisper STT ready (base.en model)")
        except ImportError:
            print("⚠️  faster-whisper not installed. Run: pip install faster-whisper")
        except Exception as e:
            print(f"⚠️  STT engine error: {e}")

    async def listen_once(self) -> str | None:
        """Record from microphone until silence, then transcribe."""
        self._listening = True
        loop = asyncio.get_event_loop()

        try:
            audio_data = await loop.run_in_executor(None, self._record)
            if audio_data is None:
                return None
            transcript = await loop.run_in_executor(None, self._transcribe, audio_data)
            return transcript
        finally:
            self._listening = False

    def _record(self) -> np.ndarray | None:
        try:
            import sounddevice as sd

            print("[STT] Listening...")
            recorded = []
            silence_count = 0
            chunk_size = int(SAMPLE_RATE * 0.1)  # 100ms chunks

            with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype='float32') as stream:
                total_chunks = 0
                max_chunks = int(MAX_LISTEN / 0.1)

                while self._listening and total_chunks < max_chunks:
                    chunk, _ = stream.read(chunk_size)
                    recorded.append(chunk.copy())
                    total_chunks += 1

                    # Check for silence
                    rms = np.sqrt(np.mean(chunk ** 2))
                    if rms < SILENCE_THRESH:
                        silence_count += 1
                        if silence_count >= int(SILENCE_SECS / 0.1) and total_chunks > 10:
                            break
                    else:
                        silence_count = 0

            if not recorded:
                return None

            audio = np.concatenate(recorded, axis=0).flatten()
            return audio

        except ImportError:
            print("⚠️  sounddevice not installed. Run: pip install sounddevice")
            return None
        except Exception as e:
            print(f"[STT] Record error: {e}")
            return None

    def _transcribe(self, audio: np.ndarray) -> str | None:
        if self._model is None:
            return None
        try:
            # Save to temp wav for whisper
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                tmp_path = f.name

            with wave.open(tmp_path, 'w') as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(SAMPLE_RATE)
                wf.writeframes((audio * 32767).astype(np.int16).tobytes())

            segments, _ = self._model.transcribe(tmp_path, language="en", vad_filter=True)
            text = " ".join(s.text for s in segments).strip()

            import os
            os.unlink(tmp_path)

            print(f"[STT] Heard: {text}")
            return text if text else None

        except Exception as e:
            print(f"[STT] Transcribe error: {e}")
            return None

    def stop(self):
        self._listening = False
