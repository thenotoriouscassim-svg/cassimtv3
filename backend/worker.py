"""Cloudflare Python Workers entrypoint for the existing JARVIS FastAPI app.

Use the official WorkerEntrypoint env binding and ASGI adapter so secrets are
available before cloud_main reads its configuration.
"""
import os

from workers import WorkerEntrypoint


_ENV_NAMES = (
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
)


class Default(WorkerEntrypoint):
    async def fetch(self, request):
        # Cloudflare exposes variables and secrets through self.env.
        # Populate the shared app's existing configuration before importing it.
        for name in _ENV_NAMES:
            try:
                value = getattr(self.env, name, None)
            except Exception:
                value = None
            if value is not None:
                os.environ[name] = str(value)

        # Import only after environment bindings are copied: cloud_main reads
        # provider credentials at module import time.
        from cloud_main import app
        import asgi

        return await asgi.fetch(app, request.js_object, self.env)
