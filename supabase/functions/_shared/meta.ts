// Shared Meta AI adapter — the ONLY place Meta is configured for all Edge Functions.
// Client contract never changes even if the Meta API shape changes; adapt only here.

export const MODEL_SPARK = "muse-spark-1.3";
export const MODEL_IMAGE = "muse-image-1.0";
export const MODEL_SAM = "sam-3.1";

const META_API_BASE_URL = Deno.env.get("META_API_BASE_URL") ?? "https://api.meta.ai/v1";
const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function handleOptions(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return null;
}

/// Verify a Supabase user JWT. Returns userId or null.
export async function verifyJwt(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON_KEY },
    });
    if (!res.ok) return null;
    const user: unknown = await res.json();
    if (isRecord(user) && typeof user.id === "string") return user.id;
    return null;
  } catch {
    return null;
  }
}

export class MetaError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/// Call Meta API (OpenAI-compatible). Timeout -> 504, non-2xx -> 502.
export async function callMeta(path: string, body: unknown, timeoutMs = 30000): Promise<unknown> {
  if (!META_API_KEY) throw new MetaError(502, "AI service is temporarily unavailable.");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${META_API_BASE_URL}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${META_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await res.text();
    if (!res.ok) {
      console.error(`Meta ${path} status=${res.status} body=${text.slice(0, 500)}`);
      throw new MetaError(502, "AI service is temporarily unavailable.");
    }
    try {
      const parsed: unknown = JSON.parse(text);
      return parsed;
    } catch {
      throw new MetaError(502, "AI service is temporarily unavailable.");
    }
  } catch (e) {
    if (e instanceof MetaError) throw e;
    if (e instanceof Error && e.name === "AbortError") {
      throw new MetaError(504, "AI is taking too long to respond. Please try again.");
    }
    console.error(`Meta ${path} error=${e instanceof Error ? e.message : String(e)}`);
    throw new MetaError(502, "AI service is temporarily unavailable.");
  } finally {
    clearTimeout(timer);
  }
}

/// Map MetaError / unknown errors to the uniform JSON error shape.
export function metaErrorResponse(e: unknown): Response {
  if (e instanceof MetaError) {
    if (e.status === 504) return jsonResponse({ error: "AI is taking too long to respond. Please try again." }, 504);
    if (e.status === 502) return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
    return jsonResponse({ error: e.message }, e.status);
  }
  console.error(`Unhandled: ${e instanceof Error ? e.message : String(e)}`);
  return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
}

/// Meta's media fetcher rejects many origins (robots/400). Data URIs are the
/// verified-working transport for Spark vision + SAM — inline server-side.
export async function inlineImage(imageUrl: string): Promise<string | null> {
  if (imageUrl.startsWith("data:")) return imageUrl;
  try {
    const res = await fetch(imageUrl, { headers: { "User-Agent": "RecyGo/1.0" } });
    if (!res.ok) return null;
    const ct = res.headers.get("content-type") ?? "image/jpeg";
    const buf = new Uint8Array(await res.arrayBuffer());
    if (buf.length > 8_000_000) return null;
    let bin = "";
    for (let i = 0; i < buf.length; i += 8192) {
      bin += String.fromCharCode(...buf.subarray(i, i + 8192));
    }
    return `data:${ct};base64,${btoa(bin)}`;
  } catch {
    return null;
  }
}

export function stripCodeFence(s: string): string {
  return s.replace(/```(?:json)?/gi, "").trim();
}

/// Extract the first text content from a chat-completions response.
export function chatContent(resp: unknown): string {
  if (!isRecord(resp)) return "";
  const choices = resp.choices;
  if (!Array.isArray(choices) || choices.length === 0) return "";
  const first: unknown = choices[0];
  if (!isRecord(first)) return "";
  const message = first.message;
  if (!isRecord(message)) return "";
  const c = message.content;
  if (typeof c === "string") return c;
  if (Array.isArray(c)) {
    const parts: string[] = [];
    for (const p of c) {
      if (isRecord(p) && typeof p.text === "string") parts.push(p.text);
    }
    return parts.join("");
  }
  return "";
}

type ChatContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } };

/// Call Muse Spark chat completions (optionally with images), expecting JSON.
/// Returns the parsed object, or null when unparsable.
export async function callSparkJson(opts: {
  system: string;
  userText: string;
  imageUrls?: string[];
  timeoutMs?: number;
}): Promise<Record<string, unknown> | null> {
  const content: ChatContentPart[] = [{ type: "text", text: opts.userText }];
  for (const url of opts.imageUrls ?? []) {
    content.push({ type: "image_url", image_url: { url } });
  }
  const resp = await callMeta(
    "/chat/completions",
    {
      model: MODEL_SPARK,
      messages: [
        { role: "system", content: opts.system },
        { role: "user", content },
      ],
      temperature: 0.2,
      response_format: { type: "json_object" },
    },
    opts.timeoutMs ?? 30000,
  );
  const raw = stripCodeFence(chatContent(resp));
  try {
    const parsed: unknown = JSON.parse(raw);
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/// Fetch a JSON body as a plain record, or null.
export async function readJsonBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const parsed: unknown = await req.json();
    return isRecord(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function str(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

export function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

export function strArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const x of v) if (typeof x === "string") out.push(x);
  return out;
}
