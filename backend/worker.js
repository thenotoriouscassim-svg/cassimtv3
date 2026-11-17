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
    v2: ["NVIDIA_API_KEY", "https://integrate.api.nvidia.com/v1/chat/completions", env.NVIDIA_MODEL || "nvidia/nemotron-3.5-super-vl-120b-a12b", "JARVIS v2"],
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
async function callVoice(req, env) {
  // AUTO Call Mode: ask every configured assistant in parallel and speak the first valid answer.
  const available = ["v1", "v2", "v3", "v4"].filter(choice => {
    const key = { v1: "GROQ_API_KEY", v2: "NVIDIA_API_KEY", v3: "GEMINI_API_KEY", v4: "OPENROUTER_API_KEY" }[choice];
    return configured(env, key);
  });
  if (!available.length) throw new Error("No assistant models are configured.");
  const pending = available.map(model => {
    const token = {};
    token.promise = provider(req, env, model).then(
      response => ({ model, response, token }),
      failure => ({ model, error: failure, token })
    );
    return token;
  });
  const failures = [];
  while (pending.length) {
    const result = await Promise.race(pending.map(item => item.promise));
    if (result.response) return { response: result.response, model: result.model };
    failures.push(`${result.model}: ${result.error?.message || "failed"}`);
    pending.splice(pending.indexOf(result.token), 1);
  }
  throw new Error("All Call Mode models failed. " + failures.join("; ").slice(0, 500));
}

