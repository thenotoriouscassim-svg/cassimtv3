---
title: JARVIS Voice Clone
emoji: 🎙️
colorFrom: blue
colorTo: purple
sdk: gradio
python_version: "3.10"
suggested_hardware: zero-a10g
pinned: false
---

# JARVIS Voice Clone

XTTS-v2 voice generation for JARVIS AI by CassimTV, running on Hugging Face ZeroGPU.

The service uses the three reference recordings supplied by the owner. The Render Gemini brain and `/chat` endpoint are separate and are not hosted here.

The Gradio API endpoint is `/generate`. It accepts the speech text and the private service key and returns generated WAV audio.

Set `JARVIS_VOICE_API_KEY` as a Space secret. The same value is used by the Render backend.

XTTS-v2 is distributed under the Coqui Public Model License (CPML), which restricts use to non-commercial purposes unless a separate commercial license is obtained.
