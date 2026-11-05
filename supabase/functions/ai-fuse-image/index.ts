import {
  callMeta,
  handleOptions,
  isRecord,
  jsonResponse,
  metaErrorResponse,
  MODEL_IMAGE,
  readJsonBody,
  str,
  verifyJwt,
} from "../_shared/meta.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function extractImage(resp: unknown): { url: string | null; b64: string | null } {
  if (!isRecord(resp)) return { url: null, b64: null };
  const data: unknown = resp.data;
  if (Array.isArray(data) && data.length > 0 && isRecord(data[0])) {
    const first = data[0];
    return { url: str(first.url), b64: str(first.b64_json) ?? str(first.b64) };
  }
  return { url: str(resp.url), b64: str(resp.b64_json) ?? str(resp.image_base64) };
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
    const recipeId = str(body.recipeId);
    const prompt = str(body.prompt);
    const referenceImageUrl = str(body.referenceImageUrl);
    if (!recipeId || !prompt) return jsonResponse({ error: "Invalid request." }, 400);
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
    }

    // Verify the recipe belongs to the caller.
    const recipeRes = await fetch(
      `${SUPABASE_URL}/rest/v1/fuse_recipes?id=eq.${encodeURIComponent(recipeId)}&select=id,owner_id`,
      { headers: { Authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY } },
    );
    if (!recipeRes.ok) return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
    const recipes: unknown = await recipeRes.json();
    const recipe = Array.isArray(recipes) && recipes.length > 0 && isRecord(recipes[0]) ? recipes[0] : null;
    if (!recipe || recipe.owner_id !== uid) return jsonResponse({ error: "Unauthorized." }, 401);

    const imageBody: Record<string, unknown> = {
      model: MODEL_IMAGE,
      prompt,
      size: "1024x1024",
    };
    if (referenceImageUrl) imageBody.image_url = referenceImageUrl;

    const resp = await callMeta("/images/generations", imageBody, 60000);
    const { url, b64 } = extractImage(resp);

    let imageBytes: Uint8Array | null = null;
    let contentType = "image/png";
    if (b64) {
      const bin = atob(b64);
      imageBytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) imageBytes[i] = bin.charCodeAt(i);
    } else if (url) {
      const imgRes = await fetch(url);
      if (imgRes.ok) {
        imageBytes = new Uint8Array(await imgRes.arrayBuffer());
        contentType = imgRes.headers.get("Content-Type") ?? "image/png";
      }
    }
    if (!imageBytes) return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);

    const ext = contentType.includes("jpeg") || contentType.includes("jpg") ? "jpg" : "png";
    const path = `${uid}/${recipeId}.${ext}`;
    const uploadRes = await fetch(`${SUPABASE_URL}/storage/v1/object/fuse-images/${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        apikey: SERVICE_ROLE_KEY,
        "Content-Type": contentType,
        "x-upsert": "true",
      },
      body: imageBytes as BodyInit,
    });
    if (!uploadRes.ok) {
      console.error(`fuse image upload failed status=${uploadRes.status}`);
      return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
    }
    const imageUrl = `${SUPABASE_URL}/storage/v1/object/public/fuse-images/${path}`;

    const updateRes = await fetch(
      `${SUPABASE_URL}/rest/v1/fuse_recipes?id=eq.${encodeURIComponent(recipeId)}`,
      {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          apikey: SERVICE_ROLE_KEY,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ image_url: imageUrl }),
      },
    );
    if (!updateRes.ok) {
      console.error(`fuse recipe update failed status=${updateRes.status}`);
      return jsonResponse({ error: "AI service is temporarily unavailable." }, 502);
    }
    return jsonResponse({ imageUrl }, 200);
  } catch (e) {
    return metaErrorResponse(e);
  }
});
