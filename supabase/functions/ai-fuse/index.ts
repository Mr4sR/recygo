import {
  callSparkJson,
  handleOptions,
  isRecord,
  jsonResponse,
  metaErrorResponse,
  num,
  readJsonBody,
  str,
  strArray,
  verifyJwt,
} from "../_shared/meta.ts";

const CATEGORIES = ["plastik", "kertas_kardus", "logam", "kaca", "kain_tekstil", "kayu", "elektronik", "organik", "lainnya"];
const DIFFICULTIES = ["mudah", "sedang", "sulit"];

const SYSTEM = `You are an upcycling expert. Given a list of used items a user owns, propose EXACTLY 3 creative upcycle ideas that genuinely use those items.
Return ONLY valid JSON:
{"ideas":[{
  "title":"...",
  "description":"2-3 sentences in English",
  "steps":["step 1","... 4-8 steps in English"],
  "difficulty":"mudah|sedang|sulit",
  "estimatedMinutes":60,
  "usedItems":[{"itemId":"uuid from input","name":"...","role":"role in the creation, English"}],
  "missingItems":[{"name":"English","category":"one of plastik|kertas_kardus|logam|kaca|kain_tekstil|kayu|elektronik|organik|lainnya","suggestion":"English alternative / where to get it"}],
  "imagePrompt":"English prompt for a photorealistic product illustration, clean background"
}]}
difficulty values MUST stay exactly mudah|sedang|sulit (internal codes). All human-readable text is English.`;

interface FuseItemInput {
  id: string;
  name: string;
  category: string;
  material: string | null;
  condition: string | null;
  quantity: number;
  unit: string;
}

Deno.serve(async (req: Request) => {
  const pre = handleOptions(req);
  if (pre) return pre;
  if (req.method !== "POST") return jsonResponse({ error: "Invalid request." }, 400);
  try {
    const uid = await verifyJwt(req);
    if (!uid) return jsonResponse({ error: "Unauthorized." }, 401);
    const body = await readJsonBody(req);
    if (!body || !Array.isArray(body.items)) return jsonResponse({ error: "Invalid request." }, 400);

    const items: FuseItemInput[] = [];
    for (const raw of body.items as unknown[]) {
      if (!isRecord(raw)) continue;
      const id = str(raw.id);
      const name = str(raw.name);
      if (!id || !name) continue;
      const qty = num(raw.quantity);
      items.push({
        id,
        name,
        category: str(raw.category) ?? "lainnya",
        material: str(raw.material),
        condition: str(raw.condition),
        quantity: qty !== null && qty >= 1 ? Math.round(qty) : 1,
        unit: str(raw.unit) ?? "satuan",
      });
      if (items.length >= 6) break;
    }
    if (items.length < 2) return jsonResponse({ error: "Invalid request." }, 400);

    const userText = `Items I own (JSON): ${JSON.stringify(items)}\nCreate exactly 3 upcycle ideas using these items.`;
    let parsed = await callSparkJson({ system: SYSTEM, userText });
    if (!parsed || !Array.isArray(parsed.ideas)) {
      parsed = await callSparkJson({
        system: SYSTEM,
        userText: `${userText}\nReply with valid JSON only.`,
      });
    }
    if (!parsed || !Array.isArray(parsed.ideas)) {
      return jsonResponse({ error: "AI could not create ideas. Please try again." }, 422);
    }

    const ideas: Record<string, unknown>[] = [];
    for (const raw of (parsed.ideas as unknown[]).slice(0, 3)) {
      if (!isRecord(raw)) continue;
      const title = str(raw.title);
      const description = str(raw.description);
      const imagePrompt = str(raw.imagePrompt);
      if (!title || !description || !imagePrompt) continue;
      const diffRaw = str(raw.difficulty);
      const usedItems: { itemId: string; name: string; role: string }[] = [];
      if (Array.isArray(raw.usedItems)) {
        for (const u of raw.usedItems as unknown[]) {
          if (!isRecord(u)) continue;
          const itemId = str(u.itemId);
          const name = str(u.name);
          if (!itemId || !name) continue;
          usedItems.push({ itemId, name, role: str(u.role) ?? "" });
        }
      }
      const missingItems: { name: string; category: string; suggestion: string }[] = [];
      if (Array.isArray(raw.missingItems)) {
        for (const m of raw.missingItems as unknown[]) {
          if (!isRecord(m)) continue;
          const name = str(m.name);
          if (!name) continue;
          const catRaw = str(m.category);
          missingItems.push({
            name,
            category: catRaw !== null && CATEGORIES.includes(catRaw) ? catRaw : "lainnya",
            suggestion: str(m.suggestion) ?? "",
          });
        }
      }
      const mins = num(raw.estimatedMinutes);
      ideas.push({
        title,
        description,
        steps: strArray(raw.steps).slice(0, 8),
        difficulty: diffRaw !== null && DIFFICULTIES.includes(diffRaw) ? diffRaw : "mudah",
        estimatedMinutes: mins !== null && mins > 0 ? Math.round(mins) : null,
        usedItems,
        missingItems,
        imagePrompt,
      });
    }
    if (ideas.length === 0) {
      return jsonResponse({ error: "AI could not create ideas. Please try again." }, 422);
    }
    return jsonResponse({ ideas }, 200);
  } catch (e) {
    return metaErrorResponse(e);
  }
});
