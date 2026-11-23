# JARVIS AI by CassimTV — Cloudflare Workers

The production JARVIS API is the Cloudflare-native JavaScript Worker in `worker.js`.
It preserves the Flutter app's API routes without Python/FastAPI cold-start overhead.

## Cloudflare Worker

- Worker name: `jarvis-ai-cassimtv`
- Root directory: `backend`
- Main module: `worker.js`
- Runtime: JavaScript Modules
- Build command: leave blank
- Deploy command: `npx wrangler deploy`

The Workers Builds project connects to `thenotoriouscassim-svg/cassimtv3` on branch `main`.

## D1 account storage

The Worker requires a D1 binding named `DB` pointing to `jarvis-accounts`.
The database contains the `users`, `sessions`, `chats`, `messages`, and `memories` tables.
The production binding is defined in `wrangler.jsonc`.

## Runtime secrets

Configure these under Worker **Settings → Variables and Secrets** as encrypted secrets:

- `GEMINI_API_KEY` — required for normal JARVIS v3 chat and search synthesis
- `GROQ_API_KEY` — optional JARVIS v1 and speech transcription
- `NVIDIA_API_KEY` — optional JARVIS v2 and advanced coding
- `OPENROUTER_API_KEY` — optional JARVIS v4
- `ZAI_API_KEY` — required for standard coding
- `FISH_API_KEY` — required for speech generation
- `FISH_AUDIO_VOICE_ID` — required for the selected JARVIS voice

Optional non-secret variables: `FISH_AUDIO_MODEL`, `GROQ_MODEL`, `NVIDIA_MODEL`, `OPENROUTER_MODEL`, `ZAI_CODE_MODEL`, and `NVIDIA_ADVANCED_CODE_MODEL`.

Never put API keys in `wrangler.jsonc`, GitHub commits, or chat messages.

## API smoke tests

After deployment, verify:

- `GET /health`
- `GET /diagnostics`
- `GET /models`
- `POST /chat`
- `GET /auth/me`
- `GET /chats`
- `GET /memories`

## Runtime note

The previous Python/FastAPI entrypoint exceeded the Cloudflare Workers Free CPU-time allowance during dependency imports. Production now uses the JavaScript Worker entrypoint. Keep `wrangler.jsonc` pointed at `worker.js`; do not deploy `worker.py` for the JARVIS API.
