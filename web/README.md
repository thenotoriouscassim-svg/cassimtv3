# JARVIS Web

Static browser client for JARVIS AI by CassimTV.

## Deploy with Cloudflare Pages

1. Create a Pages project connected to this repository.
2. Set the production branch to `feature/jarvis-web` while testing, or merge the branch into the chosen production branch first.
3. Set the project root directory to `web`.
4. Leave the build command empty.
5. Set the build output directory to `.`.
6. Deploy. Cloudflare Pages will provide a `*.pages.dev` URL.
7. Add a custom domain in Pages when the final public hostname has been chosen.

## Backend

The client currently calls the existing JARVIS Worker at:

`https://jarvis-ai-cassimtv.ramancassim-764.workers.dev`

The web client uses the existing account API (`/auth/*`), chat sync (`/chats`), memories (`/memories`), AI chat (`/chat`), model availability (`/models`) and live search (`/search`).

## Browser capabilities

- Microphone input uses the browser's Web Speech API where supported (Chrome support is recommended).
- Spoken replies use the browser's speech synthesis.
- Browser device information is informational only. Android-specific device controls and Shizuku features remain in the Android app.

## Important before public launch

- Verify the production Worker is healthy and that its D1 binding and account schema are active.
- Test sign-up, login, password recovery, chat creation/sync, memories, model selection and search against the production API.
- The current API stores bearer sessions in browser local storage. For a larger public launch, consider moving browser authentication to secure, HttpOnly cookies with CSRF protection.
- Add privacy policy, terms, abuse controls and rate limits before opening registration widely.