async function chat(req, env) {
  if (typeof req.message !== "string" || !req.message.trim() || req.message.length > 12000)
    return error("Message must contain between 1 and 12000 characters.", 422);
  if (req.voice_mode) {
    try { const result = await callVoice(req, env); return json({ response: result.response, model_choice: result.model, selection: "auto" }); }
    catch (e) {
      const msg = String(e.message || e);
      return error(msg, /not configured/i.test(msg) ? 503 : /timeout|abort/i.test(msg) ? 504 : 502);
    }
  }
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
  const pending = available.map(model => {
    const token = {};
    token.promise = provider(req, env, model).then(
      response => ({ model, response, token }),
      failure => ({ model, error: failure, token })
    );
    return token;
  });
  const failures = [];
  while (pending.length) {
    const result = await Promise.race(pending.map(item => item.promise));
    if (result.response) return json({ response: result.response, model_choice: result.model, selection: "auto" });
    failures.push(`${result.model}: ${result.error?.message || "failed"}`);
    pending.splice(pending.indexOf(result.token), 1);
  }
  return error("All configured JARVIS models are temporarily unavailable. " + failures.join("; ").slice(0, 700), 502);
}
async function code(req, env) {
  if (typeof req.message !== "string" || !req.message.trim()) return error("A coding request is required.", 422);
  const mode = req.mode === "advanced" ? "advanced" : "standard";
  const messages = [{
    role: "system",
    content: mode === "advanced"
      ? "You are JARVIS's advanced software architect and principal engineer. Use deep reasoning for complex architecture, difficult debugging, multi-file changes, performance, security, concurrency, and production systems. Think through edge cases and failure modes before answering. Produce complete, correct, runnable code; preserve the user's existing architecture and explain important decisions. Never claim to have run tests or changed files unless the tools actually did so."
      : "You are JARVIS's standard coding assistant. Handle everyday scripts, small features, straightforward fixes, and code explanations. Produce correct, complete, runnable code and respect the existing architecture. Keep explanations concise."
  }];
  for (const m of (Array.isArray(req.conversation_history) ? req.conversation_history.slice(-10) : [])) {
    if (["user", "assistant"].includes(m?.role) && typeof m.content === "string") messages.push({ role: m.role, content: m.content.slice(0, 16000) });
  }
  messages.push({ role: "user", content: req.message });
  if (mode === "advanced") {
    if (!configured(env, "NVIDIA_API_KEY")) return error("Advanced coding is not configured because the advanced coding service is unavailable.", 503);
    const model = env.NVIDIA_ADVANCED_CODE_MODEL || "poolside/laguna-xs-2.1";
    try {
      const upstream = await fetch("https://integrate.api.nvidia.com/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${env.NVIDIA_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ model, messages, temperature: 0.15, max_tokens: 12000, stream: true })
      });
      if (!upstream.ok) {
        const detail = (await upstream.text()).slice(0, 600);
        return error(`Advanced coding service returned HTTP ${upstream.status}: ${detail}`, 502);
      }
      return new Response(upstream.body, { status: 200, headers: { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" } });
    } catch (e) {
      return error("Advanced coding service failed: " + String(e.message || e), 502);
    }
  }
  if (!configured(env, "ZAI_API_KEY")) return error("The standard coding service is not configured yet.", 503);
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
  return error(`The standard coding service failed: ${last || "temporarily unavailable"}`, 502);
}
async function transcribe(request, env) {
  if (!configured(env, "GROQ_API_KEY")) return error("Speech transcription is not configured.", 503);
  let form;
  try { form = await request.formData(); } catch { return error("A valid audio recording is required.", 400); }
  const audio = form.get("file");
  if (!audio || typeof audio === "string" || typeof audio.arrayBuffer !== "function") return error("No audio recording was uploaded.", 422);
  if (audio.size < 1000) return error("The recording is too short or empty.", 422);
  if (audio.size > 24 * 1024 * 1024) return error("Recording is too large. Keep recordings under three minutes.", 413);
  const upstreamForm = new FormData();
  upstreamForm.append("file", audio, "jarvis-recording.m4a");
  upstreamForm.append("model", "whisper-large-v3-turbo");
  upstreamForm.append("language", "en");
  upstreamForm.append("response_format", "json");
  try {
    const upstream = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: "Bearer " + env.GROQ_API_KEY },
      body: upstreamForm, signal: AbortSignal.timeout(120000)
    });
    const data = await upstream.json().catch(() => ({}));
    if (!upstream.ok) return error("Speech transcription service returned HTTP " + upstream.status + ": " + (data.error?.message || "request failed"), upstream.status === 429 ? 503 : 502);
    const transcript = String(data.text || "").trim();
    if (!transcript) return error("No speech was detected in the recording.", 422);
    return json({ text: transcript });
  } catch (e) { return error("Could not transcribe the recording: " + String(e.message || e), 502); }
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
function xmlText(item, tag) {
  const match = item.match(new RegExp("<" + tag + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + tag + ">", "i"));
  if (!match) return "";
  return match[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").replace(/<[^>]*>/g, " ")
    .replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/\s+/g, " ").trim();
}
async function search(req, env) {
  if (typeof req.query !== "string" || req.query.trim().length < 2 || req.query.length > 1000)
    return error("Search query must contain between 2 and 1000 characters.", 422);
  const query = req.query.trim();
  try {
    const freshness = /\b(latest|today|yesterday|this week|breaking|current|war|conflict|iran|israel|ukraine|usa|united states|election|president|attack|ceasefire|strike|sanction)\b/i.test(query) ? " when:7d" : "";
    const params = new URLSearchParams({ q: query + freshness, hl: "en-ZA", gl: "ZA", ceid: "ZA:en" });
    const feedResponse = await fetch("https://news.google.com/rss/search?" + params.toString(), {
      headers: { "Accept": "application/rss+xml, application/xml, text/xml", "User-Agent": "Mozilla/5.0 JARVIS-AI/1.0" },
      signal: AbortSignal.timeout(18000)
    });
    if (!feedResponse.ok) throw new Error("News search returned HTTP " + feedResponse.status);
    const xml = await feedResponse.text();
    const articles = [];
    for (const match of xml.matchAll(/<item>([\s\S]*?)<\/item>/gi)) {
      const item = match[1];
      const title = xmlText(item, "title");
      let url = xmlText(item, "link");
      const publisher = xmlText(item, "source") || "News publisher";
      const published = xmlText(item, "pubDate");
      const description = xmlText(item, "description").slice(0, 500);
      if (!title || !url || !/^https?:\/\//i.test(url)) continue;
      if (articles.some(a => a.title.toLowerCase() === title.toLowerCase())) continue;
      articles.push({ title, publisher, published, description, url });
      if (articles.length >= 10) break;
    }
    if (!articles.length) throw new Error("No matching news articles were returned.");
    const evidence = articles.map((a, i) => `[${i+1}] ${a.title}\nPublisher: ${a.publisher}\nPublished: ${a.published}\nSnippet: ${a.description}\nURL: ${a.url}`).join("\n\n");
    let answer = "";
    if (configured(env, "GEMINI_API_KEY")) {
      const prompt = `You are JARVIS's research analyst. Answer the user's search query using ONLY the retrieved news evidence below. The user is in South Africa, but cover the international story objectively.\n\nUSER QUERY: ${query}\n\nRETRIEVED ARTICLES:\n${evidence}\n\nRULES:\n- Start with a direct 1-2 sentence answer explaining what the latest reporting says.\n- Then give 3-5 concise factual bullet points: what happened, who is involved, when, what is confirmed, and what remains unclear.\n- Cite every factual claim with bracket citations such as [1] or [2][4], matching the article numbers exactly.\n- Distinguish confirmed facts from allegations, analysis and speculation. If sources conflict, say so.\n- Do not invent details, casualty figures, dates, motives, or outcomes absent from the supplied evidence.\n- State the publication date range represented by the articles.\n- If the evidence is weak or headlines are ambiguous, say that plainly rather than guessing.\n- Do not fabricate links or cite sources not in the list.\n- Do not add a Sources section; the app displays verified retrieved links separately.`;
      try {
        const data = await fetchJson(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key=${encodeURIComponent(env.GEMINI_API_KEY)}`, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { temperature: 0.2, maxOutputTokens: 1600 } })
        }, 30000);
        answer = (data.candidates?.[0]?.content?.parts || []).map(p => p.text || "").join("").trim();
      } catch (e) { console.error("Search synthesis failed:", e.message); }
    }
    if (!answer) {
      answer = `I found ${articles.length} recent news reports related to "${query}", but I could not generate a reliable summary. Here are the retrieved reports; open the sources to verify the details.`;
    }
    return json({
      answer,
      sources: articles.map(a => ({ title: a.title, publisher: a.publisher, published: a.published, url: a.url, snippet: a.description })),
      search_queries: [query],
      provider: "Google News"
    });
  } catch (e) {
    console.error("JARVIS live search error:", e.message);
    return error("Live news search is temporarily unavailable: " + String(e.message || e).slice(0, 220), 502);
  }
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
  ], coding: { standard_configured: configured(env, "ZAI_API_KEY"), standard_model: env.ZAI_CODE_MODEL || "glm-4.6", advanced_configured: configured(env, "NVIDIA_API_KEY"), advanced_model: env.NVIDIA_DEEPSEEK_CODE_MODEL || "deepseek-ai/deepseek-v4.1-flash" } });
  if (request.method === "GET" && url.pathname === "/stats") return json({ cpu_percent: null, ram_used_gb: null, ram_total_gb: null, ram_percent: null, storage_used_gb: null, storage_total_gb: null, storage_percent: null, cpu_temp: null, battery_percent: null, network_status: "connected", platform: "Cloudflare Workers", uptime_seconds: null });
  if (request.method !== "POST") return error("Not found.", 404);
  if (request.method === "POST" && url.pathname === "/transcribe") return transcribe(request, env);
  let req;
  try { req = await bodyJson(request); } catch (e) { return error(e.message, 400); }
  if (url.pathname === "/transcribe") return error("Transcription requires multipart audio.", 400);
  if (url.pathname === "/chat") return chat(req, env);
  if (url.pathname === "/code") return code(req, env);
  if (url.pathname === "/tts") return tts(req, env);
  if (url.pathname === "/search") return search(req, env);
  if (url.pathname === "/command") return error("Device-control commands are handled locally by the Android app. No cloud command was executed.", 501);
  return error("Not found.", 404);
}
export default { async fetch(request, env) { try { return await handle(request, env); } catch (e) { console.error("JARVIS Worker error:", e?.stack || e); return error("JARVIS cloud service encountered an internal error. Please retry.", 500); } } };
