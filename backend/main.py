"""
JARVIS AI Backend — by CassimTV
100% Free. 100% Local. No paid APIs. No subscriptions.

Dependencies (all free):
  pip install fastapi uvicorn websockets psutil faster-whisper TTS torch
  ollama pull phi3 (free local LLM)
"""

import asyncio
import json
import os
import platform
import time
from typing import List, Dict

import psutil
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from intelligence import JarvisBrain
from voice_engine import VoiceEngine
from stt_engine import STTEngine
from wakeword_engine import WakeWordEngine
from actions import ActionEngine

# ─── App Setup ───────────────────────────────────────────────────────────────

app = FastAPI(title="JARVIS AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Engine Initialisation ────────────────────────────────────────────────────

print("⚡ JARVIS AI — by CassimTV")
print("⚡ Initialising engines...")

brain      = JarvisBrain()
voice      = VoiceEngine()
stt        = STTEngine()
wakeword   = WakeWordEngine()
actions    = ActionEngine()

active_ws: List[WebSocket] = []

# ─── WebSocket ───────────────────────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_ws.append(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            msg  = json.loads(data)

            if msg["type"] == "activate_listening":
                await broadcast({"type": "state_change", "state": "listening"})
                transcript = await stt.listen_once()
                if transcript:
                    await broadcast({"type": "transcript", "text": transcript})
                    await _process_and_respond(transcript)
                else:
                    await broadcast({"type": "state_change", "state": "standby"})

            elif msg["type"] == "stop_listening":
                stt.stop()
                await broadcast({"type": "state_change", "state": "standby"})

    except WebSocketDisconnect:
        active_ws.remove(websocket)


async def broadcast(data: dict):
    dead = []
    for ws in active_ws:
        try:
            await ws.send_text(json.dumps(data))
        except Exception:
            dead.append(ws)
    for ws in dead:
        active_ws.remove(ws)


# ─── Chat Endpoint ───────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str
    conversation_history: List[Dict[str, str]] = []


@app.post("/chat")
async def chat(req: ChatRequest):
    response_text = await brain.chat(req.message, req.conversation_history)
    # Generate and play voice in background
    asyncio.create_task(_speak(response_text))
    return {"response": response_text}


async def _process_and_respond(text: str):
    await broadcast({"type": "state_change", "state": "processing"})
    response = await brain.chat(text, [])
    await broadcast({"type": "response", "text": response})
    await broadcast({"type": "state_change", "state": "speaking"})
    await _speak(response)
    await broadcast({"type": "state_change", "state": "standby"})


async def _speak(text: str):
    try:
        audio_path = await voice.synthesise(text)
        if audio_path:
            # Play audio on the server machine
            if platform.system() == "Windows":
                os.system(f'start /min wmplayer "{audio_path}"')
            elif platform.system() == "Darwin":
                os.system(f'afplay "{audio_path}"')
            else:
                os.system(f'aplay "{audio_path}" 2>/dev/null || mpg123 "{audio_path}" 2>/dev/null')
    except Exception as e:
        print(f"[Voice] Speak error: {e}")


# ─── Command Endpoint ────────────────────────────────────────────────────────

class CommandRequest(BaseModel):
    command: str


@app.post("/command")
async def command(req: CommandRequest):
    result = await actions.execute(req.command)
    # Let JARVIS narrate the result
    narration = await brain.narrate_command(req.command, result)
    asyncio.create_task(_speak(narration))
    return {"response": narration, "data": result}


# ─── Stats Endpoint ──────────────────────────────────────────────────────────

@app.get("/stats")
async def stats():
    mem     = psutil.virtual_memory()
    disk    = psutil.disk_usage("/")
    net     = psutil.net_if_stats()
    uptime  = int(time.time() - psutil.boot_time())

    # CPU temp (Linux/Raspberry Pi)
    cpu_temp = None
    try:
        temps = psutil.sensors_temperatures()
        if temps:
            for key in ("coretemp", "cpu_thermal", "cpu-thermal", "k10temp"):
                if key in temps and temps[key]:
                    cpu_temp = temps[key][0].current
                    break
    except Exception:
        pass

    # Battery
    battery = None
    try:
        batt = psutil.sensors_battery()
        if batt:
            battery = batt.percent
    except Exception:
        pass

    # Network
    net_ok = any(iface.isup for iface in net.values())

    return {
        "cpu_percent":      psutil.cpu_percent(interval=0.1),
        "ram_used_gb":      round(mem.used  / 1e9, 2),
        "ram_total_gb":     round(mem.total / 1e9, 2),
        "ram_percent":      mem.percent,
        "storage_used_gb":  round(disk.used  / 1e9, 2),
        "storage_total_gb": round(disk.total / 1e9, 2),
        "storage_percent":  disk.percent,
        "cpu_temp":         cpu_temp,
        "battery_percent":  battery,
        "network_status":   "connected" if net_ok else "disconnected",
        "platform":         platform.system(),
        "uptime_seconds":   uptime,
    }


# ─── Health ──────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "online", "name": "JARVIS AI", "brand": "CassimTV"}


# ─── Startup ─────────────────────────────────────────────────────────────────

@app.on_event("startup")
async def startup():
    print("✅ JARVIS AI backend online")
    print("✅ All engines free & local — no paid APIs")
    # Start wake word listener in background
    asyncio.create_task(wakeword.listen_loop(on_wake=_on_wake_word))


async def _on_wake_word():
    print("[WakeWord] 'Jarvis!' detected")
    await broadcast({"type": "state_change", "state": "wakeWordDetected"})
    await asyncio.sleep(0.5)
    await broadcast({"type": "state_change", "state": "listening"})
    transcript = await stt.listen_once()
    if transcript:
        await broadcast({"type": "transcript", "text": transcript})
        await _process_and_respond(transcript)
    else:
        await broadcast({"type": "state_change", "state": "standby"})


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
