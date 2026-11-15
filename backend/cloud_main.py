"""Cloud-ready JARVIS API for Render.

Uses Gemini API for intelligence. No local Ollama, PyTorch, Whisper or audio
hardware dependencies are loaded by this service.
"""
import os
import time
from typing import Dict, List, Optional

import httpx
import psutil
from fastapi import FastAPI, Header, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

APP_STARTED = time.time()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash").strip()
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY", "").strip()
ELEVENLABS_VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID", "").strip()
VOICE_SETUP_TOKEN = os.getenv("VOICE_SETUP_TOKEN", "").strip()
VOICE_SAMPLE_BASE = "https://raw.githubusercontent.com/thenotoriouscassim-svg/cassimtv3/main/assets/audio"

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

app = FastAPI(title="JARVIS AI by CassimTV", version="1.1.0-cloud")
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
        "voice_configured": bool(ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID),
    }


@app.post("/voice/clone")
async def clone_reference_voice(x_setup_token: str = Header(default="")):
    """Create the JARVIS voice from the three repository reference recordings.

    Configure ELEVENLABS_API_KEY and VOICE_SETUP_TOKEN in Render first.
    Save the returned voice_id as ELEVENLABS_VOICE_ID in Render afterwards.
    """
    global ELEVENLABS_VOICE_ID
    if not ELEVENLABS_API_KEY:
        raise HTTPException(status_code=503, detail="Add ELEVENLABS_API_KEY to the Render environment first.")
    if not VOICE_SETUP_TOKEN or x_setup_token != VOICE_SETUP_TOKEN:
        raise HTTPException(status_code=403, detail="Voice setup token is missing or incorrect.")
    if ELEVENLABS_VOICE_ID:
        return {"status": "already_configured", "voice_id": ELEVENLABS_VOICE_ID}

    sample_names = [
        "jarvis_boot.mp3",
        "jarvis_request_root.mp3",
        "jarvis_app_closed.mp3",
    ]
    try:
        async with httpx.AsyncClient(timeout=60, follow_redirects=True) as client:
            uploads = []
            for filename in sample_names:
                sample = await client.get(f"{VOICE_SAMPLE_BASE}/{filename}")
                sample.raise_for_status()
                uploads.append(("files", (filename, sample.content, "audio/mpeg")))
            result = await client.post(
                "https://api.elevenlabs.io/v1/voices/add",
                headers={"xi-api-key": ELEVENLABS_API_KEY},
                data={
                    "name": "JARVIS AI by CassimTV",
                    "description": "Voice clone created from the three supplied JARVIS reference recordings.",
                    "remove_background_noise": "false",
                },
                files=uploads,
            )
        if result.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Voice cloning provider error: {result.text[:700]}")
        payload = result.json()
        voice_id = payload.get("voice_id")
        if not voice_id:
            raise HTTPException(status_code=502, detail="Voice provider did not return a voice ID.")
        ELEVENLABS_VOICE_ID = voice_id
        return {
            "status": "created",
            "voice_id": voice_id,
            "requires_verification": payload.get("requires_verification", False),
            "next_step": "Save this voice ID as ELEVENLABS_VOICE_ID in Render, then redeploy.",
        }
    except HTTPException:
        raise
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Could not retrieve the three reference recordings: {exc}")

class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)

@app.post("/speak")
async def speak(req: SpeechRequest):
    if not ELEVENLABS_API_KEY or not ELEVENLABS_VOICE_ID:
        raise HTTPException(status_code=503, detail="The JARVIS reference voice has not been configured yet.")
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            result = await client.post(
                f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE_ID}",
                params={"output_format": "mp3_44100_128"},
                headers={
                    "xi-api-key": ELEVENLABS_API_KEY,
                    "Content-Type": "application/json",
                },
                json={
                    "text": req.text,
                    "model_id": "eleven_flash_v2_5",
                    "voice_settings": {
                        "stability": 0.55,
                        "similarity_boost": 0.85,
                        "style": 0.15,
                        "use_speaker_boost": True,
                    },
                },
            )
        if result.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Voice synthesis failed: {result.text[:500]}")
        return Response(content=result.content, media_type="audio/mpeg")
    except HTTPException:
        raise
    except httpx.HTTPError:
        raise HTTPException(status_code=502, detail="JARVIS could not reach the voice synthesis service.")

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
