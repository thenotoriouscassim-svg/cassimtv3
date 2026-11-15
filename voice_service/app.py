"""JARVIS XTTS-v2 voice clone running on Hugging Face ZeroGPU."""
import os
import secrets
import tempfile
import threading
from pathlib import Path

import gradio as gr
import spaces
import torch
from TTS.api import TTS

API_KEY = os.getenv("JARVIS_VOICE_API_KEY", "").strip()
SAMPLE_DIR = Path(__file__).parent / "samples"
SPEAKER_SAMPLES = [
    SAMPLE_DIR / "jarvis_boot.mp3",
    SAMPLE_DIR / "jarvis_request_root.mp3",
    SAMPLE_DIR / "jarvis_app_closed.mp3",
]
MODEL_NAME = "tts_models/multilingual/multi-dataset/xtts_v2"
_model = None
_model_lock = threading.Lock()


def get_model():
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                torch.set_num_threads(2)
                _model = TTS(MODEL_NAME, gpu=True)
    return _model


@spaces.GPU(duration=120)
def generate_speech(text: str, supplied_key: str):
    if not API_KEY:
        raise gr.Error("The voice service key is not configured.")
    if not secrets.compare_digest((supplied_key or "").strip(), API_KEY):
        raise gr.Error("Unauthorized voice request.")
    if not all(path.is_file() for path in SPEAKER_SAMPLES):
        raise gr.Error("One or more reference recordings are missing.")
    text = " ".join((text or "").split())
    if not text:
        raise gr.Error("Speech text is empty.")
    output_path = tempfile.mktemp(suffix=".wav")
    try:
        model = get_model()
        model.tts_to_file(
            text=text[:2500],
            speaker_wav=[str(path) for path in SPEAKER_SAMPLES],
            language="en",
            file_path=output_path,
            split_sentences=True,
        )
        if not os.path.isfile(output_path) or os.path.getsize(output_path) < 1000:
            raise RuntimeError("XTTS did not produce a valid audio file.")
        return output_path
    except Exception:
        try:
            os.remove(output_path)
        except OSError:
            pass
        raise


demo = gr.Interface(
    fn=generate_speech,
    inputs=[
        gr.Textbox(label="Text", lines=3, max_lines=8),
        gr.Textbox(label="Service key", visible=False),
    ],
    outputs=gr.Audio(label="JARVIS voice", type="filepath"),
    api_name="generate",
    title="JARVIS Voice Clone",
    description="Private XTTS-v2 voice generation for JARVIS AI by CassimTV.",
)


if __name__ == "__main__":
    demo.queue(max_size=8).launch()
