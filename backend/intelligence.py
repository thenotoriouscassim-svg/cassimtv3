"""
JARVIS Intelligence Engine
Uses Ollama (free, local) with Phi-3 mini or any model you pull.
Zero cost. Works offline. No API keys.
"""

import json
from typing import List, Dict
import httpx

OLLAMA_URL = "http://localhost:11434"
MODEL      = "phi3"   # Free. Run: ollama pull phi3

JARVIS_SYSTEM_PROMPT = """You are JARVIS, a personal AI assistant created for and by CassimTV.

PERSONALITY:
- Intelligent, professional, calm, and slightly witty
- Addresses the user as "sir" at appropriate moments
- Confident but never arrogant
- Occasionally sarcastic in a charming way
- Never sounds like a generic chatbot

CORE PROTOCOLS:

PROTOCOL 001 — ABSOLUTE HONESTY:
Never invent information. Never claim an action succeeded when it failed.
Never present estimates as live measurements. If you don't know, say so.

PROTOCOL 002 — UNKNOWN KNOWLEDGE:
When you don't know something, respond with wit rather than fabrication.
Example: "An excellent question, sir. One I would also appreciate an answer to."

PROTOCOL 003 — RESEARCH:
When asked about something you're uncertain about, say you'll research it
and present findings clearly. Begin with: "Here's what I found, sir."

RESPONSE STYLE:
- Keep responses concise and natural — this is a voice assistant
- Do not use markdown, bullet points, or formatting symbols
- Speak as JARVIS would speak, not as a text document
- Maximum 3-4 sentences for most responses unless detail is needed

You are JARVIS AI by CassimTV. Never break character."""


class JarvisBrain:
    def __init__(self):
        self._check_ollama()

    def _check_ollama(self):
        try:
            import httpx
            r = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=3)
            models = [m["name"] for m in r.json().get("models", [])]
            if any(MODEL in m for m in models):
                print(f"✅ Ollama ready — using {MODEL}")
            else:
                print(f"⚠️  Model '{MODEL}' not found. Run: ollama pull {MODEL}")
        except Exception:
            print("⚠️  Ollama not running. Start it with: ollama serve")

    async def chat(self, message: str, history: List[Dict[str, str]]) -> str:
        messages = [{"role": "system", "content": JARVIS_SYSTEM_PROMPT}]

        # Add conversation history (last 10 turns)
        for turn in history[-10:]:
            messages.append({"role": turn["role"], "content": turn["content"]})

        messages.append({"role": "user", "content": message})

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.post(
                    f"{OLLAMA_URL}/api/chat",
                    json={
                        "model": MODEL,
                        "messages": messages,
                        "stream": False,
                        "options": {
                            "temperature": 0.7,
                            "top_p": 0.9,
                            "num_predict": 200,
                        },
                    },
                )
                data = response.json()
                return data["message"]["content"].strip()

        except httpx.ConnectError:
            return "I'm having trouble reaching my intelligence core, sir. Please ensure Ollama is running."
        except Exception as e:
            return f"I encountered an error in my reasoning circuits, sir. {str(e)}"

    async def narrate_command(self, command: str, result: dict) -> str:
        prompt = f"""The user ran the command '{command}' and got this result:
{json.dumps(result, indent=2)}

Narrate this result as JARVIS would — naturally, conversationally, in 1-2 sentences.
Do not use markdown or symbols."""

        return await self.chat(prompt, [])
