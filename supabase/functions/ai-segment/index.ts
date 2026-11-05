import {
  callMeta,
  handleOptions,
  isRecord,
  jsonResponse,
  metaErrorResponse,
  MODEL_SAM,
  inlineImage,
  readJsonBody,
  str,
  strArray,
  verifyJwt,
} from "../_shared/meta.ts";

// SAM 3.1 via Meta Responses API (verified live):
// POST /responses {model:"sam-3.1", input:[{role:"user",content:[
//   {type:"input_text",text:prompt},{type:"input_image",image_url:<data URI or URL>}]}]}
// Output text contains `<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..|>` per instance
// followed by an RLE `<|mask;...|>` token. The RLE mask is not decoded in v1;
// the client cutout falls back to the verified bbox crop (maskUrl stays "").
// Client contract stays {instances:[{prompt,label,confidence,bbox,maskUrl}]}.

interface Instance {
  prompt: string;
  label: string;
  confidence: number;
  bbox: { x: number; y: number; w: number; h: number };
  maskUrl: string;
}

function bboxArea(b: { w: number; h: number }): number {
  return b.w * b.h;
}

function iou(a: Instance["bbox"], b: Instance["bbox"]): number {
  const x1 = Math.max(a.x, b.x);
  const y1 = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.w, b.x + b.w);
  const y2 = Math.min(a.y + a.h, b.y + b.h);
  const inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
  const union = bboxArea(a) + bboxArea(b) - inter;
  return union <= 0 ? 0 : inter / union;
}


function parseSamText(text: string, prompt: string): Instance[] {
  const out: Instance[] = [];
  const re = /<\|box;([^|]*)\|>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const kv: Record<string, number> = {};
    for (const part of m[1].split(";")) {
      const eq = part.indexOf("=");
      if (eq > 0) {
        const v = Number(part.slice(eq + 1).trim());
        if (Number.isFinite(v)) kv[part.slice(0, eq).trim()] = v;
      }
    }
    const { x1, y1, x2, y2, w, h } = kv;
    if ([x1, y1, x2, y2, w, h].some((v) => v === undefined) || w <= 0 || h <= 0) {
      continue;
    }
    const bbox = { x: x1 / w, y: y1 / h, w: (x2 - x1) / w, h: (y2 - y1) / h };
    if (bbox.w * bbox.h < 0.002) continue;
    out.push({ prompt, label: prompt, confidence: 1, bbox, maskUrl: "" });
  }
  return out;
}

function responseText(resp: unknown): string {
  if (!isRecord(resp) || !Array.isArray(resp.output)) return "";
  let text = "";
  for (const item of resp.output as unknown[]) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue;
    for (const c of item.content as unknown[]) {
      if (isRecord(c) && typeof c.text === "string") text += c.text;
    }
  }
  return text;
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
    const imageUrl = str(body.imageUrl);
    const prompts = strArray(body.prompts).slice(0, 12);
    if (!imageUrl || prompts.length === 0) {
      return jsonResponse({ error: "Invalid request." }, 400);
    }
    const img = await inlineImage(imageUrl);
    if (!img) {
      return jsonResponse(
        { error: "Could not load the photo for AI processing." },
        502,
      );
    }

    const all: Instance[] = [];
    for (const prompt of prompts) {
      try {
        const resp = await callMeta(
          "/responses",
          {
            model: MODEL_SAM,
            input: [
              {
                role: "user",
                content: [
                  { type: "input_text", text: prompt },
                  { type: "input_image", image_url: img },
                ],
              },
            ],
          },
          60000,
        );
        all.push(...parseSamText(responseText(resp), prompt));
      } catch {
        // One failed prompt must not fail the whole batch.
        continue;
      }
    }

    const dedup: Instance[] = [];
    for (const inst of all) {
      if (!dedup.some((d) => iou(d.bbox, inst.bbox) > 0.9)) dedup.push(inst);
      if (dedup.length >= 20) break;
    }
    if (dedup.length === 0) {
      return jsonResponse(
        {
          error:
            "No items were detected. Try a photo with better lighting or add items manually.",
        },
        422,
      );
    }
    return jsonResponse({ instances: dedup }, 200);
  } catch (e) {
    return metaErrorResponse(e);
  }
});
