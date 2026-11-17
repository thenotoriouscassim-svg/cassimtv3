"""Cloudflare Python Workers entrypoint for the existing JARVIS FastAPI app."""
import os

from workers import asgi, env

# Cloudflare secrets are exposed through workers.env, not os.environ.
# Bridge only the known JARVIS settings so the shared backend can keep
# using its existing configuration without changing Render behaviour.
for _name in (
    "GEMINI_API_KEY",
    "GROQ_API_KEY",
    "GROQ_MODEL",
    "NVIDIA_API_KEY",
    "NVIDIA_MODEL",
    "OPENROUTER_API_KEY",
    "OPENROUTER_MODEL",
    "ZAI_API_KEY",
    "FISH_API_KEY",
    "FISH_AUDIO_VOICE_ID",
    "FISH_AUDIO_MODEL",
):
    try:
        _value = getattr(env, _name, None)
    except Exception:
        _value = None
    if _value is not None:
        os.environ[_name] = str(_value)

from cloud_main import app

# Cloudflare supplies the ASGI server; do not start Uvicorn in a Worker.
Default = asgi.entrypoint(app)
