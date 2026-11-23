"""Cassim TV Remote relay service.

The JARVIS application has moved to Cloudflare. This Render service is now
reserved for Cassim TV Remote pairing and low-latency command relaying.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from tv_remote import router as tv_remote_router

app = FastAPI(title="Cassim TV Remote Relay", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)
app.include_router(tv_remote_router)


@app.get("/")
async def home():
    return {
        "name": "Cassim TV Remote Relay",
        "status": "online",
        "service": "device-pairing-and-command-relay",
    }


@app.get("/health")
async def health():
    return {"status": "online", "service": "cassim-tv-remote"}
