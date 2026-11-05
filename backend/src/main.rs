use axum::{body::Bytes, extract::{Path, Query, State}, http::{HeaderMap, StatusCode}, response::{IntoResponse, Response}, routing::{get, patch, post}, Json, Router};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::{collections::HashMap, sync::Arc};
use tower_http::cors::{Any, CorsLayer};
use uuid::Uuid;

#[derive(Clone)]
struct Config { supabase_url:String, supabase_anon:String, supabase_service:String, meta_key:String, meta_base:String, spark:String, image:String, sam:String, rustfs_endpoint:String, rustfs_public:String, rustfs_access:String, rustfs_secret:String, rustfs_bucket:String, public_url:String }
fn env(k:&str,d:&str)->String{std::env::var(k).unwrap_or_else(|_|d.into())}
impl Config { fn load()->Self{Self{supabase_url:env("SUPABASE_URL",""), supabase_anon:env("SUPABASE_ANON_KEY",""), supabase_service:env("SUPABASE_SERVICE_ROLE_KEY",""), meta_key:env("META_API_KEY",""), meta_base:env("META_API_BASE_URL","https://api.meta.ai/v1"), spark:env("MODEL_SPARK","muse-spark-1.3"), image:env("MODEL_IMAGE","muse-image-1.0"), sam:env("MODEL_SAM","sam-3.1"), rustfs_endpoint:env("RUSTFS_ENDPOINT",""), rustfs_public:env("RUSTFS_PUBLIC_URL",""), rustfs_access:env("RUSTFS_ACCESS_KEY",""), rustfs_secret:env("RUSTFS_SECRET_KEY",""), rustfs_bucket:env("RUSTFS_BUCKET","recygo-media"), public_url:env("BACKEND_PUBLIC_URL","")}} }
#[derive(Clone)] struct AppState { cfg:Arc<Config>, http:reqwest::Client }
fn err(code:StatusCode,msg:&str)->Response{(code,Json(json!({"error":msg}))).into_response()}
fn s(v:&Value)->Option<String>{v.as_str().map(str::trim).filter(|x|!x.is_empty()).map(str::to_string)}
fn n(v:&Value)->Option<f64>{v.as_f64().filter(|x|x.is_finite())}
fn arr(v:&Value)->Vec<Value>{v.as_array().cloned().unwrap_or_default()}
fn strs(v:&Value)->Vec<String>{arr(v).into_iter().filter_map(|x|x.as_str().map(str::to_string)).collect()}
const CATS:[&str;9]=["plastik","kertas_kardus","logam","kaca","kain_tekstil","kayu","elektronik","organik","lainnya"];
fn enum_or(v:Option<String>, allowed:&[&str], fb:&str)->String{match v{Some(x) if allowed.contains(&x.as_str())=>x,_=>fb.into()}}
fn pick(data:&Value, fields:&[&str])->Map<String,Value>{let mut out=Map::new(); if let Some(o)=data.as_object(){for f in fields{if let Some(v)=o.get(*f){if !v.is_null()||["description","condition","brand","material","original_photo_url","cutout_photo_url","segmentation","price","note","lat","lng","avatar_url","phone","whatsapp","bio","city","image_url","estimated_minutes"].contains(f){out.insert(f.to_string(),v.clone());}}}} out}

// ---------- health / auth ----------
async fn health(State(st):State<AppState>)->impl IntoResponse{Json(json!({"ok":true,"service":"recygo-backend","storage":"supabase-postgres","supabaseConfigured":!st.cfg.supabase_url.is_empty()&&!st.cfg.supabase_service.is_empty(),"metaConfigured":!st.cfg.meta_key.is_empty(),"rustfsConfigured":!st.cfg.rustfs_endpoint.is_empty()&&!st.cfg.rustfs_access.is_empty(),"models":{"spark":st.cfg.spark,"image":st.cfg.image,"sam":st.cfg.sam}}))}
async fn verify(st:&AppState,h:&HeaderMap)->Result<String,Response>{
 let a=h.get("authorization").and_then(|v|v.to_str().ok()).unwrap_or(""); let token=a.strip_prefix("Bearer ").unwrap_or(a).trim();
 if token.is_empty(){return Err(err(StatusCode::UNAUTHORIZED,"Unauthorized."))}
 if st.cfg.supabase_url.is_empty(){ if token=="dev-token" {return Ok("00000000-0000-0000-0000-000000000001".into())} return Err(err(StatusCode::UNAUTHORIZED,"Unauthorized.")); }
 let res=st.http.get(format!("{}/auth/v1/user",st.cfg.supabase_url)).header("Authorization",format!("Bearer {token}")).header("apikey",&st.cfg.supabase_anon).send().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable."))?;
 if !res.status().is_success(){return Err(err(StatusCode::UNAUTHORIZED,"Unauthorized."))}
 let u:Value=res.json().await.map_err(|_|err(StatusCode::UNAUTHORIZED,"Unauthorized."))?; u.get("id").and_then(Value::as_str).map(str::to_string).ok_or_else(||err(StatusCode::UNAUTHORIZED,"Unauthorized."))
}

