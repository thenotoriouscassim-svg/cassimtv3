---
title: JARVIS Voice Clone
emoji: 🎙️
colorFrom: blue
colorTo: purple
sdk: docker
app_port: 7860
pinned: false
---

# JARVIS Voice Clone API

Private XTTS-v2 speech service for JARVIS AI by CassimTV. It uses the three
reference recordings supplied by the owner. Gemini remains on the Render API.

## API
- `GET /health` — service and sample status.
- `POST /speak` — JSON body `{"text":"..." }`, requires
  `Authorization: Bearer <JARVIS_VOICE_API_KEY>`, returns WAV audio.

## Space secret
Set `JARVIS_VOICE_API_KEY` in the Space settings. Use the exact same value
as the Render environment variable.

This service is intended for the owner's own voice recordings and private use.
XTTS-v2 is distributed under the Coqui Public Model License (CPML), which
restricts use to non-commercial purposes unless a separate commercial license
is obtained.
