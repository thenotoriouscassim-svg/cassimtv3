# JARVIS AI by CassimTV — Cloudflare Workers

This directory contains the Cloudflare Python Workers entrypoint for the existing FastAPI backend.

## Cloudflare Worker settings

- Worker name: `jarvis-ai-cassimtv`
- Root directory: `backend`
- Main module: `worker.py` (configured in `wrangler.jsonc`)
- Runtime: Python Workers with FastAPI ASGI adapter
- Build command: leave blank
- Deploy command:

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh && "$HOME/.local/bin/uv" run pywrangler deploy
```

The Workers Builds project should connect to the GitHub repository
`thenotoriouscassim-svg/cassimtv3` on branch `main`.

## Runtime secrets

Add these under the Worker **Settings → Variables and Secrets** as encrypted secrets:

- `GEMINI_API_KEY` — required for normal chat and Gemini web search
- `ZAI_API_KEY` — required for the separate coding endpoint
- `FISH_API_KEY` — required for speech generation
- `FISH_AUDIO_VOICE_ID` — required for the selected JARVIS voice

Optional non-secret variable:

- `FISH_AUDIO_MODEL` — defaults to `s2.1-pro-free`

Do not put API keys in `wrangler.jsonc`, GitHub commits, or chat messages.
The Worker entrypoint bridges Cloudflare's `workers.env` bindings into the
shared backend configuration before importing the FastAPI app.

## Compatibility notes

- Render continues using `requirements.txt` and `psutil`; the Render deployment is not replaced by these files.
- Cloudflare Workers does not expose host CPU, RAM, or disk counters. The shared `/stats` route returns null for those fields on Workers rather than inventing values.
- The Android device bridge remains on the phone and is unchanged.
- The normal `/chat` route remains on the existing Gemini Flash-Lite configuration. The separate `/code` route remains the Z.ai coding endpoint.
- Test `/health`, `/chat`, `/code`, `/search`, and `/tts` before changing the Android app's backend URL.

## Free-plan limitation

Cloudflare Workers Free has a 10 ms CPU-time allowance per request. Network waiting is separate from CPU time, but Python/FastAPI startup and request processing must still fit. Confirm this with live endpoint tests before moving production traffic.