// ---------- Supabase PostgREST (service role; owner checks enforced here) ----------
fn pg_ok(st:&AppState)->Result<(),Response>{ if st.cfg.supabase_url.is_empty()||st.cfg.supabase_service.is_empty(){Err(err(StatusCode::BAD_GATEWAY,"Backend storage is not configured."))}else{Ok(())} }
async fn pg_get(st:&AppState, table:&str, query:&str)->Result<Vec<Value>,Response>{ pg_ok(st)?; let url=format!("{}/rest/v1/{}?{}",st.cfg.supabase_url.trim_end_matches('/'),table,query); let r=st.http.get(&url).header("apikey",&st.cfg.supabase_service).header("Authorization",format!("Bearer {}",st.cfg.supabase_service)).header("Accept","application/json").send().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))?; if !r.status().is_success(){return Err(err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))} let v:Value=r.json().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))?; Ok(arr(&v)) }
async fn pg_send(st:&AppState, method:reqwest::Method, table:&str, query:&str, body:Value)->Result<Vec<Value>,Response>{ pg_request(st,method,table,query,body,"return=representation").await }
/// Upsert helper: PostgREST only honours `on_conflict` when the resolution
/// preference is sent, otherwise the request fails with 400/409.
async fn pg_upsert(st:&AppState, table:&str, query:&str, body:Value)->Result<Vec<Value>,Response>{ pg_request(st,reqwest::Method::POST,table,query,body,"return=representation,resolution=merge-duplicates").await }
async fn pg_request(st:&AppState, method:reqwest::Method, table:&str, query:&str, body:Value, prefer:&str)->Result<Vec<Value>,Response>{ pg_ok(st)?; let url=format!("{}/rest/v1/{}?{}",st.cfg.supabase_url.trim_end_matches('/'),table,query); let r=st.http.request(method.clone(),&url).header("apikey",&st.cfg.supabase_service).header("Authorization",format!("Bearer {}",st.cfg.supabase_service)).header("Content-Type","application/json").header("Prefer",prefer).json(&body).send().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))?; let status=r.status(); let t=r.text().await.unwrap_or_default(); if !status.is_success(){eprintln!("postgrest {method} {table} -> {status}: {}",t.chars().take(400).collect::<String>());return Err(err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))} if t.trim().is_empty(){return Ok(vec![])} let v:Value=serde_json::from_str(&t).map_err(|_|err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable."))?; Ok(if v.is_array(){arr(&v)}else{vec![v]}) }
async fn pg_one(st:&AppState, table:&str, query:&str)->Result<Option<Value>,Response>{ Ok(pg_get(st,table,query).await?.into_iter().next()) }

// ---------- Meta ----------
async fn meta(st:&AppState,path:&str,body:Value,timeout:u64)->Result<Value,Response>{
 if st.cfg.meta_key.is_empty(){return Err(err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable."))}
 let r=st.http.post(format!("{}{}",st.cfg.meta_base.trim_end_matches('/'),path)).bearer_auth(&st.cfg.meta_key).json(&body).timeout(std::time::Duration::from_millis(timeout)).send().await;
 let r=match r{Ok(x)=>x,Err(e) if e.is_timeout()=>return Err(err(StatusCode::GATEWAY_TIMEOUT,"AI is taking too long to respond. Please try again.")),Err(_)=>return Err(err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable."))};
 if !r.status().is_success(){return Err(err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable."))}
 r.json().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable."))
}
fn chat(resp:&Value)->String{let c=&resp["choices"][0]["message"]["content"]; if let Some(t)=c.as_str(){return t.into()} if let Some(p)=c.as_array(){return p.iter().filter_map(|x|x["text"].as_str()).collect::<Vec<_>>().join("")} String::new()}
async fn spark(st:&AppState,system:&str,user:&str,images:&[String])->Result<Value,Response>{
 let mut content=vec![json!({"type":"text","text":user})]; for u in images{content.push(json!({"type":"image_url","image_url":{"url":u}}))}
 let resp=match meta(st,"/chat/completions",json!({"model":st.cfg.spark,"messages":[{"role":"system","content":system},{"role":"user","content":content.clone()}],"temperature":0.2,"response_format":{"type":"json_object"}}),45000).await{Ok(v)=>v,Err(e)=>{ if e.status()==StatusCode::GATEWAY_TIMEOUT{ meta(st,"/chat/completions",json!({"model":st.cfg.spark,"messages":[{"role":"system","content":system},{"role":"user","content":content}],"temperature":0.2,"response_format":{"type":"json_object"}}),45000).await? } else { return Err(e); } }};
 let raw=chat(&resp).replace("```json","").replace("```",""); serde_json::from_str(raw.trim()).map_err(|_|err(StatusCode::UNPROCESSABLE_ENTITY,"AI could not read this photo. Try another photo or fill in manually."))
}
#[derive(Deserialize)] struct AnalyzeReq{#[serde(rename="imageUrls")] image_urls:Vec<String>}
async fn analyze(State(st):State<AppState>,h:HeaderMap,Json(req):Json<AnalyzeReq>)->Response{
 if let Err(e)=verify(&st,&h).await{return e} if req.image_urls.is_empty()||req.image_urls.len()>5{return err(StatusCode::BAD_REQUEST,"Invalid request.")}
 let mut imgs=Vec::new(); for u in &req.image_urls{ match inline_image(&st,u).await{Ok(v)=>imgs.push(v),Err(e)=>return e} }
 let sys="Identify dominant second-hand item. Return ONLY JSON: name English max60, category plastik|kertas_kardus|logam|kaca|kain_tekstil|kayu|elektronik|organik|lainnya, tags max6 lowercase English, description English/null, condition baru|baik|cukup|rusak_ringan|rusak_berat, brand, material, unitGuess satuan|kardus|karung|paket|kilogram|lainnya, quantityGuess, confidence.";
 let p=match spark(&st,sys,"Identify the dominant used item.",&imgs).await{Ok(v)=>v,Err(e)=>return e};
 (StatusCode::OK,Json(json!({"name":s(&p["name"]).unwrap_or_else(||"Used Item".into()).chars().take(60).collect::<String>(),"category":enum_or(s(&p["category"]),&CATS,"lainnya"),"tags":strs(&p["tags"]).into_iter().map(|t|t.to_lowercase()).take(6).collect::<Vec<_>>(),"description":s(&p["description"]),"condition":s(&p["condition"]),"brand":s(&p["brand"]),"material":s(&p["material"]),"unitGuess":enum_or(s(&p["unitGuess"]),&["satuan","kardus","karung","paket","kilogram","lainnya"],"satuan"),"quantityGuess":n(&p["quantityGuess"]).map(|v|v.max(1.0).round() as i64).unwrap_or(1),"confidence":n(&p["confidence"]).unwrap_or(0.0).clamp(0.0,1.0)}))).into_response()
}
#[derive(Deserialize)] struct SuggestReq{#[serde(rename="imageUrl")] image_url:String}
async fn suggest(State(st):State<AppState>,h:HeaderMap,Json(req):Json<SuggestReq>)->Response{
 if let Err(e)=verify(&st,&h).await{return e}
 let img=match inline_image(&st,&req.image_url).await{Ok(v)=>v,Err(e)=>return e};
 let p=match spark(&st,"List distinct TYPES of second-hand objects. Return ONLY JSON {objects:[{label English,prompt short English,categoryGuess enum}]} max 12.","List every distinct type.",&[img]).await{Ok(v)=>v,Err(e)=>return e};
 let mut out=vec![]; for o in arr(&p["objects"]){if let(Some(label),Some(prompt))=(s(&o["label"]),s(&o["prompt"])){out.push(json!({"label":label,"prompt":prompt.to_lowercase(),"categoryGuess":enum_or(s(&o["categoryGuess"]),&CATS,"lainnya")}));} if out.len()>=12{break}}
 (StatusCode::OK,Json(json!({"objects":out}))).into_response()
}
fn iou(a:&Value,b:&Value)->f64{let g=|v:&Value,k:&str|n(&v[k]).unwrap_or(0.0);let(ax,ay,aw,ah)=(g(a,"x"),g(a,"y"),g(a,"w"),g(a,"h"));let(bx,by,bw,bh)=(g(b,"x"),g(b,"y"),g(b,"w"),g(b,"h"));let inter=((ax+aw).min(bx+bw)-ax.max(bx)).max(0.0)*((ay+ah).min(by+bh)-ay.max(by)).max(0.0);let uni=aw*ah+bw*bh-inter;if uni<=0.0{0.0}else{inter/uni}}
#[derive(Deserialize)] struct SegmentReq{#[serde(rename="imageUrl")] image_url:String,prompts:Vec<String>,#[serde(rename="batchId")] batch_id:Option<String>}
/// Fetch an image URL and inline it as a data URI. Meta's fetcher rejects many
/// origins (robots/400), while data URIs are verified to work for Spark + SAM.
async fn inline_image(st:&AppState,url:&str)->Result<String,Response>{
 if url.starts_with("data:"){return Ok(url.to_string())}
 let r=st.http.get(url).header("User-Agent","RecyGo/1.0").send().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Could not load the photo for AI processing."))?;
 if !r.status().is_success(){return Err(err(StatusCode::BAD_GATEWAY,"Could not load the photo for AI processing."))}
 let ct=r.headers().get("content-type").and_then(|v|v.to_str().ok()).unwrap_or("image/jpeg").to_string();
 let bytes=r.bytes().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Could not load the photo for AI processing."))?;
 if bytes.len()>8_000_000{return Err(err(StatusCode::BAD_REQUEST,"Photo is too large."))}
 Ok(format!("data:{};base64,{}",ct,encode_b64(&bytes)))
}
fn decode_b64(input:&str)->Result<Vec<u8>,()>{let mut out=Vec::new();let mut buf=0u32;let mut bits=0;for c in input.bytes(){let v=match c{b'A'..=b'Z'=>(c-b'A') as u32,b'a'..=b'z'=>(c-b'a'+26) as u32,b'0'..=b'9'=>(c-b'0'+52) as u32,b'+'=>62,b'/'=>63,b'=' =>break,_=>continue};buf=(buf<<6)|v;bits+=6;if bits>=8{bits-=8;out.push((buf>>bits) as u8)}}Ok(out)}
fn encode_b64(data:&[u8])->String{const T:&[u8]=b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; let mut out=String::new(); for ch in data.chunks(3){let b=|i:usize|if i<ch.len(){ch[i] as u32}else{0}; let n=(b(0)<<16)|(b(1)<<8)|b(2); out.push(T[(n>>18)as usize &63]as char); out.push(T[(n>>12)as usize &63]as char); out.push(if ch.len()>1{T[(n>>6)as usize &63]as char}else{'='}); out.push(if ch.len()>2{T[n as usize &63]as char}else{'='});} out}
/// Detect real image format from magic bytes: Muse Image returns WebP inside b64_json.
fn sniff_image(b:&[u8])->(&'static str,&'static str){ if b.starts_with(b"\x89PNG\r\n\x1a\n"){("png","image/png")} else if b.starts_with(b"\xff\xd8\xff"){("jpg","image/jpeg")} else if b.len()>12&&b.starts_with(b"RIFF")&&&b[8..12]==b"WEBP"{("webp","image/webp")} else {("png","image/png")} }
/// Parse SAM 3.1 Responses output: repeated `<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..|>` (+ RLE mask tokens, not decoded v1).
fn parse_sam(text:&str,prompt:&str)->Vec<Value>{
 let mut out=vec![]; let mut rest=text;
 while let Some(start)=rest.find("<|box;"){ let after=&rest[start+6..]; let Some(end)=after.find("|>") else{break}; let spec=&after[..end]; rest=&after[end+2..];
  let mut m:HashMap<String,f64>=HashMap::new(); for kv in spec.split(';'){ if let Some((k,v))=kv.split_once('='){ if let Ok(f)=v.trim().parse::<f64>(){m.insert(k.trim().to_string(),f);} } }
  if let(Some(x1),Some(y1),Some(x2),Some(y2),Some(w),Some(h))=(m.get("x1").copied(),m.get("y1").copied(),m.get("x2").copied(),m.get("y2").copied(),m.get("w").copied(),m.get("h").copied()){ if w>0.0&&h>0.0{ let bw=(x2-x1)/w; let bh=(y2-y1)/h; if bw*bh>=0.002{ out.push(json!({"prompt":prompt,"label":prompt,"confidence":1.0,"bbox":{"x":x1/w,"y":y1/h,"w":bw,"h":bh},"maskUrl":""})); } } }
 }
 out
}
async fn segment(State(st):State<AppState>,h:HeaderMap,Json(req):Json<SegmentReq>)->Response{
 if let Err(e)=verify(&st,&h).await{return e}; if req.prompts.is_empty()||req.prompts.len()>12{return err(StatusCode::BAD_REQUEST,"Invalid request.")}
 let img=match inline_image(&st,&req.image_url).await{Ok(v)=>v,Err(e)=>return e}; let _=req.batch_id;
 let mut all:Vec<Value>=vec![];
 for prompt in req.prompts.iter().take(12){
  let body=json!({"model":st.cfg.sam,"input":[{"role":"user","content":[{"type":"input_text","text":prompt},{"type":"input_image","image_url":img}]}]});
  let resp=match meta(&st,"/responses",body,60000).await{Ok(v)=>v,Err(_)=>continue};
  for item in arr(&resp["output"]){ for c in arr(&item["content"]){ if let Some(t)=c["text"].as_str(){ all.extend(parse_sam(t,prompt)); } } }
 }
 let mut dedup:Vec<Value>=vec![]; for c in all{if !dedup.iter().any(|d:&Value|iou(&d["bbox"],&c["bbox"])>0.9){dedup.push(c)} if dedup.len()>=20{break}}
 if dedup.is_empty(){return err(StatusCode::UNPROCESSABLE_ENTITY,"No items were detected. Try a photo with better lighting or add items manually.")}
 (StatusCode::OK,Json(json!({"instances":dedup}))).into_response()
}
async fn fuse(State(st):State<AppState>,h:HeaderMap,Json(body):Json<Value>)->Response{
 if let Err(e)=verify(&st,&h).await{return e} let items=arr(&body["items"]); if items.len()<2||items.len()>6{return err(StatusCode::BAD_REQUEST,"Invalid request.")}
 let sys="You are an upcycling expert. Return ONLY JSON {ideas:[{title,description English,steps English 4-8,difficulty mudah|sedang|sulit,estimatedMinutes,usedItems[{itemId,name,role}],missingItems[{name,category enum,suggestion}],imagePrompt English}]}. Exactly 3 ideas.";
 let user=format!("Items JSON: {}",Value::Array(items)); let p=match spark(&st,sys,&user,&[]).await{Ok(v)=>v,Err(e)=>return e}; let ideas=arr(&p["ideas"]); if ideas.is_empty(){return err(StatusCode::UNPROCESSABLE_ENTITY,"AI could not create ideas. Please try again.")}
 (StatusCode::OK,Json(json!({"ideas":ideas.into_iter().take(3).collect::<Vec<_>>()}))).into_response()
}
async fn fuse_image(State(st):State<AppState>,h:HeaderMap,Json(body):Json<Value>)->Response{
 let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e};
 let recipe_id=match s(&body["recipeId"]){Some(v)=>v,None=>return err(StatusCode::BAD_REQUEST,"Invalid request.")};
 let prompt=match s(&body["prompt"]){Some(v)=>v,None=>return err(StatusCode::BAD_REQUEST,"Invalid request.")};
 let recipe=match pg_one(&st,"fuse_recipes",&format!("id=eq.{recipe_id}&select=id,owner_id")).await{Ok(v)=>v,Err(e)=>return e};
 match recipe { Some(r) if s(&r["owner_id"]).as_deref()==Some(uid.as_str())=>{}, _=>return err(StatusCode::UNAUTHORIZED,"Unauthorized.") }
 // Meta rejects `image_url` on /images/generations; reference-guided images must
 // go through /images/edits with `images:[{image_url}]` (data URIs only, the
 // upstream fetcher refuses most origins).
 let mut img_body=json!({"model":st.cfg.image,"prompt":prompt,"size":"1024x1024"});
 let mut path="/images/generations"; let mut timeout=60000u64;
 if let Some(r)=s(&body["referenceImageUrl"]){ if !r.is_empty(){ if let Ok(uri)=inline_image(&st,&r).await{ img_body["images"]=json!([{"image_url":uri}]); path="/images/edits"; timeout=120000; } } }
 let resp=match meta(&st,path,img_body,timeout).await{Ok(v)=>v,Err(e)=>return e};
 let data0=arr(&resp["data"]).into_iter().next().unwrap_or(Value::Null);
 let mut image_url=s(&data0["url"]).or_else(||s(&resp["url"])).unwrap_or_default();
 if image_url.is_empty(){ if let Some(b64)=s(&data0["b64_json"]).or_else(||s(&data0["b64"])).or_else(||s(&resp["b64_json"])){ if let Ok(bytes)=decode_b64(&b64){ let (ext,ct)=sniff_image(&bytes); let key=format!("{uid}/fuse/{recipe_id}.{ext}"); match put_s3(&st,&key,bytes,ct).await{Ok(u)=>image_url=u,Err(e)=>return e} } } }
 if image_url.is_empty(){return err(StatusCode::BAD_GATEWAY,"AI service is temporarily unavailable.")}
 if image_url.starts_with("http") && !st.cfg.rustfs_endpoint.is_empty(){
   // Best-effort mirror remote URL into RustFS for stable CDN URL; keep original on failure.
   if let Ok(r)=st.http.get(&image_url).send().await{ if r.status().is_success(){ if let Ok(bytes)=r.bytes().await{ let (ext,ct)=sniff_image(&bytes); let key=format!("{uid}/fuse/{recipe_id}.{ext}"); if let Ok(u)=put_s3(&st,&key,bytes.to_vec(),ct).await{ image_url=u; } } } }
 }
 if let Err(e)=pg_send(&st,reqwest::Method::PATCH,"fuse_recipes",&format!("id=eq.{recipe_id}"),json!({"image_url":image_url})).await{return e}
 (StatusCode::OK,Json(json!({"imageUrl":image_url}))).into_response()
}

// ---------- RustFS S3 presign / upload ----------
#[derive(Deserialize)] struct MediaReq{filename:String,#[serde(rename="contentType")] content_type:Option<String>,folder:Option<String>}
async fn presign(State(st):State<AppState>,h:HeaderMap,Json(req):Json<MediaReq>)->Response{
 let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; if st.cfg.rustfs_endpoint.is_empty(){return err(StatusCode::BAD_GATEWAY,"Media storage is not configured.")}
 let ct=req.content_type.unwrap_or_else(||"image/jpeg".into()); let folder=req.folder.unwrap_or_else(||"items".into()); let key=format!("{uid}/{folder}/{}/{}",Uuid::new_v4(),req.filename.replace('/', "-"));
 match presign_put(&st,&key,&ct,900).await{Ok((upload,public))=> (StatusCode::OK,Json(json!({"uploadUrl":upload,"publicUrl":public,"key":key}))).into_response(),Err(e)=>e}
}
async fn upload(State(st):State<AppState>,h:HeaderMap,Query(q):Query<HashMap<String,String>>, body:Bytes)->Response{
 let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; if body.is_empty()||body.len()>10_000_000{return err(StatusCode::BAD_REQUEST,"Invalid request.")}
 let filename=q.get("filename").cloned().unwrap_or_else(||"photo.jpg".into()).replace('/',"-"); let folder=q.get("folder").cloned().unwrap_or_else(||"items".into());
 let ct=h.get("content-type").and_then(|v|v.to_str().ok()).unwrap_or("image/jpeg").to_string();
 let key=format!("{uid}/{folder}/{}/{}",Uuid::new_v4(),filename);
 match put_s3(&st,&key,body.to_vec(),&ct).await{Ok(public)=>(StatusCode::OK,Json(json!({"publicUrl":public,"key":key}))).into_response(),Err(e)=>e}
}
async fn put_s3(st:&AppState,key:&str,bytes:Vec<u8>,content_type:&str)->Result<String,Response>{
 let (upload,_public)=presign_put(st,key,content_type,900).await?; let r=st.http.put(&upload).header("Content-Type",content_type).body(bytes).send().await.map_err(|_|err(StatusCode::BAD_GATEWAY,"Media storage is unavailable."))?; if !r.status().is_success(){return Err(err(StatusCode::BAD_GATEWAY,"Media storage is unavailable."))} if !st.cfg.public_url.is_empty(){return Ok(format!("{}/v1/media/file/{}",st.cfg.public_url.trim_end_matches('/'),key))} presign_get(st,key,7*24*3600).await
}
fn signing_key(st:&AppState,datestamp:&str)->Vec<u8>{
 use hmac::{Hmac,Mac}; type H=Hmac<sha2::Sha256>;
 let mut k=H::new_from_slice(format!("AWS4{}",st.cfg.rustfs_secret).as_bytes()).unwrap(); k.update(datestamp.as_bytes()); let kdate=k.finalize().into_bytes(); let mut k=H::new_from_slice(&kdate).unwrap(); k.update(b"us-east-1"); let kregion=k.finalize().into_bytes(); let mut k=H::new_from_slice(&kregion).unwrap(); k.update(b"s3"); let kservice=k.finalize().into_bytes(); let mut k=H::new_from_slice(&kservice).unwrap(); k.update(b"aws4_request"); k.finalize().into_bytes().to_vec()
}
async fn presign_get(st:&AppState,key:&str,expires:u64)->Result<String,Response>{
 use hmac::{Hmac,Mac}; use sha2::{Digest,Sha256}; type H=Hmac<Sha256>;
 if st.cfg.rustfs_access.is_empty()||st.cfg.rustfs_secret.is_empty(){return Err(err(StatusCode::BAD_GATEWAY,"Media storage is not configured."))}
 let endpoint=st.cfg.rustfs_endpoint.trim_end_matches('/'); let host=endpoint.replace("https://","").replace("http://",""); let cdn_host=st.cfg.rustfs_public.trim_end_matches('/').replace("https://","").replace("http://",""); let cdn_path_prefix=if cdn_host.is_empty(){String::new()}else{ cdn_host.split('/').skip(1).collect::<Vec<_>>().join("/") };
 let _=cdn_path_prefix; let now=chrono::Utc::now(); let amzdate=now.format("%Y%m%dT%H%M%SZ").to_string(); let datestamp=now.format("%Y%m%d").to_string(); let scope=format!("{datestamp}/us-east-1/s3/aws4_request"); let ksign=signing_key(st,&datestamp);
 let use_cdn=!st.cfg.rustfs_public.is_empty(); let (base, canonical_host, canonical_uri)=if use_cdn{ let pubbase=st.cfg.rustfs_public.trim_end_matches('/').to_string(); let host_only=pubbase.replace("https://","").replace("http://","").split('/').next().unwrap_or("").to_string(); (pubbase, host_only, format!("/{}",key)) } else { (endpoint.to_string(), host.clone(), format!("/{}/{}",st.cfg.rustfs_bucket,key)) };
 // CDN public URL shape is {RUSTFS_PUBLIC_URL}/{key} where RUSTFS_PUBLIC_URL already contains the bucket.
 let canonical_uri=if use_cdn{ let pubbase=st.cfg.rustfs_public.trim_end_matches('/'); let after=pubbase.replace("https://","").replace("http://",""); let path=after.split('/').skip(1).collect::<Vec<_>>().join("/"); if path.is_empty(){format!("/{}",key)}else{format!("/{}/{}",path,key)} } else {canonical_uri};
 let query=format!("X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential={}%2F{}&X-Amz-Date={}&X-Amz-Expires={}&X-Amz-SignedHeaders=host",st.cfg.rustfs_access,scope.replace('/',"%2F"),amzdate,expires);
 let canonical_q=format!("GET\n{canonical_uri}\n{query}\nhost:{canonical_host}\n\nhost\nUNSIGNED-PAYLOAD"); let sts=format!("AWS4-HMAC-SHA256\n{amzdate}\n{scope}\n{}",hex::encode(Sha256::digest(canonical_q.as_bytes()))); let mut mac=H::new_from_slice(&ksign).unwrap(); mac.update(sts.as_bytes()); let sig=hex::encode(mac.finalize().into_bytes());
 Ok(format!("{base}{}?{query}&X-Amz-Signature={sig}", if use_cdn{format!("/{}",key)}else{canonical_uri.clone()}))
}
async fn presign_put(st:&AppState,key:&str,content_type:&str,expires:u64)->Result<(String,String),Response>{
 use hmac::{Hmac,Mac}; use sha2::{Digest,Sha256}; type H=Hmac<Sha256>;
 if st.cfg.rustfs_access.is_empty()||st.cfg.rustfs_secret.is_empty(){return Err(err(StatusCode::BAD_GATEWAY,"Media storage is not configured."))}
 let endpoint=st.cfg.rustfs_endpoint.trim_end_matches('/'); let host=endpoint.replace("https://","").replace("http://",""); let now=chrono::Utc::now(); let amzdate=now.format("%Y%m%dT%H%M%SZ").to_string(); let datestamp=now.format("%Y%m%d").to_string(); let scope=format!("{datestamp}/us-east-1/s3/aws4_request"); let ksign=signing_key(st,&datestamp);
 let canonical_uri=format!("/{}/{}",st.cfg.rustfs_bucket,key);
 let query=format!("X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential={}%2F{}&X-Amz-Date={}&X-Amz-Expires={}&X-Amz-SignedHeaders=host",st.cfg.rustfs_access,scope.replace('/',"%2F"),amzdate,expires);
 let canonical_q=format!("PUT\n{canonical_uri}\n{query}\nhost:{host}\n\nhost\nUNSIGNED-PAYLOAD"); let sts=format!("AWS4-HMAC-SHA256\n{amzdate}\n{scope}\n{}",hex::encode(Sha256::digest(canonical_q.as_bytes()))); let mut mac=H::new_from_slice(&ksign).unwrap(); mac.update(sts.as_bytes()); let sig2=hex::encode(mac.finalize().into_bytes());
 let _=content_type;
 let upload=format!("{endpoint}{canonical_uri}?{query}&X-Amz-Signature={sig2}"); let signed=presign_get(st,key,7*24*3600).await?; Ok((upload,signed))
}

// ---------- CRUD ----------
#[derive(Deserialize)] struct DataReq{data:Value}
const ITEM_FIELDS:[&str;15]=["name","category","tags","description","condition","brand","material","unit","quantity","photo_urls","original_photo_url","cutout_photo_url","segmentation","status","is_published"];
const RECIPE_FIELDS:[&str;10]=["title","description","steps","difficulty","estimated_minutes","image_url","source_item_ids","used_items","missing_items","owner_id"];
const PROFILE_FIELDS:[&str;8]=["display_name","avatar_url","phone","whatsapp","bio","city","lat","lng"];

/// Sign-up that skips the confirmation email: the backend holds the service
/// role key, so it can create an already-confirmed user through the GoTrue
/// admin API. The client then signs in normally to obtain a session.
async fn register(State(st):State<AppState>,Json(req):Json<DataReq>)->Response{
 if st.cfg.supabase_url.is_empty()||st.cfg.supabase_service.is_empty(){return err(StatusCode::BAD_GATEWAY,"Backend storage is not configured.")}
 let email=s(&req.data["email"]).unwrap_or_default().to_lowercase();
 let password=s(&req.data["password"]).unwrap_or_default();
 let name=s(&req.data["displayName"]).or_else(||s(&req.data["display_name"])).unwrap_or_else(||email.split('@').next().unwrap_or("User").to_string());
 if !email.contains('@')||email.len()<5||password.len()<6{return err(StatusCode::BAD_REQUEST,"Enter a valid email and a password of at least 6 characters.")}
 let url=format!("{}/auth/v1/admin/users",st.cfg.supabase_url.trim_end_matches('/'));
 let body=json!({"email":email,"password":password,"email_confirm":true,"user_metadata":{"display_name":name}});
 let r=st.http.post(&url).header("apikey",&st.cfg.supabase_service).header("Authorization",format!("Bearer {}",st.cfg.supabase_service)).header("Content-Type","application/json").json(&body).send().await;
 let r=match r{Ok(v)=>v,Err(_)=>return err(StatusCode::BAD_GATEWAY,"Backend storage is unavailable.")};
 let status=r.status(); let text=r.text().await.unwrap_or_default();
 if !status.is_success(){
  let low=text.to_lowercase();
  if low.contains("already")||low.contains("exists")||status.as_u16()==422{return err(StatusCode::CONFLICT,"This email is already registered. Sign in instead.")}
  if low.contains("password"){return err(StatusCode::BAD_REQUEST,"Password is too weak. Use at least 6 characters.")}
  return err(StatusCode::BAD_GATEWAY,"Could not create the account. Please try again.")
 }
 let uid=serde_json::from_str::<Value>(&text).ok().and_then(|v|s(&v["id"])).unwrap_or_default();
 if !uid.is_empty(){
  if let Err(e)=pg_upsert(&st,"profiles","on_conflict=id",json!({"id":uid,"display_name":name})).await{eprintln!("profile bootstrap failed for {uid}"); let _=e;}
  if let Ok(Some(p))=pg_one(&st,"profiles",&format!("id=eq.{uid}&select=*")).await{return (StatusCode::CREATED,Json(p)).into_response()}
 }
 (StatusCode::CREATED,Json(json!({"id":uid,"display_name":name}))).into_response()
}

async fn me(State(st):State<AppState>,h:HeaderMap)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_one(&st,"profiles",&format!("id=eq.{uid}&select=*")).await{Ok(Some(p))=>(StatusCode::OK,Json(p)).into_response(),Ok(None)=>(StatusCode::OK,Json(json!({"id":uid,"display_name":"User"}))).into_response(),Err(e)=>e} }
async fn update_me(State(st):State<AppState>,h:HeaderMap,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let mut body=pick(&req.data,&PROFILE_FIELDS); body.insert("id".into(),json!(uid)); match pg_upsert(&st,"profiles","on_conflict=id",Value::Object(body)).await{Ok(mut v)=>{let one=v.pop().unwrap_or(json!({"id":uid})); (StatusCode::OK,Json(one)).into_response()},Err(e)=>e} }

async fn create_item(State(st):State<AppState>,h:HeaderMap,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let mut body=pick(&req.data,&ITEM_FIELDS); if let Some(id)=s(&req.data["id"]){body.insert("id".into(),json!(id));} body.insert("owner_id".into(),json!(uid)); match pg_send(&st,reqwest::Method::POST,"items","",Value::Object(body)).await{Ok(mut v)=>(StatusCode::CREATED,Json(v.pop().unwrap_or(Value::Null))).into_response(),Err(e)=>e} }
async fn list_items(State(st):State<AppState>,h:HeaderMap)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_get(&st,"items",&format!("owner_id=eq.{uid}&select=*&order=created_at.desc&limit=200")).await{Ok(v)=>(StatusCode::OK,Json(Value::Array(v))).into_response(),Err(e)=>e} }
async fn get_item(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_one(&st,"items",&format!("id=eq.{id}&select=*")).await{Ok(Some(v))=>{ if s(&v["owner_id"]).as_deref()==Some(uid.as_str())||v["is_published"].as_bool()==Some(true){(StatusCode::OK,Json(v)).into_response()}else{err(StatusCode::NOT_FOUND,"Not found.")} },Ok(None)=>err(StatusCode::NOT_FOUND,"Not found."),Err(e)=>e} }
async fn update_item(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let existing=match pg_one(&st,"items",&format!("id=eq.{id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match existing{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} let body=pick(&req.data,&ITEM_FIELDS); match pg_send(&st,reqwest::Method::PATCH,"items",&format!("id=eq.{id}"),Value::Object(body)).await{Ok(mut v)=>(StatusCode::OK,Json(v.pop().unwrap_or(Value::Null))).into_response(),Err(e)=>e} }
async fn delete_item(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let existing=match pg_one(&st,"items",&format!("id=eq.{id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match existing{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} match pg_send(&st,reqwest::Method::DELETE,"items",&format!("id=eq.{id}"),Value::Null).await{Ok(_)=>(StatusCode::OK,Json(json!({"ok":true}))).into_response(),Err(e)=>e} }

async fn list_listings(State(st):State<AppState>,h:HeaderMap)->Response{ if let Err(e)=verify(&st,&h).await{return e} match pg_get(&st,"community_listings","is_active=eq.true&select=*,items(*),profiles!community_listings_owner_id_fkey(*)&order=created_at.desc&limit=200").await{Ok(v)=>(StatusCode::OK,Json(Value::Array(v))).into_response(),Err(e)=>e} }
async fn get_listing(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>)->Response{ if let Err(e)=verify(&st,&h).await{return e} match pg_one(&st,"community_listings",&format!("id=eq.{id}&select=*,items(*),profiles!community_listings_owner_id_fkey(*)")).await{Ok(Some(v))=>(StatusCode::OK,Json(v)).into_response(),Ok(None)=>err(StatusCode::NOT_FOUND,"Not found."),Err(e)=>e} }
async fn listing_by_item(State(st):State<AppState>,h:HeaderMap,Path(item_id):Path<String>)->Response{ if let Err(e)=verify(&st,&h).await{return e} match pg_one(&st,"community_listings",&format!("item_id=eq.{item_id}&is_active=eq.true&select=*,items(*),profiles!community_listings_owner_id_fkey(*)")).await{Ok(Some(v))=>(StatusCode::OK,Json(v)).into_response(),Ok(None)=>err(StatusCode::NOT_FOUND,"Not found."),Err(e)=>e} }
async fn create_listing(State(st):State<AppState>,h:HeaderMap,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let item_id=match s(&req.data["item_id"]).or_else(||s(&req.data["itemId"])){Some(v)=>v,None=>return err(StatusCode::BAD_REQUEST,"Invalid request.")}; let item=match pg_one(&st,"items",&format!("id=eq.{item_id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match item{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} let lt=s(&req.data["listing_type"]).or_else(||s(&req.data["listingType"])).unwrap_or_else(||"gratis".into()); let mut body=Map::new(); body.insert("item_id".into(),json!(item_id)); body.insert("owner_id".into(),json!(uid)); body.insert("listing_type".into(),json!(lt)); body.insert("price".into(), if lt=="jual"{req.data["price"].clone()}else{Value::Null}); body.insert("note".into(),req.data["note"].clone()); body.insert("lat".into(),req.data["lat"].clone()); body.insert("lng".into(),req.data["lng"].clone()); body.insert("is_active".into(),json!(true)); let created=match pg_send(&st,reqwest::Method::POST,"community_listings","",Value::Object(body)).await{Ok(mut v)=>v.pop().unwrap_or(Value::Null),Err(e)=>return e}; let _=pg_send(&st,reqwest::Method::PATCH,"items",&format!("id=eq.{item_id}"),json!({"is_published":true})).await; // re-fetch with joins for client model
 match pg_one(&st,"community_listings",&format!("id=eq.{}&select=*,items(*),profiles!community_listings_owner_id_fkey(*)",s(&created["id"]).unwrap_or_default())).await{Ok(Some(v))=>(StatusCode::CREATED,Json(v)).into_response(),_=> (StatusCode::CREATED,Json(created)).into_response()} }
async fn update_listing(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let ex=match pg_one(&st,"community_listings",&format!("id=eq.{id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match ex{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} let lt=s(&req.data["listing_type"]).or_else(||s(&req.data["listingType"])).unwrap_or_else(||"gratis".into()); let body=json!({"listing_type":lt,"price": if lt=="jual"{req.data["price"].clone()}else{Value::Null},"note":req.data["note"].clone(),"lat":req.data["lat"].clone(),"lng":req.data["lng"].clone()}); let _=match pg_send(&st,reqwest::Method::PATCH,"community_listings",&format!("id=eq.{id}"),body).await{Ok(v)=>v,Err(e)=>return e}; match pg_one(&st,"community_listings",&format!("id=eq.{id}&select=*,items(*),profiles!community_listings_owner_id_fkey(*)")).await{Ok(Some(v))=>(StatusCode::OK,Json(v)).into_response(),_=>err(StatusCode::NOT_FOUND,"Not found.")} }
async fn close_listing(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>,Json(_req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let ex=match pg_one(&st,"community_listings",&format!("id=eq.{id}&select=owner_id,item_id")).await{Ok(v)=>v,Err(e)=>return e}; let item_id=match ex{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>s(&v["item_id"]).unwrap_or_default(),_=>return err(StatusCode::NOT_FOUND,"Not found.")}; let _=pg_send(&st,reqwest::Method::PATCH,"community_listings",&format!("id=eq.{id}"),json!({"is_active":false})).await; let _=pg_send(&st,reqwest::Method::PATCH,"items",&format!("id=eq.{item_id}"),json!({"is_published":false})).await; (StatusCode::OK,Json(json!({"ok":true}))).into_response() }

async fn list_favorites(State(st):State<AppState>,h:HeaderMap)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_get(&st,"favorites",&format!("user_id=eq.{uid}&select=listing_id")).await{Ok(v)=>{let ids:Vec<String>=v.iter().filter_map(|r|s(&r["listing_id"])).collect(); (StatusCode::OK,Json(json!({"ids":ids}))).into_response()},Err(e)=>e} }
async fn toggle_favorite(State(st):State<AppState>,h:HeaderMap,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let listing_id=match s(&req.data["listing_id"]).or_else(||s(&req.data["listingId"])){Some(v)=>v,None=>return err(StatusCode::BAD_REQUEST,"Invalid request.")}; let fav=req.data["fav"].as_bool().unwrap_or(true); if fav{ let _=pg_send(&st,reqwest::Method::POST,"favorites","on_conflict=user_id,listing_id",json!({"user_id":uid,"listing_id":listing_id})).await; } else { let _=pg_send(&st,reqwest::Method::DELETE,"favorites",&format!("user_id=eq.{uid}&listing_id=eq.{listing_id}"),Value::Null).await; } (StatusCode::OK,Json(json!({"ok":true}))).into_response() }

async fn list_recipes(State(st):State<AppState>,h:HeaderMap)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_get(&st,"fuse_recipes",&format!("owner_id=eq.{uid}&select=*&order=created_at.desc&limit=100")).await{Ok(v)=>(StatusCode::OK,Json(Value::Array(v))).into_response(),Err(e)=>e} }
async fn get_recipe(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; match pg_one(&st,"fuse_recipes",&format!("id=eq.{id}&select=*")).await{Ok(Some(v))=>{ if s(&v["owner_id"]).as_deref()==Some(uid.as_str()){(StatusCode::OK,Json(v)).into_response()}else{err(StatusCode::NOT_FOUND,"Not found.")} },Ok(None)=>err(StatusCode::NOT_FOUND,"Not found."),Err(e)=>e} }
async fn create_recipe(State(st):State<AppState>,h:HeaderMap,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let mut body=pick(&req.data,&RECIPE_FIELDS); body.insert("owner_id".into(),json!(uid)); if let Some(id)=s(&req.data["id"]){body.insert("id".into(),json!(id));} match pg_send(&st,reqwest::Method::POST,"fuse_recipes","",Value::Object(body)).await{Ok(mut v)=>(StatusCode::CREATED,Json(v.pop().unwrap_or(Value::Null))).into_response(),Err(e)=>e} }
async fn update_recipe_image(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>,Json(req):Json<DataReq>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let ex=match pg_one(&st,"fuse_recipes",&format!("id=eq.{id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match ex{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} let url=s(&req.data["imageUrl"]).or_else(||s(&req.data["image_url"])).unwrap_or_default(); match pg_send(&st,reqwest::Method::PATCH,"fuse_recipes",&format!("id=eq.{id}"),json!({"image_url":url})).await{Ok(_)=>(StatusCode::OK,Json(json!({"ok":true}))).into_response(),Err(e)=>e} }
async fn delete_recipe(State(st):State<AppState>,h:HeaderMap,Path(id):Path<String>)->Response{ let uid=match verify(&st,&h).await{Ok(v)=>v,Err(e)=>return e}; let ex=match pg_one(&st,"fuse_recipes",&format!("id=eq.{id}&select=owner_id")).await{Ok(v)=>v,Err(e)=>return e}; match ex{Some(v) if s(&v["owner_id"]).as_deref()==Some(uid.as_str())=>{},_=>return err(StatusCode::NOT_FOUND,"Not found.")} match pg_send(&st,reqwest::Method::DELETE,"fuse_recipes",&format!("id=eq.{id}"),Value::Null).await{Ok(_)=>(StatusCode::OK,Json(json!({"ok":true}))).into_response(),Err(e)=>e} }

async fn list_banks(State(st):State<AppState>)->Response{ match pg_get(&st,"waste_banks","select=*&order=name&limit=200").await{Ok(v)=>(StatusCode::OK,Json(Value::Array(v))).into_response(),Err(e)=>e} }
async fn get_bank(State(st):State<AppState>,Path(id):Path<String>)->Response{ match pg_one(&st,"waste_banks",&format!("id=eq.{id}&select=*")).await{Ok(Some(v))=>(StatusCode::OK,Json(v)).into_response(),Ok(None)=>err(StatusCode::NOT_FOUND,"Not found."),Err(e)=>e} }
/// Public media read proxy: RustFS buckets are private, so the stable URL stored
/// in Postgres is `{BACKEND_PUBLIC_URL}/v1/media/file/{key}` (no expiry, unlike
/// presigned URLs). Backend fetches with a short-lived signed GET and streams.
async fn media_file(State(st):State<AppState>,Path(key):Path<String>)->Response{
 if key.contains("..")||key.is_empty(){return err(StatusCode::BAD_REQUEST,"Invalid request.")}
 let signed=match presign_get(&st,&key,900).await{Ok(v)=>v,Err(e)=>return e};
 let r=match st.http.get(&signed).send().await{Ok(v)=>v,Err(_)=>return err(StatusCode::BAD_GATEWAY,"Media storage is unavailable.")};
 if !r.status().is_success(){return err(StatusCode::NOT_FOUND,"Not found.")}
 let ct=r.headers().get("content-type").and_then(|v|v.to_str().ok()).unwrap_or("application/octet-stream").to_string();
 let bytes=match r.bytes().await{Ok(v)=>v,Err(_)=>return err(StatusCode::BAD_GATEWAY,"Media storage is unavailable.")};
 (StatusCode::OK,[(axum::http::header::CONTENT_TYPE,ct),(axum::http::header::CACHE_CONTROL,"public, max-age=3600".to_string())],bytes).into_response()
}

#[tokio::main]
async fn main(){
 tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).init();
 let cfg=Arc::new(Config::load()); let state=AppState{cfg,http:reqwest::Client::new()};
 let cors=CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any);
 let app=Router::new()
  .route("/health",get(health))
  .route("/v1/ai/analyze-item",post(analyze))
  .route("/v1/ai/suggest-prompts",post(suggest))
  .route("/v1/ai/segment",post(segment))
  .route("/v1/ai/fuse",post(fuse))
  .route("/v1/ai/fuse-image",post(fuse_image))
  .route("/v1/media/presign",post(presign))
  .route("/v1/media/upload",post(upload))
  .route("/v1/media/file/{*key}",get(media_file))
  .route("/v1/auth/me",get(me).patch(update_me))
  .route("/v1/auth/register",post(register))
  .route("/v1/items",get(list_items).post(create_item))
  .route("/v1/items/{id}",get(get_item).patch(update_item).delete(delete_item))
  .route("/v1/listings",get(list_listings).post(create_listing))
  .route("/v1/listings/by-item/{itemId}",get(listing_by_item))
  .route("/v1/listings/{id}",get(get_listing).patch(update_listing))
  .route("/v1/listings/{id}/close",post(close_listing))
  .route("/v1/favorites",get(list_favorites).post(toggle_favorite))
  .route("/v1/recipes",get(list_recipes).post(create_recipe))
  .route("/v1/recipes/{id}",get(get_recipe).delete(delete_recipe))
  .route("/v1/recipes/{id}/image",patch(update_recipe_image))
  .route("/v1/waste-banks",get(list_banks))
  .route("/v1/waste-banks/{id}",get(get_bank))
  .layer(axum::extract::DefaultBodyLimit::max(10_000_000))
  .layer(cors).with_state(state);
 let port=env("PORT","8080"); let listener=tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await.unwrap(); tracing::info!("recygo-backend listening on {port}"); axum::serve(listener,app).await.unwrap();
}
