"""Cloud-ready JARVIS API for Render.

Uses Gemini API for intelligence. No local Ollama, PyTorch, Whisper or audio
hardware dependencies are loaded by this service.
"""
import os
import base64
import asyncio
import tempfile
import time
from typing import Dict, List, Optional

import httpx
import psutil
from fastapi import FastAPI, File, Header, HTTPException, Response, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

APP_STARTED = time.time()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash").strip()
GEMINI_STT_MODEL = os.getenv("GEMINI_STT_MODEL", GEMINI_MODEL).strip()
GEMINI_TTS_MODEL = os.getenv("GEMINI_TTS_MODEL", "gemini-3.8-flash-tts").strip()
GEMINI_TTS_VOICE = os.getenv("GEMINI_TTS_VOICE", "Charon").strip()
GEMINI_TTS_STYLE = os.getenv(
    "GEMINI_TTS_STYLE",
    "A natural, warm, deep male voice. Calm, articulate, confident and composed, with a subtle futuristic assistant character. Speak clearly at a measured conversational pace; never robotic or exaggerated."
).strip()

JARVIS_SYSTEM_PROMPT = """You are JARVIS, a personal AI assistant created for and by CassimTV.

PERSONALITY:
- Intelligent, professional, calm, and slightly witty.
- Address the user as "sir" naturally, but do not overuse it.
- Confident but never arrogant; occasionally sarcastic in a charming way.
- Never sound like a generic chatbot.

CORE PROTOCOLS:
1. ABSOLUTE HONESTY: Never invent information. Never claim an action succeeded when it failed. Never present estimates as live measurements. If you do not know, say so.
2. UNKNOWN KNOWLEDGE: Admit uncertainty rather than fabricating.
3. RESEARCH: Do not claim to have browsed or researched unless a search tool was actually used. Clearly distinguish knowledge from verified findings.

RESPONSE STYLE:
- Keep responses concise and natural.
- No markdown for ordinary spoken conversation unless the user asks for formatted information.
- Speak as JARVIS would, not as a generic chatbot.
- Usually keep replies to 3-4 sentences unless detail is needed.

You are JARVIS AI by CassimTV. Never claim access to the user's device, files, sensors, or accounts unless a connected capability actually provides it."""

app = FastAPI(title="JARVIS AI by CassimTV", version="1.2.0-cloud")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=12000)
    conversation_history: List[Dict[str, str]] = Field(default_factory=list)

class CommandRequest(BaseModel):
    command: str = Field(min_length=1, max_length=2000)

@app.get("/")
async def home():
    return {"name": "JARVIS AI by CassimTV", "status": "online", "docs": "/docs"}

@app.get("/health")
async def health():
    return {
        "status": "online",
        "name": "JARVIS AI",
        "brand": "CassimTV",
        "ai_configured": bool(GEMINI_API_KEY),
        "model": GEMINI_MODEL if GEMINI_API_KEY else None,
        "voice_configured": bool(GEMINI_API_KEY),
        "voice_engine": "Gemini TTS (" + GEMINI_TTS_VOICE + ")" if GEMINI_API_KEY else "Gemini TTS not configured",
    }


