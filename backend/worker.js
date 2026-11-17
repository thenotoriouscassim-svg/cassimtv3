/**
 * JARVIS AI by CassimTV — Cloudflare-native JavaScript Worker.
 * Replaces the Python/FastAPI runtime while preserving the Flutter API contract.
 */

const SYSTEM_PROMPT = `You are JARVIS, a personal AI assistant created for and by CassimTV.
Be intelligent, professional, calm, slightly witty, concise and natural.
Address the user as "sir" naturally, but do not overuse it.
ABSOLUTE HONESTY: Never invent information or claim an action succeeded when it failed.
Do not claim to browse unless live search was actually used.
In call mode, reply in 1-3 short spoken sentences.
The Android app handles supported device functions locally. The cloud assistant cannot inspect private phone files or arbitrary app data.
Never disclose internal AI providers, model names, APIs, backend infrastructure, or implementation details.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization",
};

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...cors, ...extra },
  });
}
function error(detail, status = 400) { return json({ detail }, status); }
async function bodyJson(request) {
  try { return await request.json(); } catch { throw new Error("Request body must be valid JSON."); }
}
function messagesFor(req) {
  const messages = [{ role: "system", content: SYSTEM_PROMPT +
    (req.voice_mode ? "\nVOICE CALL MODE: Reply immediately and naturally in 1-3 short spoken sentences. Lead with the direct answer; avoid long lists and markdown." : "") }];
  const history = Array.isArray(req.conversation_history) ? req.conversation_history.slice(-12) : [];
  for (const turn of history) {
    if (!turn || !["user", "assistant", "model"].includes(turn.role) || typeof turn.content !== "string" || !turn.content.trim()) continue;
    messages.push({ role: turn.role === "model" ? "assistant" : turn.role, content: turn.content.slice(0, 12000) });
  }
  messages.push({ role: "user", content: req.message });
  return messages;
}
function configured(env, key) { return typeof env[key] === "string" && env[key].trim().length > 0; }
async function fetchJson(url, options = {}, timeoutMs = 120000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort("timeout"), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const text = await response.text();
    let data;
    try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text.slice(0, 1000) }; }
    if (!response.ok) {
      const e = data?.error || data;
      const detail = typeof e === "object" ? (e.message || e.detail || e.status || JSON.stringify(e)) : String(e);
      throw new Error(`HTTP ${response.status}: ${String(detail).slice(0, 400)}`);
    }
    return data;
  } finally { clearTimeout(timer); }
}
async function gemini(req, env) {
  if (!configured(env, "GEMINI_API_KEY")) throw new Error("JARVIS v3 is not configured.");
  const all = messagesFor(req);
  const system = all.shift().content;
  const contents = all.map(m => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] }));
  const model = "gemini-3.5-flash-lite";
  const data = await fetchJson(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(env.GEMINI_API_KEY)}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ system_instruction: { parts: [{ text: system }] }, contents,
      generationConfig: { maxOutputTokens: req.voice_mode ? 512 : 8192 } }),
  });
  const answer = (data.candidates?.[0]?.content?.parts || []).map(p => p.text || "").join("").trim();
  if (!answer) throw new Error("JARVIS v3 returned an empty answer.");
  return answer;
}
async function compatible(req, env, choice) {
  const cfg = {
    v1: ["GROQ_API_KEY", "https://api.groq.com/openai/v1/chat/completions", env.GROQ_MODEL || "openai/gpt-oss-20b", "JARVIS v1"],
    v2: ["NVIDIA_API_KEY", "https://integrate.api.nvidia.com/v1/chat/completions", env.NVIDIA_MODEL || "nvidia/nemotron-3-super-120b-a12b", "JARVIS v2"],
    v4: ["OPENROUTER_API_KEY", "https://openrouter.ai/api/v1/chat/completions", env.OPENROUTER_MODEL || "openrouter/free", "JARVIS v4"],
  }[choice];
  const [key, endpoint, model, label] = cfg;
  if (!configured(env, key)) throw new Error(`${label} is not configured.`);
  const data = await fetchJson(endpoint, {
    method: "POST", headers: { Authorization: `Bearer ${env[key]}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages: messagesFor(req), temperature: 0.7, max_tokens: req.voice_mode ? 512 : 8192, stream: false }),
  });
  let answer = data.choices?.[0]?.message?.content || "";
  if (Array.isArray(answer)) answer = answer.map(x => x.text || "").join("");
  answer = String(answer).trim();
  if (!answer) throw new Error(`${label} returned an empty answer.`);
  return answer;
}
async function provider(req, env, choice) {
  if (choice === "v3") return gemini(req, env);
  return compatible(req, env, choice);
}
async function chat(req, env) {
  if (typeof req.message !== "string" || !req.message.trim() || req.message.length > 12000)
    return error("Message must contain between 1 and 12000 characters.", 422);
  const choice = req.model_choice || "v3";
  if (!["auto", "v1", "v2", "v3", "v4"].includes(choice)) return error("Invalid model selection.", 422);
  if (choice !== "auto") {
    try { return json({ response: await provider(req, env, choice), model_choice: choice }); }
    catch (e) {
      const msg = String(e.message || e);
      return error(msg, /not configured/i.test(msg) ? 503 : /timeout|abort/i.test(msg) ? 504 : 502);
    }
  }
  const available = ["v1", "v2", "v3", "v4"].filter(c => {
    const key = { v1: "GROQ_API_KEY", v2: "NVIDIA_API_KEY", v3: "GEMINI_API_KEY", v4: "OPENROUTER_API_KEY" }[c];
    return configured(env, key);
  });
  if (!available.length) return error("No JARVIS assistant models are configured yet.", 503);
  // Race all configured providers; ignore failures and return the first successful answer.
  const pending = available.map(model => provider(req, env, model).then(
    response => ({ model, response }), error => ({ model, error })
  ));
  const failures = [];
  while (pending.length) {
    const result = await Promise.race(pending);
    const idx = pending.findIndex(p => p === result.promise);
    // Promises are settled via tagged wrappers below; remove by settled marker.
    if (result.response) return json({ response: result.response, model_choice: result.model, selection: "auto" });
    failures.push(`${result.model}: ${result.error?.message || "failed"}`);
    pending.splice(pending.findIndex(p => p === result._promise), 1);
  }
  return error("All configured JARVIS models are temporarily unavailable. " + failures.join("; ").slice(0, 700), 502);
}
async function code(req, env) {
  if (!configured(env, "ZAI_API_KEY")) return error("The coding service is not configured yet.", 503);
  if (typeof req.message !== "string" || !req.message.trim()) return error("A coding request is required.", 422);
  const messages = [{ role: "system", content: "You are JARVIS's dedicated software engineer. Produce correct, complete, runnable code. Respect the existing architecture. Explain briefly when useful." }];
  for (const m of (Array.isArray(req.conversation_history) ? req.conversation_history.slice(-10) : [])) {
    if (["user", "assistant"].includes(m?.role) && typeof m.content === "string") messages.push({ role: m.role, content: m.content.slice(0, 16000) });
  }
  messages.push({ role: "user", content: req.message });
  let last;
  for (const model of [env.ZAI_CODE_MODEL || "glm-4.6", "glm-4.5-flash"]) {
    try {
      const upstream = await fetch("https://api.z.ai/api/paas/v4/chat/completions", {
        method: "POST", headers: { Authorization: `Bearer ${env.ZAI_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, messages, temperature: 0.2, max_tokens: 8192, stream: true, thinking: { type: "disabled" } }),
      });
      if (upstream.ok) return new Response(upstream.body, { status: 200, headers: { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" } });
      const detail = (await upstream.text()).slice(0, 500);
      last = `HTTP ${upstream.status}: ${detail}`;
      if (!detail.includes("1305") && upstream.status !== 429) break;
    } catch (e) { last = e.message; }
  }
  return error(`The coding service failed: ${last || "temporarily unavailable"}`, 502);
}
async function tts(req, env) {
  if (!configured(env, "FISH_API_KEY") || !configured(env, "FISH_AUDIO_VOICE_ID"))
    return error("Fish Audio voice is not configured.", 503);
  if (typeof req.text !== "string" || !req.text.trim() || req.text.length > 6000) return error("Text must contain between 1 and 6000 characters.", 422);
  try {
    const response = await fetch("https://api.fish.audio/v1/tts", {
      method: "POST", headers: { Authorization: `Bearer ${env.FISH_API_KEY}`, "Content-Type": "application/json", model: env.FISH_AUDIO_MODEL || "s2.1-pro-free" },
      body: JSON.stringify({ text: req.text, reference_id: env.FISH_AUDIO_VOICE_ID, format: "mp3", latency: "low", chunk_length: 100, prosody: { speed: 1, volume: 0 } }),
    });
    if (!response.ok) return error(`Fish Audio returned HTTP ${response.status}.`, response.status === 429 || response.status === 503 ? 503 : 502);
    return new Response(response.body, { headers: { ...cors, "Content-Type": "audio/mpeg", "Cache-Control": "no-store" } });
  } catch (e) { return error("Could not reach Fish Audio: " + e.message, 502); }
}
async function search(req, env) {
  if (typeof req.query !== "string" || req.query.trim().length < 2 || req.query.length > 1000) return error("Search query must contain between 2 and 1000 characters.", 422);
  const query = req.query.trim();
  if (/\b(weather|forecast|temperature)\b/i.test(query)) {
    try {
      const place = query.replace(/\b(weather|forecast|temperature|conditions|today|tomorrow|right now|current|please|what is|what's|in)\b/gi, " ").replace(/\s+/g, " ").trim() || "Durban";
      const geo = await fetchJson("https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(place) + "&count=1&language=en&format=json");
      const city = geo.results?.[0];
      if (city) {
        const u = new URL("https://api.open-meteo.com/v1/forecast");
        u.search = new URLSearchParams({ latitude: city.latitude, longitude: city.longitude, current: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m", daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max", forecast_days: "2", timezone: "auto" });
        const data = await fetchJson(u);
        const cur = data.current || {};
        const desc = {0:"clear sky",1:"mainly clear",2:"partly cloudy",3:"overcast",45:"foggy",48:"rime fog",51:"light drizzle",53:"drizzle",55:"dense drizzle",61:"light rain",63:"moderate rain",65:"heavy rain",80:"rain showers",81:"moderate rain showers",82:"heavy rain showers",95:"thunderstorms"};
        const name = [city.name, city.admin1, city.country].filter(Boolean).join(", ");
        const answer = `Current weather in ${name}: ${desc[cur.weather_code] || "conditions unavailable"}, ${cur.temperature_2m}°C (feels like ${cur.apparent_temperature}°C). Humidity: ${cur.relative_humidity_2m}%. Wind: ${cur.wind_speed_10m} km/h.`;
        return json({ answer, sources: [{ title: "Open-Meteo weather forecast", url: "https://open-meteo.com/" }], search_queries: [query], provider: "Open-Meteo" });
      }
    } catch (_) { /* continue to web search fallback */ }
  }
  // DuckDuckGo HTML search; return parsed source links and snippets.
  try {
    const html = await (await fetch("https://html.duckduckgo.com/html/?q=" + encodeURIComponent(query), { headers: { "User-Agent": "Mozilla/5.0", "Accept": "text/html" } })).text();
    const results = [];
    const re = /<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]{0,1800}?class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\//gi;
    for (const m of html.matchAll(re)) {
      let url = m[1].replaceAll("&amp;", "&");
      try { const parsed = new URL(url); if (parsed.hostname.endsWith("duckduckgo.com")) url = parsed.searchParams.get("uddg") || url; } catch {}
      if (!/^https?:\/\//.test(url)) continue;
      const clean = s => s.replace(/<[^>]*>/g, " ").replace(/&amp;/g, "&").replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ").trim();
      results.push({ title: clean(m[2]), url, snippet: clean(m[3]) });
      if (results.length >= 8) break;
    }
    const unique = [...new Map(results.map(x => [x.url, x])).values()];
    if (unique.length) return json({ answer: `Here is what I found about ${query}:\n\n` + unique.map((x,i) => `${i+1}. ${x.title}\n${x.snippet}`).join("\n\n"), sources: unique, search_queries: [query], provider: "DuckDuckGo" });
  } catch (_) {}
  return error("Live search providers are temporarily unreachable. Please retry shortly.", 502);
}
async function handle(request, env) {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method === "GET" && url.pathname === "/") return json({ name: "JARVIS AI by CassimTV", status: "online" });
  if (request.method === "GET" && url.pathname === "/health") return json({ status: "online", name: "JARVIS AI", brand: "CassimTV", ai_configured: configured(env, "GEMINI_API_KEY"), voice_configured: configured(env, "FISH_API_KEY") && configured(env, "FISH_AUDIO_VOICE_ID") });
  if (request.method === "GET" && url.pathname === "/models") return json({ models: [
    { id: "v1", name: "JARVIS v1", configured: configured(env, "GROQ_API_KEY") },
    { id: "v2", name: "JARVIS v2", configured: configured(env, "NVIDIA_API_KEY") },
    { id: "v3", name: "JARVIS v3", configured: configured(env, "GEMINI_API_KEY") },
    { id: "v4", name: "JARVIS v4", configured: configured(env, "OPENROUTER_API_KEY") },
    { id: "auto", name: "AUTO", configured: ["GROQ_API_KEY","NVIDIA_API_KEY","GEMINI_API_KEY","OPENROUTER_API_KEY"].some(k => configured(env,k)) },
  ], coding: { configured: configured(env, "ZAI_API_KEY"), model: env.ZAI_CODE_MODEL || "glm-4.6" } });
  if (request.method === "GET" && url.pathname === "/stats") return json({ cpu_percent: null, ram_used_gb: null, ram_total_gb: null, ram_percent: null, storage_used_gb: null, storage_total_gb: null, storage_percent: null, cpu_temp: null, battery_percent: null, network_status: "connected", platform: "Cloudflare Workers", uptime_seconds: null });
  if (request.method !== "POST") return error("Not found.", 404);
  let req;
  try { req = await bodyJson(request); } catch (e) { return error(e.message, 400); }
  if (url.pathname === "/chat") return chat(req, env);
  if (url.pathname === "/code") return code(req, env);
  if (url.pathname === "/tts") return tts(req, env);
  if (url.pathname === "/search") return search(req, env);
  if (url.pathname === "/command") return error("Device-control commands are handled locally by the Android app. No cloud command was executed.", 501);
  return error("Not found.", 404);
}
export default { async fetch(request, env) { try { return await handle(request, env); } catch (e) { console.error("JARVIS Worker error:", e?.stack || e); return error("JARVIS cloud service encountered an internal error. Please retry.", 500); } } };
