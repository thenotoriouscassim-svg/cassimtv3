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
        "voice_configured": True,
        "voice_engine": "Edge Neural TTS (temporary voice; voice cloning not configured)",
    }


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


@app.post("/speak")
async def speak(req: SpeechRequest):
    """Generate speech with a lightweight neural voice service.

    This is a temporary speaking voice, not a clone of the supplied recordings.
    XTTS-v2 cloning needs a larger server than the current Render free instance.
    """
    import tempfile
    import edge_tts

    text = " ".join(req.text.split())
    if not text:
        raise HTTPException(status_code=400, detail="Speech text is empty.")

    voice = os.getenv("JARVIS_TTS_VOICE", "en-GB-RyanNeural").strip()
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as temp:
            temp_path = temp.name
        communicate = edge_tts.Communicate(text, voice)
        await communicate.save(temp_path)
        with open(temp_path, "rb") as audio_file:
            audio = audio_file.read()
        if not audio:
            raise HTTPException(status_code=502, detail="The speech service returned empty audio.")
        return Response(content=audio, media_type="audio/mpeg")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Speech generation failed: {str(exc)[:300]}")
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass

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