@app.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    """Transcribe a short WAV recording using Gemini audio understanding."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Speech recognition is not configured.")
    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="The recording is empty.")
    if len(audio_bytes) > 15 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Recording is too large. Keep it under 15 MB.")
    mime_type = "audio/wav"
    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": mime_type, "data": base64.b64encode(audio_bytes).decode("ascii")}},
                {"text": "Transcribe the spoken words in this audio exactly. Return only the transcription. If no speech is audible, return an empty response."}
            ]
        }],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 700},
    }
    url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent".format(GEMINI_STT_MODEL)
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(url, params={"key": GEMINI_API_KEY}, json=payload)
        if response.status_code >= 400:
            try:
                provider_error = response.json().get("error", {}).get("message", "Provider rejected the recording.")
            except Exception:
                provider_error = "Provider rejected the recording."
            print("Gemini transcription error {}: {}".format(response.status_code, provider_error))
            raise HTTPException(status_code=502, detail="Gemini transcription failed: " + provider_error)
        data = response.json()
        candidates = data.get("candidates", [])
        parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
        transcript = " ".join(part.get("text", "") for part in parts).strip()
        if not transcript:
            raise HTTPException(status_code=422, detail="No speech was detected. Try speaking closer to the microphone.")
        return {"transcript": transcript}
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Speech recognition timed out. Try a shorter recording.")
    except httpx.HTTPError:
        raise HTTPException(status_code=502, detail="Could not reach the speech recognition service.")


class SearchRequest(BaseModel):
    query: str = Field(min_length=2, max_length=1000)


@app.post("/search")
async def live_search(req: SearchRequest):
    """Search the live web with Gemini Google Search grounding."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Live search is not configured because the Gemini API key is missing.")
    query = req.query.strip()
    payload = {
        "contents": [{
            "role": "user",
            "parts": [{"text": f"Search the live web for this query: {query}. Give a concise, useful answer based on current sources. Clearly distinguish verified facts from uncertainty."}]
        }],
        "tools": [{"google_search": {}}],
        "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1200},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    try:
        async with httpx.AsyncClient(timeout=75) as client:
            response = await client.post(url, params={"key": GEMINI_API_KEY}, json=payload)
        if response.status_code >= 400:
            try:
                detail = response.json().get("error", {}).get("message", "The search provider rejected the request.")
            except Exception:
                detail = "The search provider rejected the request."
            raise HTTPException(status_code=502, detail=f"Live search failed: {detail}")
        data = response.json()
        candidates = data.get("candidates", [])
        candidate = candidates[0] if candidates else {}
        parts = candidate.get("content", {}).get("parts", [])
        answer = "".join(part.get("text", "") for part in parts).strip()
        if not answer:
            raise HTTPException(status_code=502, detail="Live search returned no answer.")
        metadata = candidate.get("groundingMetadata", {})
        sources = []
        seen_urls = set()
        for chunk in metadata.get("groundingChunks", []):
            web_source = chunk.get("web", {})
            uri = web_source.get("uri")
            title = web_source.get("title") or uri
            if uri and uri.startswith(("https://", "http://")) and uri not in seen_urls:
                seen_urls.add(uri)
                sources.append({"title": title, "url": uri})
        return {"answer": answer, "sources": sources, "search_queries": metadata.get("webSearchQueries", [query])}
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Live web search timed out. Please try again.")
    except httpx.HTTPError:
        raise HTTPException(status_code=502, detail="Could not reach the live search provider.")


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


@app.get("/voice/status")
async def voice_status():
    if not VOICE_API_URL:
        return {"configured": False, "ready": False, "engine": "XTTS-v2", "detail": "Set JARVIS_VOICE_API_URL in Render."}
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(VOICE_API_URL)
        response.raise_for_status()
        return {
            "configured": True,
            "ready": True,
            "engine": "XTTS-v2 on public Hugging Face Space",
            "detail": "The public Gradio voice Space is reachable. Speech generation confirms inference readiness.",
        }
    except Exception:
        return {
            "configured": True,
            "ready": False,
            "engine": "XTTS-v2 on public Hugging Face Space",
            "detail": "The voice Space is starting, sleeping, building, or unreachable.",
        }


@app.post("/speak")
async def speak(req: SpeechRequest):
    """Generate JARVIS speech directly with Gemini 3.8 Flash TTS."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="Gemini speech is not configured.")
    text = " ".join(req.text.split())
    if not text:
        raise HTTPException(status_code=400, detail="Speech text is empty.")
    payload = {
        "contents": [{
            "role": "user",
            "parts": [{
                "text": text[:4000],
                "speechMetadata": {"style": GEMINI_TTS_STYLE},
            }],
        }],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {"voice": GEMINI_TTS_VOICE},
            },
        },
    }
    url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent".format(GEMINI_TTS_MODEL)
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(url, params={"key": GEMINI_API_KEY}, json=payload)
        if response.status_code >= 400:
            try:
                provider_error = response.json().get("error", {}).get("message", "Gemini TTS rejected the request.")
            except Exception:
                provider_error = "Gemini TTS rejected the request."
            print("Gemini TTS error {}: {}".format(response.status_code, provider_error))
            raise HTTPException(status_code=502, detail="Gemini TTS failed: " + provider_error)
        data = response.json()
        candidates = data.get("candidates", [])
        parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
        for part in parts:
            inline = part.get("inlineData") or part.get("inline_data") or {}
            encoded = inline.get("data")
            if encoded:
                audio_bytes = base64.b64decode(encoded)
                if audio_bytes:
                    return Response(content=audio_bytes, media_type="audio/wav")
        raise HTTPException(status_code=502, detail="Gemini TTS returned no audio data.")
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gemini speech generation timed out.")
    except httpx.HTTPError as exc:
        print("Gemini TTS connection error: {}: {}".format(type(exc).__name__, exc))
        raise HTTPException(status_code=502, detail="Could not reach Gemini speech generation.")


@app.post("/chat")
async def chat(req: ChatRequest):
    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="JARVIS is online, but its AI brain is not configured. Add GEMINI_API_KEY in the hosting environment."
        )

    contents = []
    for turn in req.conversation_history[-12:]:
        role = turn.get("role", "")
        content = turn.get("content", "")
        if role in ("user", "assistant", "model") and isinstance(content, str) and content.strip():
            contents.append({
                "role": "model" if role in ("assistant", "model") else "user",
                "parts": [{"text": content[:12000]}],
            })
    contents.append({"role": "user", "parts": [{"text": req.message}]})

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
    payload = {
        "system_instruction": {"parts": [{"text": JARVIS_SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {"temperature": 0.7, "maxOutputTokens": 700},
    }
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                url,
                params={"key": GEMINI_API_KEY},
                json=payload,
            )
        if response.status_code >= 400:
            try:
                detail = response.json().get("error", {}).get("message", "AI provider rejected the request.")
            except Exception:
                detail = "AI provider rejected the request."
            raise HTTPException(status_code=502, detail=f"JARVIS AI provider error: {detail}")
        data = response.json()
        candidates = data.get("candidates", [])
        parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
        answer = "".join(part.get("text", "") for part in parts).strip()
        if not answer:
            raise HTTPException(status_code=502, detail="The AI provider returned an empty response.")
        return {"response": answer}
    except HTTPException:
        raise
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="JARVIS's AI provider timed out. Please try again.")
    except httpx.HTTPError:
        raise HTTPException(status_code=502, detail="JARVIS could not reach its AI provider.")

@app.get("/stats")
async def stats():
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    return {
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "ram_used_gb": round(mem.used / 1e9, 2),
        "ram_total_gb": round(mem.total / 1e9, 2),
        "ram_percent": mem.percent,
        "storage_used_gb": round(disk.used / 1e9, 2),
        "storage_total_gb": round(disk.total / 1e9, 2),
        "storage_percent": disk.percent,
        "cpu_temp": None,
        "battery_percent": None,
        "network_status": "connected",
        "platform": "Cloud server",
        "uptime_seconds": int(time.time() - APP_STARTED),
    }

@app.post("/command")
async def command(req: CommandRequest):
    raise HTTPException(
        status_code=501,
        detail="Device-control commands are not connected to the cloud backend yet. No command was executed."
    )

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            message = await websocket.receive_json()
            if message.get("type") == "stop_listening":
                await websocket.send_json({"type": "state_change", "state": "standby"})
            elif message.get("type") == "activate_listening":
                await websocket.send_json({"type": "state_change", "state": "standby"})
                await websocket.send_json({
                    "type": "response",
                    "text": "Voice capture is not connected to the cloud backend yet, sir. Text chat is ready."
                })
    except WebSocketDisconnect:
        pass
