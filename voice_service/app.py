"""Private JARVIS XTTS-v2 voice service for Hugging Face Spaces."""
import os
import secrets
import tempfile
import threading
from pathlib import Path

import torch
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask

API_KEY = os.getenv("JARVIS_VOICE_API_KEY", "").strip()
SAMPLE_DIR = Path("/app/samples")
SPEAKER_SAMPLES = [
    SAMPLE_DIR / "jarvis_boot.mp3",
    SAMPLE_DIR / "jarvis_request_root.mp3",
    SAMPLE_DIR / "jarvis_app_closed.mp3",
]
MODEL_NAME = "tts_models/multilingual/multi-dataset/xtts_v2"

app = FastAPI(title="JARVIS Voice Clone API", version="1.0.0")
_model = None
_model_lock = threading.Lock()
_generation_lock = threading.Lock()


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2500)


def get_model():
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                torch.set_num_threads(max(1, min(4, os.cpu_count() or 1)))
                from TTS.api import TTS
                _model = TTS(MODEL_NAME, gpu=False)
    return _model


def remove_file(path: str):
    try:
        os.remove(path)
    except OSError:
        pass


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "engine": "Coqui XTTS-v2",
        "model_loaded": _model is not None,
        "samples_ready": all(path.is_file() for path in SPEAKER_SAMPLES),
    }


@app.post("/speak")
async def speak(request: SpeakRequest, authorization: str | None = Header(default=None)):
    if not API_KEY:
        raise HTTPException(status_code=503, detail="Voice API key is not configured.")
    supplied = authorization.removeprefix("Bearer ").strip() if authorization else ""
    if not secrets.compare_digest(supplied, API_KEY):
        raise HTTPException(status_code=401, detail="Invalid voice API key.")
    if not all(path.is_file() for path in SPEAKER_SAMPLES):
        raise HTTPException(status_code=503, detail="One or more reference recordings are missing.")

    text = " ".join(request.text.split())
    if not text:
        raise HTTPException(status_code=400, detail="Speech text is empty.")

    handle, output_path = tempfile.mkstemp(suffix=".wav")
    os.close(handle)
    try:
        model = get_model()
        with _generation_lock:
            model.tts_to_file(
                text=text,
                speaker_wav=[str(path) for path in SPEAKER_SAMPLES],
                language="en",
                file_path=output_path,
                split_sentences=True,
            )
        if not os.path.isfile(output_path) or os.path.getsize(output_path) < 1000:
            raise RuntimeError("XTTS did not produce a valid audio file.")
        return FileResponse(
            output_path,
            media_type="audio/wav",
            filename="jarvis-voice.wav",
            background=BackgroundTask(remove_file, output_path),
        )
    except HTTPException:
        remove_file(output_path)
        raise
    except Exception as exc:
        remove_file(output_path)
        raise HTTPException(status_code=500, detail=f"XTTS speech generation failed: {str(exc)[:240]}")
