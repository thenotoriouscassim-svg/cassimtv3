"""Paired-device command relay for Cassim TV Remote.

Pairing state is intentionally in-memory for the first prototype. A Render
instance restart clears pairings, so clients must pair again after a restart.
Only an allowlisted set of TV actions can be relayed; arbitrary shell commands
are never accepted by this API.
"""
import asyncio
import hmac
import secrets
import time
import uuid
from typing import Dict, Literal, Optional

from fastapi import APIRouter, Header, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

router = APIRouter(prefix="/tv", tags=["Cassim TV Remote"])

PAIR_TTL_SECONDS = 300
COMMAND_ACK_TIMEOUT_SECONDS = 3.0

# Single-instance prototype state. Do not log pairing codes or access tokens.
_devices: Dict[str, dict] = {}
_pair_codes: Dict[str, str] = {}
_pending_acks: Dict[str, asyncio.Future] = {}
_pair_attempts: Dict[str, list] = {}


class PairClaim(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


class TVCommand(BaseModel):
    device_id: str = Field(min_length=1, max_length=80)
    action: Literal[
        "VOLUME_UP", "VOLUME_DOWN", "MUTE",
        "HOME", "BACK", "POWER",
        "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT", "OK",
    ]


def _clean_expired_pairs():
    now = time.monotonic()
    expired = [
        code for code, device_id in _pair_codes.items()
        if now - _devices.get(device_id, {}).get("pair_created", 0) > PAIR_TTL_SECONDS
    ]
    for code in expired:
        device_id = _pair_codes.pop(code, None)
        if device_id:
            device = _devices.get(device_id)
            if device and not device.get("paired"):
                _devices.pop(device_id, None)


def _check_pair_rate_limit(client_key: str):
    now = time.monotonic()
    attempts = [stamp for stamp in _pair_attempts.get(client_key, []) if now - stamp < 60]
    if len(attempts) >= 10:
        raise HTTPException(status_code=429, detail="Too many pairing attempts. Wait one minute and try again.")
    attempts.append(now)
    _pair_attempts[client_key] = attempts


def _bearer_token(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="A paired remote token is required.")
    return authorization[7:].strip()


@router.post("/pair/start")
async def start_pairing():
    """Called by the TV receiver to create a short-lived six-digit pairing code."""
    _clean_expired_pairs()
    device_id = str(uuid.uuid4())
    receiver_token = secrets.token_urlsafe(32)
    while True:
        code = f"{secrets.randbelow(1_000_000):06d}"
        if code not in _pair_codes:
            break

    _devices[device_id] = {
        "receiver_token": receiver_token,
        "remote_token": None,
        "paired": False,
        "pair_created": time.monotonic(),
        "socket": None,
    }
    _pair_codes[code] = device_id
    return {
        "device_id": device_id,
        "pairing_code": code,
        "receiver_token": receiver_token,
        "expires_in_seconds": PAIR_TTL_SECONDS,
        "websocket_path": f"/tv/receiver/{device_id}",
    }


@router.post("/pair/claim")
async def claim_pairing(req: PairClaim, authorization: Optional[str] = Header(default=None)):
    """Called by the phone after the user enters the code shown on the TV."""
    # Rate limit by a supplied client bearer identity when available. The
    # six-digit code is one-time and expires quickly; the phone receives a
    # separate high-entropy token after successful pairing.
    _check_pair_rate_limit("global")
    _clean_expired_pairs()
    device_id = _pair_codes.get(req.code)
    device = _devices.get(device_id or "")
    if not device or device.get("paired"):
        raise HTTPException(status_code=404, detail="Pairing code is invalid or expired.")

    remote_token = secrets.token_urlsafe(40)
    device["remote_token"] = remote_token
    device["paired"] = True
    _pair_codes.pop(req.code, None)
    return {"device_id": device_id, "remote_token": remote_token, "paired": True}


@router.websocket("/receiver/{device_id}")
async def receiver_socket(websocket: WebSocket, device_id: str, token: str = ""):
    """Persistent connection held open by the TV receiver."""
    device = _devices.get(device_id)
    if not device or not device.get("paired") or not hmac.compare_digest(
        str(device.get("receiver_token") or ""), token
    ):
        await websocket.close(code=1008)
        return

    await websocket.accept()
    old_socket = device.get("socket")
    if old_socket and old_socket is not websocket:
        try:
            await old_socket.close(code=4001)
        except Exception:
            pass
    device["socket"] = websocket

    try:
        while True:
            message = await websocket.receive_json()
            message_type = message.get("type") if isinstance(message, dict) else None
            if message_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif message_type == "ack":
                command_id = str(message.get("id", ""))
                future = _pending_acks.get(command_id)
                if future and not future.done():
                    future.set_result({
                        "ok": bool(message.get("ok", False)),
                        "detail": str(message.get("detail", ""))[:200],
                    })
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        if device.get("socket") is websocket:
            device["socket"] = None


@router.post("/command")
async def send_tv_command(req: TVCommand, authorization: Optional[str] = Header(default=None)):
    """Relay one allowlisted action and wait briefly for the TV's execution ACK."""
    token = _bearer_token(authorization)
    device = _devices.get(req.device_id)
    if not device or not device.get("paired") or not hmac.compare_digest(
        str(device.get("remote_token") or ""), token
    ):
        raise HTTPException(status_code=401, detail="This phone is not paired with that TV.")

    socket = device.get("socket")
    if socket is None:
        raise HTTPException(status_code=503, detail="The TV receiver is currently offline.")

    command_id = str(uuid.uuid4())
    future = asyncio.get_running_loop().create_future()
    _pending_acks[command_id] = future
    try:
        await socket.send_json({"type": "command", "id": command_id, "action": req.action})
        try:
            result = await asyncio.wait_for(future, timeout=COMMAND_ACK_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            raise HTTPException(status_code=504, detail="The TV did not acknowledge the command in time.")
        if not result["ok"]:
            raise HTTPException(status_code=502, detail=result["detail"] or "The TV could not execute that action.")
        return {"sent": True, "executed": True, "action": req.action}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=503, detail="The connection to the TV was interrupted.")
    finally:
        _pending_acks.pop(command_id, None)


@router.get("/status/{device_id}")
async def tv_status(device_id: str, authorization: Optional[str] = Header(default=None)):
    token = _bearer_token(authorization)
    device = _devices.get(device_id)
    if not device or not device.get("paired") or not hmac.compare_digest(
        str(device.get("remote_token") or ""), token
    ):
        raise HTTPException(status_code=401, detail="This phone is not paired with that TV.")
    return {"paired": True, "connected": device.get("socket") is not None}
