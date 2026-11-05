import {
  callSparkJson,
  handleOptions,
  inlineImage,
  jsonResponse,
  metaErrorResponse,
  readJsonBody,
  str,
  verifyJwt,
} from "../_shared/meta.ts";

const CATEGORIES = ["plastik", "kertas_kardus", "logam", "kaca", "kain_tekstil", "kayu", "elektronik", "organik", "lainnya"];

const SYSTEM = `You list distinct types of second-hand / recyclable objects visible in a photo.
Return ONLY valid JSON: {"objects":[{"label":"...","prompt":"...","categoryGuess":"..."}]}
Rules: one entry per TYPE (not per instance), max 12, ignore background/hands/people.
"label" is English (e.g. "Plastic Bottle"), "prompt" is a short English SAM text prompt (e.g. "plastic bottle"),
"categoryGuess" is one of: plastik|kertas_kardus|logam|kaca|kain_tekstil|kayu|elektronik|organik|lainnya.`;

Deno.serve(async (req: Request) => {
  const pre = handleOptions(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "Invalid request." }, 400);
  try {
    const uid = await verifyJwt(req);
    if (!uid) return jsonResponse({ error: "Unauthorized." }, 401);
    const body = await readJsonBody(req);
    const rawUrl = body ? str(body.imageUrl) : null;
    if (!body || !rawUrl) return jsonResponse({ error: "Invalid request." }, 400);
    const imageUrl = await inlineImage(rawUrl);
    if (!imageUrl) return jsonResponse({ error: "Could not load the photo for AI processing." }, 502);

    let parsed = await callSparkJson({
      system: SYSTEM,
      userText: "List every distinct type of used/recyclable object in this photo.",
      imageUrls: [imageUrl],
    });
    if (!parsed) {
      parsed = await callSparkJson({
        system: SYSTEM,
        userText: "Reply with valid JSON only. List every distinct type of used/recyclable object in this photo.",
        imageUrls: [imageUrl],
      });
    }
    if (!parsed || !Array.isArray(parsed.objects)) {
      return jsonResponse({ error: "AI could not read this photo. Try another photo or fill in manually." }, 422);
    }
    const objects: { label: string; prompt: string; categoryGuess: string }[] = [];
    for (const raw of parsed.objects as unknown[]) {
      if (typeof raw !== "object" || raw === null || Array.isArray(raw)) continue;
      const o = raw as Record<string, unknown>;
      const label = str(o.label);
      const prompt = str(o.prompt);
      if (!label || !prompt) continue;
      const catRaw = str(o.categoryGuess);
      const categoryGuess = catRaw !== null && CATEGORIES.includes(catRaw) ? catRaw : "lainnya";
      objects.push({ label, prompt: prompt.toLowerCase(), categoryGuess });
      if (objects.length >= 12) break;
    }
    return jsonResponse({ objects }, 200);
  } catch (e) {
    return metaErrorResponse(e);
  }
});
