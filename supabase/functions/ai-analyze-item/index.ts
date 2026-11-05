import {
  callSparkJson,
  handleOptions,
  inlineImage,
  jsonResponse,
  metaErrorResponse,
  num,
  readJsonBody,
  str,
  strArray,
  verifyJwt,
} from "../_shared/meta.ts";

const CATEGORIES = ["plastik", "kertas_kardus", "logam", "kaca", "kain_tekstil", "kayu", "elektronik", "organik", "lainnya"];
const CONDITIONS = ["baru", "baik", "cukup", "rusak_ringan", "rusak_berat"];
const UNITS = ["satuan", "kardus", "karung", "paket", "kilogram", "lainnya"];

const SYSTEM = `You identify dominant second-hand / recyclable items in photos for a recycling marketplace.
Return ONLY valid JSON, no markdown, with exactly this shape:
{
  "name": "string, English, max 60 chars",
  "category": "one of: plastik|kertas_kardus|logam|kaca|kain_tekstil|kayu|elektronik|organik|lainnya",
  "tags": ["max 6 lowercase English tags"],
  "description": "1-2 sentences in English or null",
  "condition": "baru|baik|cukup|rusak_ringan|rusak_berat",
  "brand": "string or null",
  "material": "string or null, e.g. PP plastic, iron, cotton",
  "unitGuess": "satuan|kardus|karung|paket|kilogram|lainnya",
  "quantityGuess": 1,
  "confidence": 0.0
}
Category/condition/unit values MUST stay exactly as the enum codes above (they are internal codes), while name/tags/description are English.`;

function pickEnum(v: unknown, allowed: string[], fallback: string | null): string | null {
  const s = str(v);
  return s !== null && allowed.includes(s) ? s : fallback;
}

Deno.serve(async (req: Request) => {
  const pre = handleOptions(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "Invalid request." }, 400);
  try {
    const uid = await verifyJwt(req);
    if (!uid) return jsonResponse({ error: "Unauthorized." }, 401);
    const body = await readJsonBody(req);
    if (!body) return jsonResponse({ error: "Invalid request." }, 400);
    const rawUrls = strArray(body.imageUrls).slice(0, 5);
    if (rawUrls.length === 0) return jsonResponse({ error: "Invalid request." }, 400);
    // Meta's fetcher rejects many origins (robots/400); inline as data URIs.
    const imageUrls: string[] = [];
    for (const u of rawUrls) {
      const inlined = await inlineImage(u);
      if (!inlined) return jsonResponse({ error: "Could not load the photo for AI processing." }, 502);
      imageUrls.push(inlined);
    }

    let parsed = await callSparkJson({
      system: SYSTEM,
      userText: "Identify the dominant used item in these photos and return the JSON described.",
      imageUrls,
    });
    if (!parsed) {
      parsed = await callSparkJson({
        system: SYSTEM,
        userText: "Reply with valid JSON only, no other text. Identify the dominant used item in these photos.",
        imageUrls,
      });
    }
    if (!parsed) {
      return jsonResponse({ error: "AI could not read this photo. Try another photo or fill in manually." }, 422);
    }
    const nameRaw = str(parsed.name) ?? "Used Item";
    const confidenceRaw = num(parsed.confidence) ?? 0;
    const qtyRaw = num(parsed.quantityGuess);
    const result = {
      name: nameRaw.slice(0, 60),
      category: pickEnum(parsed.category, CATEGORIES, "lainnya") ?? "lainnya",
      tags: strArray(parsed.tags).map((t) => t.toLowerCase().trim()).filter((t) => t !== "").slice(0, 6),
      description: str(parsed.description),
      condition: pickEnum(parsed.condition, CONDITIONS, null),
      brand: str(parsed.brand),
      material: str(parsed.material),
      unitGuess: pickEnum(parsed.unitGuess, UNITS, "satuan") ?? "satuan",
      quantityGuess: qtyRaw !== null && qtyRaw >= 1 ? Math.round(qtyRaw) : 1,
      confidence: Math.min(1, Math.max(0, confidenceRaw)),
    };
    return jsonResponse(result, 200);
  } catch (e) {
    return metaErrorResponse(e);
  }
});
