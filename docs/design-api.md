# API Design: กลับด้วยกันมั้ย (GOWITHME) MVP 0.1

Backend = Supabase (PostgREST + RPC + Realtime + Storage + optional Edge Functions). "API" ของระบบคือ **สัญญา (contract) ระหว่าง Flutter client กับ Supabase** บวก **client ของบริการภายนอก (OSRM, Nominatim)**
Inputs: `docs/requirements.md`, `docs/design-db.md`, `supabase/migrations/0001_init.sql`. Machine-readable: `docs/openapi.yaml`.
ข้อสมมติแทนการถามกลับอยู่ท้ายเอกสาร (หัวข้อ 12).

---

## 1. Requirements analysis (Step 1)

**Consumers**
| Actor | Credential | เข้าถึงอะไร |
|---|---|---|
| anon (ผู้รับลิงก์แชร์, ก่อน login) | anon key | `get_shared_trip(token)` เท่านั้น + Auth endpoints (signup/login/recover) |
| authenticated (สมาชิก) | anon key + user JWT | PostgREST ตามที่ GRANT/RLS อนุญาต + RPC + Realtime + Storage `avatars` |
| admin | JWT `app_metadata.role='admin'` | อ่าน `reports`, `sos_events`, `profiles` (ไม่มี UI ใน MVP) |
| service | service_role (ห้ามอยู่ในแอป) | `purge_expired_data()` ผ่าน pg_cron / Edge Function schedule |

**Access pattern (สูง -> ต่ำ)**: (1) `trip_locations` insert ทุก 15-30 วิ (write-heavy, fire-and-forget) (2) chat read/subscribe + insert (3) `find_matches` (read, แพงสุดฝั่ง DB) (4) my trips / match inbox (5) `get_shared_trip` (anon, polling ทุก 15-30 วิ จากหน้าเว็บผู้รับ) (6) auth/profile (ต่ำ).

**High-impact operations (ต้อง idempotent/audit)** — ไม่มีเงินใน MVP; "state สำคัญ" คือ:
`sos_events` (safety-critical, ห้ามหาย/ห้ามซ้ำจน spam), `request_match`/`respond_match` (race ขอพร้อมกัน, limit 3), `trips` status transitions, `create_trip_share` (คืน token ดิบครั้งเดียว), `request_account_deletion` (PDPA), `chat_messages` insert (retry เมื่อเครือข่ายหลุด).

---

## 2. Surface และ versioning

| Surface | Base | Version strategy |
|---|---|---|
| PostgREST tables | `{SUPABASE_URL}/rest/v1/{table}` | `/v1` มากับ Supabase (คงที่). schema เปลี่ยนแบบ additive เท่านั้น |
| RPC | `{SUPABASE_URL}/rest/v1/rpc/{fn}` | **ห้ามเปลี่ยน signature เดิม**; breaking change = ฟังก์ชันใหม่ `find_matches_v2` แล้ว deprecate ตัวเดิมหลัง client เวอร์ชันเก่าหมดอายุ. พารามิเตอร์ใหม่ต้องมี `default` |
| Edge Functions | `{SUPABASE_URL}/functions/v1/{name}` | `/v1` มากับ Supabase; ถ้า breaking ใช้ชื่อ `share-view-v2` |
| Realtime | `wss://{project}.supabase.co/realtime/v1` | channel/table names เป็นส่วนหนึ่งของ contract |
| Client min-version gate | `app_config` key `client.min_version` (แนะนำเพิ่มใน 0002) | client เก่า -> แสดงหน้า "กรุณาอัปเดต" |

**Naming**: snake_case ทั้งระบบ (ตรงกับ column/RPC param; param ของ RPC ขึ้นต้น `p_`). วันที่ = ISO 8601 UTC (`timestamptz` -> `2026-09-25T13:00:00Z`). พิกัด: **lng ก่อน lat** ตอนเขียน (EWKT), RPC ขาออกเป็น `*_lat`/`*_lng` แยกฟิลด์เสมอ (ไม่ส่ง geography ดิบ). ไม่มีเงิน. Enum ส่งเป็น string ตรง DB (`walk|transit|car|taxi`, ...).

---

## 3. API Contract Map (Step 2)

Auth legend: `A`=anon key, `U`=authenticated JWT, `O`=เจ้าของแถว (RLS), `P`=participant ของ match, `T`=target ของ match, `S`=service_role, `Ad`=admin.
Idempotent: `Y` ทำซ้ำได้ผลเหมือนเดิม, `N` ไม่ idempotent, `Y*` idempotent เมื่อใช้กลไกที่ระบุ (หัวข้อ 7).

### 3.1 Auth (GoTrue `/auth/v1`)
| Resource | Endpoint | Auth | Idem | หมายเหตุ |
|---|---|---|---|---|
| session | `POST /auth/v1/signup` (data: `display_name, adult_confirmed, policy_version`) | A | N | trigger สร้าง profile+consent+verification |
| session | `POST /auth/v1/token?grant_type=password` / `refresh_token` | A | Y (refresh: ครั้งเดียวต่อ token, ดู 7.6) | |
| session | `POST /auth/v1/logout` | U | Y | |
| recovery | `POST /auth/v1/recover` | A | Y | P1 |
| account | `DELETE`/ลบบัญชี = RPC `request_account_deletion` | U | Y | ไม่มี admin delete API ฝั่ง client |

### 3.2 Resource -> PostgREST / RPC
| Resource | Operation | Endpoint | Auth | Idem |
|---|---|---|---|---|
| **profile** | อ่านของตน/คู่ accepted | `GET /rest/v1/profiles?id=eq.{id}` | U (RLS) | Y |
| | แก้ (display_name, avatar_path, locale, adult_confirmed_at) | `PATCH /rest/v1/profiles?id=eq.{me}` | U,O | Y |
| **consent** | บันทึก/ถอน | `POST /rest/v1/rpc/record_consent` `{p_kind,p_granted,p_version}` | U | N (append-only log; ซ้ำ = แถวซ้ำ ไม่เสียหาย) |
| | ประวัติ | `GET /rest/v1/consents?order=created_at.desc&limit=` | U,O | Y |
| **verification** | อ่านป้าย | `GET /rest/v1/verifications?user_id=eq.` | U | Y |
| | OTP mock | `POST /rpc/verify_phone_mock` `{p_phone,p_code}` | U | Y (upsert unique(user,kind)) |
| | ป้ายรวมของคนอื่น | ผ่าน `badges` ใน `find_matches`/`get_trip_card` | U | Y |
| **org_domain / app_config** | อ่าน config สาธารณะ | `GET /rest/v1/app_config?select=key,value` , `org_domains` | U | Y (cache 10 นาที) |
| **emergency_contact** | list/create/update/delete | `GET/POST/PATCH/DELETE /rest/v1/emergency_contacts` | U,O | GET/PATCH/DELETE=Y, POST=N (unique(user_id,phone) กันซ้ำ = Y*) |
| **trip** | สร้าง | `POST /rest/v1/trips` (Prefer: return=representation) | U,O | N (กันซ้ำด้วย `GWM_ACTIVE_TRIP_LIMIT`, ดู 7.3) |
| | list ของฉัน | `GET /rest/v1/trips?user_id=eq.{me}&status=in.(...)&order=created_at.desc&limit=&` | U,O | Y |
| | เริ่ม/จบ/ยกเลิก | `PATCH /rest/v1/trips?id=eq.{id}` `{status}` | U,O | Y (PATCH ไป status เดิมซ้ำ: ดู 7.3) |
| | แก้เวลา/วิธี (P1) | `PATCH /rest/v1/trips?id=eq.{id}` | U,O | Y |
| | ลบ (soft) | `PATCH … {deleted_at}` (ต้อง cancelled/completed ก่อน) | U,O | Y |
| **trip_location** | ส่งตำแหน่งสด | `POST /rest/v1/trip_locations` `{trip_id,user_id,location,accuracy_m}` (1 แถว/5 วิ) | U,O | N (append; ซ้ำไม่อันตราย) |
| **match candidates** | หาคู่ | `POST /rpc/find_matches` `{p_trip_id,p_limit}` | U,O(trip) | Y (read; deterministic) |
| | การ์ดทริปคู่ | `POST /rpc/get_trip_card` `{p_trip_id}` | U | Y |
| **match** | ส่งคำขอ | `POST /rpc/request_match` `{p_my_trip,p_target_trip}` -> uuid | U | Y* (7.2) |
| | ตอบรับ/ปฏิเสธ | `POST /rpc/respond_match` `{p_match_id,p_accept,p_meet_lng,p_meet_lat,p_meet_label}` -> status | U,T | Y* (7.2) |
| | ตั้งจุดนัดพบ | `POST /rpc/set_meeting_point` | U,P | Y |
| | ยกเลิก | `POST /rpc/cancel_match` `{p_match_id}` | U,P | Y* |
| | inbox / list | `GET /rest/v1/matches?or=(requester_id.eq.{me},target_id.eq.{me})&status=in.()&order=created_at.desc&limit=` | U,P (RLS) | Y |
| | ตำแหน่งสดของคู่ | `POST /rpc/get_partner_live_location` `{p_match_id}` (poll 15-30 วิ) | U,P | Y (read) |
| **chat_message** | ประวัติ | `GET /rest/v1/chat_messages?match_id=eq.{id}&order=created_at.desc,id.desc&limit=30` (+keyset) | U,P | Y |
| | ส่ง | `POST /rest/v1/chat_messages` `{match_id,sender_id,body,client_msg_id}` | U,P (RLS `is_chat_open`) | Y* (client_msg_id, 7.4) |
| | live | Realtime `postgres_changes` INSERT `chat_messages` filter `match_id=eq.` | U,P | - |
| | match status live | Realtime `postgres_changes` `matches` (filter `target_id=eq.{me}` และ `requester_id=eq.{me}` = 2 subscription) | U,P | - |
| **block** | block/unblock/list | `POST /rest/v1/blocks`, `DELETE …?blocked_id=eq.`, `GET` | U,O | POST=Y* (PK ซ้ำ -> 23505 ตีเป็นสำเร็จ), DELETE=Y |
| **report** | รายงาน | `POST /rest/v1/reports` | U | N (เจตนา: หลายรายงานได้; client กด double-tap กัน) |
| **sos_event** | บันทึกเหตุ SOS | `POST /rest/v1/sos_events` | U,O | Y* (7.1 — **ต้องแก้ grant ใน 0002**) |
| | ประวัติ | `GET /rest/v1/sos_events?order=created_at.desc&limit=` | U,O / Ad | Y |
| **trip_share** | สร้างลิงก์ | `POST /rpc/create_trip_share` `{p_trip_id,p_ttl_min}` -> `{share_id,token,share_expires_at}` | U,O | N (token ใหม่ทุกครั้ง; limit 10 active) |
| | เพิกถอน | `POST /rpc/revoke_trip_share` `{p_share_id}` | U,O | Y |
| | list ที่ active | `GET /rest/v1/trip_shares?revoked_at=is.null&expires_at=gt.now` | U,O | Y |
| | **ผู้รับเปิดลิงก์** | `POST /rpc/get_shared_trip` `{p_token}` หรือ Edge Function `GET /functions/v1/share-view?t={token}` | **A** | Y (read; side effect เดียว = `last_viewed_at`) |
| **avatar** | upload/read/delete | Storage `avatars/{uid}/{file}` (signed URL 60-300 วิ) | U,O / partner อ่าน | PUT=Y (upsert path คงที่ `avatar.jpg`) |
| **PDPA** | export | `POST /rpc/export_my_data` | U | Y |
| | ลบบัญชี | `POST /rpc/request_account_deletion` | U | Y |
| **maintenance** | purge | `select purge_expired_data()` (cron) | S | Y |

**Nesting**: PostgREST เป็น flat; ความสัมพันธ์แสดงด้วย FK filter (`chat_messages?match_id=eq.`, `trip_locations?trip_id=eq.`) และ embedded resource เฉพาะตารางที่ RLS อนุญาต (เช่น `matches?select=*,chat_messages(*)` ห้ามใช้ embed `trips` ของคู่ — RLS ตัดทิ้งอยู่แล้ว). ข้อมูลของคู่อ่านผ่าน RPC blur เท่านั้น.

### 3.2.1 Edge Functions (optional, ไม่จำเป็นต่อ P0)
| Function | เหตุผล | Auth | สถานะ |
|---|---|---|---|
| `share-view` | หน้าเว็บ/JSON สำหรับผู้รับลิงก์ (US-11 P1): rate limit ต่อ IP, 404 เดียวกันทุกกรณี, `Cache-Control: no-store`, ไม่ส่ง header ที่บอกเหตุผลที่ token ใช้ไม่ได้, render HTML + แผนที่ OSM | verify_jwt=false (anon) | แนะนำเมื่อทำ P1 web; MVP ข้อความแชร์ (P0) ไม่ต้องใช้ |
| `sos-dispatch` | อนาคต: ส่ง SMS/LINE Notify ให้ผู้ติดต่อฉุกเฉิน (out-of-scope MVP) | U | ไม่ทำใน MVP; MVP = insert `sos_events` + share sheet |
| `purge-cron` | ถ้า pg_cron ไม่พร้อม: schedule เรียก `purge_expired_data()` ด้วย service_role | S (secret header) | fallback |
| `rate-gate` | ไม่แนะนำในตอนนี้ (ดู 8) | - | - |

---

## 4. REST Design Audit (Step 3)

**RMM** — PostgREST ตาราง = Level 2 (resource path + verb ตรงความหมาย + status ตรง). RPC `POST /rpc/{fn}` = **Level 1 โดยเจตนา** (verb เดียว, function-oriented): ยอมรับได้เพราะเป็นเส้นทางเดียวที่บังคับ privacy/eligibility ฝั่ง DB (ตาม design-db §8) ไม่ใช่ CRUD. Level 3 (HATEOAS) ไม่ทำ — client เป็นแอปของเราเอง ไม่ต้อง discover flow.

| Endpoint | RMM | Idempotent | Status codes | Auth | Notes / Violations |
|---|---|---|---|---|---|
| `GET /rest/v1/trips` | 2 | Y | 200, 401, 400 | U,O | ต้องใส่ `limit` เสมอ (PostgREST ไม่บังคับ; ตั้ง `db-max-rows`=1000 ที่ project) |
| `POST /rest/v1/trips` | 2 | N | 201, 400 (GWM_*), 403, 409 | U,O | V1: ไม่มี idempotency key -> ดู 7.3 |
| `PATCH /rest/v1/trips?id=` | 2 | Y (status เดิม -> `GWM_INVALID_TRIP_TRANSITION` 400) | 200/204, 400, 403 | U,O | V2: "ซ้ำแล้ว error" ทำให้ retry อัตโนมัติไม่ safe -> client ต้อง treat "already in target state" เป็นสำเร็จ (7.3) |
| `POST /rest/v1/trip_locations` | 2 | N (append) | 201, 400 (`GWM_RATE_LIMITED`), 403 | U,O | 1 แถว/5 วิ/ทริป (trigger); ไม่มี dedupe — ยอมได้ (7.5) |
| `POST /rpc/find_matches` | 1 | Y | 200, 403 | U,O | **POST แต่ safe/read-only** (PostgREST ให้ `GET /rpc` สำหรับ STABLE fn ด้วย; ใช้ POST เพราะ payload/พารามิเตอร์ไม่ควรอยู่ใน URL/log). `p_limit` ถูก clamp 1-50 ใน SQL แล้ว (anti-scraping) |
| `POST /rpc/request_match` | 1 | Y* | 200 (uuid), 400 GWM_*, 403 | U | V4: ซ้ำ -> `GWM_ALREADY_REQUESTED` 400 แทนคืน id เดิม (7.2) |
| `POST /rpc/respond_match` | 1 | Y* | 200, 400 `GWM_MATCH_NOT_FOUND` | U,T | ตอบซ้ำ -> NOT_FOUND (status ไม่ใช่ pending) -> client ต้อง refetch |
| `POST /rpc/cancel_match`, `set_meeting_point` | 1 | Y | 200/204, 400 | U,P | |
| `GET/POST /rest/v1/chat_messages` | 2 | GET Y, POST Y* | 200, 201, 403 (RLS), 409 (dup client_msg_id), 400 (body) | U,P | V5: RLS deny = 403 `42501` ไม่แยกว่า "แชทปิดแล้ว" กับ "ไม่ใช่สมาชิก" — client ต้อง refetch match/trip status เพื่อแสดงข้อความ read-only |
| `POST /rest/v1/sos_events` | 2 | Y* หลังแก้ | 201, 403, 409 | U,O | **V6: ไม่มีกลไก idempotency ใน 0001** (`id` ไม่อยู่ใน column grant) -> 7.1 |
| `POST /rpc/create_trip_share` | 1 | N | 200, 400 GWM_TRIP_NOT_FOUND/GWM_SHARE_LIMIT | U,O | คืน token ดิบครั้งเดียว: **response ห้าม log/cache**; retry หลัง timeout = ได้ token ใหม่ (ปลอดภัย, orphan ลิงก์เก่าหมดอายุเอง) |
| `POST /rpc/get_shared_trip` | 1 | Y | 200 (`[]` เมื่อ invalid) | **A** | V7: invalid token คืน **200 + array ว่าง** (ไม่ใช่ 404) -> ต้อง map เป็น "ลิงก์หมดอายุ/ไม่ถูกต้อง" ที่ client/Edge Function และห้ามแยกเหตุผล (กัน oracle) |
| `POST /rpc/request_account_deletion` | 1 | Y | 200/204 | U | |
| Storage `avatars` | 2 | PUT Y | 200, 400, 403, 413 | U,O | จำกัด 2 MB/mime ที่ bucket |
| Auth `/signup` | 2 | N | 200, 422 (email/password), 429 | A | |

**HTTP semantics**
- ไม่มี GET ที่มี side effect ยกเว้น `get_shared_trip` (POST อยู่แล้ว) ที่อัปเดต `last_viewed_at` — ยอมรับ (audit field, ไม่กระทบ state ธุรกิจ). หากเปิดผ่าน Edge Function ใช้ GET ได้เพราะ side effect ไม่ใช่ business state.
- PUT ไม่ใช้เลย (PostgREST ใช้ PATCH สำหรับ partial) — ไม่มี PUT ที่ไม่ idempotent.
- **V8 (สำคัญ)**: PostgREST map `RAISE EXCEPTION ... errcode 'P0001'` เป็น **400** และ `42501` เป็น **403** (401 ถ้า role=anon). ไม่มี 404/409/422 ตามธรรมชาติสำหรับ business error -> เราแยกที่ **`message = GWM_*`** (machine-readable) ไม่ใช่ HTTP status (หัวข้อ 6). ยอมรับเป็น tradeoff.
- ไม่มี endpoint ที่คืน 200 ทั้งที่ error ยกเว้น V7.

**Error contract violations ที่พบ + แก้**: (a) error ของ PostgREST เป็น `{code,message,details,hint}` ไม่ใช่ envelope กลาง -> แก้ด้วย adapter ฝั่ง Flutter (หัวข้อ 6) ไม่แตะ server (แก้ไม่ได้บน PostgREST); Edge Functions ใช้ envelope กลางจริง. (b) `message` ของ Postgres error ปนภาษาอังกฤษ (`new row violates row-level security policy`) -> client ต้องไม่แสดงตรง ๆ.
**Security boundary**: validate ที่ DB (CHECK/trigger `trips_guard`, RLS, column GRANT) + client pre-validate เพื่อ UX; ไม่มี business logic อยู่นอก DB. ทุก endpoint ระบุ auth ในตาราง 3.

---

## 5. Auth / RLS boundary

หลัก: **anon key + user JWT เท่านั้นในแอป; service_role ห้ามอยู่ในแอป/Edge Function ที่ verify_jwt=false**. `REVOKE ALL` จาก anon/authenticated ทุกตาราง แล้ว GRANT ทีละคอลัมน์ (0001 §15).

| Boundary | บังคับที่ | ผลต่อ API |
|---|---|---|
| พิกัดจริงของ `trips` | RLS `trips_select_own` (ไม่มี policy คู่/admin) | `GET /trips?user_id=eq.{other}` -> `[]` (200 ว่าง ไม่ใช่ 403 — PostgREST กรองแถว). ห้ามใช้เป็นสัญญาณ "ไม่มีสิทธิ์" |
| ข้อมูลคู่ (blur) | SECURITY DEFINER RPC (`find_matches`, `get_trip_card`, `get_partner_live_location`) | client ห้ามพึ่ง embed |
| write ที่ต้องมี server logic | ไม่มี INSERT/UPDATE policy บน `matches`, `trip_shares`, `verifications` | ทำได้เฉพาะ RPC; direct write -> 403 `42501` |
| field ที่ client แก้ไม่ได้ | column GRANT (`started_at`, `ended_at`, `last_location`, `user_id` บน UPDATE ฯลฯ) | PATCH field ต้องห้าม -> 403 `42501 permission denied for table` |
| แชท | RLS insert `is_chat_open(match_id)` + `sender_id = auth.uid()` | ส่งเมื่อ match ไม่ accepted/ทริปจบ/block -> 403 |
| ตำแหน่งสด | RLS: trip in_progress + consent location | ไม่ consent -> 403 |
| admin | `app_metadata.role='admin'` (ตั้งด้วย service_role) | ไม่มี admin endpoint ใน MVP |
| anon | `get_shared_trip` + Auth only | ทุก endpoint อื่น -> 401/403 |

**Scope ต่อ endpoint** (แทน OAuth scope): ตัวกำหนดคือ (role, ความเป็นเจ้าของ/participant ผ่าน RLS/RPC, consent, สถานะทริป). Client ห้ามเดาสิทธิ์จาก UI.

**Input validation ที่ boundary**: RPC ใช้ typed params (uuid/enum/boolean/int) — PostgREST ปฏิเสธ type ผิดเป็น 400 (`22P02`) ก่อนเข้า function; text length = CHECK constraint (`body` 1-1000, `display_name` 1-60, `details` <=1000, `note` <=500); geometry = type `geography(Point/LineString,4326)` + `ST_NPoints>=2`; ค่าที่ business ตรวจ = `trips_guard`. Client ใช้ validator ชุดเดียวกัน (สอดคล้อง) แต่ **ไม่เชื่อ client**.

**Storage**: bucket private, path `{uid}/avatar.jpg`; client เก็บ `avatar_path` ใน profile แล้วขอ signed URL ตอนแสดง (cache ตาม expiry, ไม่เก็บ URL ถาวร). คู่ accepted อ่านได้ (`are_matched`).

**JWT**: access token อายุ 3600 วิ (default) — `supabase_flutter` refresh อัตโนมัติ; Realtime ต้อง `setAuth` ใหม่ (SDK ทำให้). การลบบัญชีต้อง invalidate session + ล้าง local storage.

---

## 6. Error envelope mapping (Client)

### 6.1 Canonical envelope (ทั้งระบบ, ใช้ภายใน client และ Edge Functions)
```json
{ "error": { "code": "GWM_ACTIVE_TRIP_LIMIT", "message": "ข้อความสำหรับนักพัฒนา (ไม่แสดงผู้ใช้)", "details": [ { "field": "depart_at", "reason": "in_past" } ], "retryable": false, "request_id": "..." } }
```
- `code` = machine-readable เสมอ (ไม่ผูกภาษา); UI แปลด้วย i18n key `error.<code>` (ARB) — ห้ามใช้ `message` จาก server แสดงผู้ใช้ (rule ภาษาไทย US-2).
- Edge Functions ตอบ envelope นี้ตรง ๆ. PostgREST/GoTrue/Storage ตอบรูปแบบของตน -> **`ErrorMapper` ฝั่ง Flutter** แปลงเป็น envelope นี้ที่เดียว (data layer boundary).

### 6.2 ตาราง mapping (source -> `AppFailure.code` -> HTTP -> UI/Retry)
| Source signal | ตัวอย่าง | canonical code | Retry? | UI (i18n) |
|---|---|---|---|---|
| PostgREST `code=P0001`, `message` เริ่ม `GWM_` (HTTP 400) | `GWM_DEPART_IN_PAST` | ใช้ `message` เป็น code ตรง ๆ | No | ข้อความเฉพาะ code, ระบุช่อง (`depart_at`) |
| `42501` + `message` เริ่ม `GWM_` (403) | `GWM_TRIP_NOT_FOUND`, `GWM_FORBIDDEN`, `GWM_UNAUTHENTICATED` | ตาม message | No (`GWM_UNAUTHENTICATED` -> sign-out flow) | |
| `42501` + `new row violates row-level security` (403) | แชทปิดแล้ว/ไม่ใช่ participant/ไม่มี consent | `FORBIDDEN_RLS` | No | refetch สถานะแล้วแสดง read-only / ขอ consent |
| `42501` + `permission denied` | PATCH column ห้ามแก้ | `FORBIDDEN_COLUMN` | No | bug — log (ไม่มี PII) |
| `23505` (409) | unique ซ้ำ: `chat_messages_client_uq`, `blocks_pkey`, `matches_pair_uq`, `emergency_contacts (user_id,phone)` | `DUPLICATE` -> ตีความตาม resource: chat/block = **สำเร็จ (idempotent hit)**, contact = "เบอร์นี้มีแล้ว" | No | |
| `23514` check violation (400) | body ว่าง/ยาวเกิน | `VALIDATION` + `details.field` | No | inline field error |
| `23503` FK (409) | อ้าง trip/match ที่ถูกลบ | `STALE_REFERENCE` | No | refetch |
| `22P02`/`22023`/`PGRST102` (400) | type ผิด | `VALIDATION` | No | bug |
| `PGRST116` (406) | `.single()` ได้ 0/หลายแถว | `NOT_FOUND` | No | |
| `PGRST301`/`PGRST303`/`401` JWT expired/invalid | | `SESSION_EXPIRED` | ครั้งเดียวหลัง `refreshSession()` | ไป login |
| `PGRST000/001/002`, `503`, `504`, `57014` (statement timeout) | DB/หรือโปรเจกต์ pause | `SERVER_UNAVAILABLE` | Yes (idempotent เท่านั้น) | "ลองใหม่" + banner |
| `500` / `P0002`/unknown | | `UNKNOWN` | No (auto) | generic + retry ปุ่มมือ |
| `429` (Supabase gateway/Auth `over_request_rate_limit`/`over_email_send_rate_limit`) | header `Retry-After` | `RATE_LIMITED` | Yes หลัง `Retry-After` (default 30 วิ) | "ลองใหม่อีกครั้งในอีกสักครู่" |
| GoTrue `invalid_credentials` (400) | | `AUTH_INVALID_CREDENTIALS` | No | ข้อความ**ทั่วไป** ไม่บอกว่าอะไรผิด (US-3) |
| GoTrue `user_already_exists` / `email_exists` (422) | | `AUTH_EMAIL_TAKEN` | No | ระบุช่องอีเมล |
| GoTrue `weak_password` (422) | | `AUTH_WEAK_PASSWORD` | No | ช่อง password |
| GoTrue `email_not_confirmed` (400) | | `AUTH_EMAIL_UNCONFIRMED` | No | ปุ่มส่งอีเมลซ้ำ |
| Storage `413`/`415` | | `UPLOAD_TOO_LARGE`/`UPLOAD_TYPE` | No | |
| Socket/DNS/timeout (`SocketException`, `TimeoutException`) | ออฟไลน์ | `NETWORK_OFFLINE` / `NETWORK_TIMEOUT` | Yes (idempotent) / queue (SOS, chat, locations) | banner ออฟไลน์ |
| Realtime `CHANNEL_ERROR`/`TIMED_OUT`/closed | | `REALTIME_DISCONNECTED` | Yes (resubscribe + backoff, แล้ว refetch จาก `created_at > last_seen`) | "กำลังเชื่อมต่อใหม่" |
| Missing config (`SUPABASE_URL` ว่าง) | | `CONFIG_MISSING` | No | หน้า setup (US-2) |
| `get_shared_trip` -> `[]` | | `SHARE_LINK_INVALID` (รวม expired/revoked/ไม่พบ ห้ามแยก) | No | |

**GWM_* -> UI ที่ควรมี (ครบ 26 code ตาม 0001 ปัจจุบัน)**: `GWM_RATE_LIMITED (retryable, รอ >=5 วิ), GWM_TRIP_RATE_LIMIT (10 ทริป/24 ชม.), GWM_TRIP_EDIT_LIMIT (แก้ geometry <=3 ครั้ง/ทริป), GWM_ACTIVE_TRIP_LIMIT, GWM_ALREADY_EXISTS, GWM_ALREADY_REQUESTED, GWM_CANCEL_BEFORE_DELETE, GWM_DEPART_IN_PAST, GWM_EMERGENCY_CONTACT_LIMIT, GWM_FORBIDDEN, GWM_IMMUTABLE, GWM_INVALID_CODE, GWM_INVALID_TRIP_TRANSITION, GWM_MATCH_LIMIT, GWM_MATCH_NOT_FOUND, GWM_MATCH_NOT_PENDING, GWM_NOT_ELIGIBLE, GWM_PHONE_MOCK_DISABLED, GWM_PROFILE_UNAVAILABLE, GWM_SHARE_LIMIT, GWM_TRIP_FINISHED, GWM_TRIP_NOT_FOUND, GWM_TRIP_STARTED, GWM_TRIP_TOO_SHORT, GWM_TRIP_UNAVAILABLE, GWM_UNAUTHENTICATED`. Unknown `GWM_*` (เพิ่มใน migration ใหม่) -> fallback `UNKNOWN` + log code (ห้ามล้ม).

### 6.3 Dart sketch
```dart
sealed class AppFailure { const AppFailure(this.code, {this.field, this.retryable = false, this.retryAfter}); final String code; final String? field; final bool retryable; final Duration? retryAfter; }
AppFailure mapError(Object e) { /* PostgrestException(code,message,details,hint) | AuthException(code,statusCode) |
   StorageException | FunctionException(status,details) | SocketException | TimeoutException -> table 6.2 */ }
// Repository methods return Result<T, AppFailure> (or throw AppFailure) — never leak PostgrestException above the data layer.
```

### 6.4 Success/collection/pagination contract
PostgREST คืน bare array/object ไม่มี `{data,pagination}` envelope -> **repository** ห่อเป็น `Page<T>{items, nextCursor, hasMore}` ที่ boundary (envelope กลางฝั่ง domain, ไม่ใช่ wire).
- **Cursor (keyset)** สำหรับข้อมูลโตต่อเนื่อง: chat ประวัติ `created_at.lt.{cursor_ts}` (tie-break `id`) `order=created_at.desc,id.desc&limit=N+1` (ขอเกิน 1 เพื่อรู้ `has_more`) ; ใช้ `Prefer: count=none`.
- **Limit-only** (dataset เล็ก/ถูกจำกัดโดย business): `find_matches` (limit <=50), my trips (`limit=20` + keyset ถ้าประวัติยาว), matches inbox (<=3 accepted, pending น้อย), emergency_contacts (<=3), blocks/consents (limit 50).
- **ห้าม unbounded**: ตั้ง `db-max-rows` และใส่ `limit` ทุก query ใน repository (lint ด้วย code review).
- ตัวอย่างหน้าจริง:
```json
// GET /rest/v1/chat_messages?match_id=eq.7f..&order=created_at.desc,id.desc&limit=31  -> repo แปลง
{ "items": [ {"id":"…","match_id":"7f..","sender_id":"…","kind":"user","body":"ถึงจุดนัดแล้วนะ","client_msg_id":"…","created_at":"2026-09-25T12:03:11Z"} ],
  "next_cursor": "2026-09-25T11:58:02Z|c1d2…", "has_more": true }
// RPC find_matches (จริงจาก DB, พิกัด blur, ระยะปัด 100 ม.)
[ { "trip_id":"…","display_name":"นุ่น","badges":{"email":true,"organization":"CU","phone":false},"mode":"transit","depart_at":"2026-09-25T13:00:00Z",
    "time_diff_min":10,"overlap_pct":72,"approx_distance_m":1200,"score":81.5,
    "approx_origin_lat":13.7455,"approx_origin_lng":100.5345,"approx_dest_lat":13.9,"approx_dest_lng":100.6,"request_status":null } ]
```
- Error ตัวอย่าง (wire จริงของ PostgREST -> หลัง map):
```json
{ "code":"P0001","message":"GWM_ACTIVE_TRIP_LIMIT","details":null,"hint":null }
=> { "error": { "code":"GWM_ACTIVE_TRIP_LIMIT", "message":"user already has an active trip", "details":[], "retryable":false } }
```

---

## 7. Idempotency & retry safety

Retry อัตโนมัติอนุญาตเฉพาะ operation ที่ Idem=Y/Y* และ error เป็น transient (network, 502/503/504, 429 หลัง Retry-After, statement timeout). Backoff: 500ms * 2^n + jitter, สูงสุด 3 ครั้ง, cap 8 วิ.

### 7.1 SOS (safety-critical: ต้อง "ไม่หาย" มากกว่า "ไม่ซ้ำ")
ปัญหาใน 0001: `sos_events` insert grant = `(user_id, trip_id, source, location, note, client_created_at)` — **ไม่มี `id` และไม่มี unique key** -> retry ที่ timeout อาจสร้างแถวซ้ำ (ไม่อันตรายต่อความปลอดภัยผู้ใช้ แต่ทำให้ audit ซ้ำ).
**สัญญา (ต้องเพิ่ม migration 0002)**:
1. `grant insert (id, user_id, trip_id, source, location, note, client_created_at) on sos_events` — client สร้าง `id` = UUIDv4/v7 **ก่อนกดยืนยัน** และเก็บใน local queue.
2. Insert ด้วย `Prefer: resolution=ignore-duplicates` (`POST /rest/v1/sos_events?on_conflict=id`) -> ส่งซ้ำได้ไม่ error/ไม่ซ้ำ (PK = idempotency key). (ไม่ต้อง header `Idempotency-Key` เพราะ PostgREST ไม่รองรับ; PK ทำหน้าที่แทน.)
3. `client_created_at` = เวลากดจริง (ฟิลด์เดิม, ตรงกับ offline queue P1); ถ้าอยู่นอก `[now-24h, now+5m]` server ควร clamp (เสนอ CHECK/trigger ใน 0002).
4. Flow: (a) กดยืนยัน -> **โทร/เปิด share sheet ก่อนเสมอ ไม่รอ network** (b) enqueue local (Drift/sqflite/Hive persisted) (c) ส่ง; สำเร็จ -> ลบจากคิว; fail transient -> retry exponential ต่อเนื่อง (ไม่จำกัดครั้งในช่วง 24 ชม.) + flush เมื่อ connectivity กลับ/app resume (d) fail permanent (403 `GWM_FORBIDDEN`: trip ไม่ใช่ของเรา) -> ทิ้งพร้อม log.
5. กด SOS ซ้ำ ๆ (panic tapping): client debounce 10 วิ ต่อ trip + สร้าง `id` เดียวต่อ "ช่วงเหตุการณ์" (ผูกกับ session ของหน้ายืนยัน) — ไม่ block การโทร.
6. **ไม่ rate-limit SOS ฝั่ง server** (ห้ามขวางขอความช่วยเหลือ; ตรงกับหลักออกแบบ design-db §8 ข้อสุดท้าย). กัน abuse ด้วย audit + admin เท่านั้น.
7. ทางเลือกอนาคต `sos-dispatch` Edge Function: รับ `{id, ...}` idempotent ด้วย id เดียวกัน แล้ว fan-out.

### 7.2 request_match / respond_match / cancel_match
- **Race ขอพร้อมกัน**: server ปลอดภัยอยู่แล้ว — `matches_pair_uq` (unordered pair) + `request_match` ถ้าอีกฝ่ายขอมาก่อนจะ auto-accept; ฝ่ายที่แพ้ได้ `GWM_ALREADY_REQUESTED`.
- **Retry ที่ timeout (ไม่รู้ว่าสำเร็จหรือไม่)**: การเรียกซ้ำจะได้ `GWM_ALREADY_REQUESTED` (400) ไม่ใช่ id เดิม. **สัญญา client**: เมื่อได้ `GWM_ALREADY_REQUESTED` หรือ `GWM_ALREADY_EXISTS` หลัง retry ของ request เดียวกัน -> `SELECT id,status FROM matches WHERE requester_trip_id=my AND target_trip_id=target` (RLS อนุญาต participant) แล้วถือเป็น**สำเร็จ**พร้อม id/สถานะจริง. ถ้าพบ match ที่ requester เป็นอีกฝ่าย = auto-accept race -> แสดง "จับคู่แล้ว".
- **ข้อเสนอ 0002 (ลด logic ฝั่ง client)**: ให้ `request_match` คืน id เดิมถ้า caller เป็น requester ของแถว pending เดียวกันอยู่แล้ว (idempotent จริง) และคงแยก `GWM_ALREADY_EXISTS` สำหรับ declined/cancelled.
- `respond_match`: ซ้ำ -> `GWM_MATCH_NOT_FOUND` (เพราะไม่ pending แล้ว) -> client refetch match; ถ้า status ตรงกับที่ตั้งใจ (accepted/declined) = สำเร็จ. `GWM_MATCH_LIMIT`/`GWM_TRIP_UNAVAILABLE` ไม่ retry.
- `cancel_match`: client ถือ "ไม่พบ/ไม่อยู่ในสถานะยกเลิกได้" หลัง retry = สำเร็จหาก refetch เจอ `cancelled`.
- ปุ่ม UI disable ขณะรอ (US-2 AC) + in-flight guard ต่อ (`fn`, `params`) ใน repository.

### 7.3 Trips
- **สร้างทริป**: ไม่มี key; กันซ้ำด้วย `GWM_ACTIVE_TRIP_LIMIT` (max_active=1). Retry หลัง timeout ที่ได้ `GWM_ACTIVE_TRIP_LIMIT` -> client query ทริป active ของตนเอง และถ้าเนื้อหา (origin/dest/depart_at ตรงกับที่ส่ง) ถือเป็นสำเร็จ. ข้อเสนอ 0002: เพิ่ม `id` ใน insert grant (client-generated UUID) + `on_conflict=id` เพื่อ idempotent แท้ (ควรทำคู่กับ SOS).
- **เปลี่ยน status**: PATCH ที่ตั้ง status เท่าเดิม -> trigger ให้ `GWM_INVALID_TRIP_TRANSITION`? (transition ตรวจเมื่อ `old.status <> new.status` เท่านั้น — ถ้าตรวจเฉพาะเมื่อเปลี่ยน จะเป็น no-op สำเร็จ; **ให้ test ยืนยัน**). Client: PATCH ด้วย filter `id=eq.X&status=eq.{expected_prev}` เพื่อกัน lost-update และ treat error transition ที่ refetch แล้วเห็น status เป้าหมาย = สำเร็จ.
- `GWM_TRIP_FINISHED / GWM_TRIP_STARTED / GWM_CANCEL_BEFORE_DELETE` = ไม่ retry, refetch.

### 7.4 Chat
`client_msg_id` (uuid v4 สร้างต่อข้อความ, คงเดิมเมื่อกดส่งซ้ำ) + unique partial `(sender_id, client_msg_id)`. ส่งซ้ำ -> `23505`/409 -> **ถือว่าสำเร็จ**, ดึงแถวจริงด้วย `client_msg_id`. UI สถานะ: sending / sent / failed(+ปุ่มส่งซ้ำ ใช้ id เดิม). Optimistic insert ด้วย `client_msg_id` แล้ว reconcile กับ Realtime event (dedupe key = `client_msg_id`, fallback `id`).

### 7.5 trip_locations
ไม่ idempotent โดยเจตนา (append-only breadcrumbs; ซ้ำ = แถวเกินไม่กี่แถว, ถูกลบใน 7 วัน). Client: **ส่งทีละ 1 แถว ห่างกัน >= 5 วิ** (0001 มี trigger `trip_locations_rate_guard`: แถวที่ 2 ภายใน 5 วิ ต่อทริป -> `GWM_RATE_LIMITED`; ห้ามพึ่ง batch), ถ้าได้ `GWM_RATE_LIMITED` = ทิ้งจุดนั้นเงียบ ๆ ไม่ retry; **ทิ้งจุดที่เก่ากว่า 2 นาที** (ตำแหน่งเก่าไม่มีค่า), ห้ามคิวยาวเพื่อไม่สร้างภาระ free tier. `recorded_at` default server now (ไม่อยู่ใน grant) — ยอมรับ.

### 7.6 Auth / อื่น ๆ
- Refresh token rotation: ห้ามยิง refresh พร้อมกันหลาย request (single-flight mutex ใน `AuthRepository`; SDK ทำอยู่แล้ว — อย่า bypass).
- `create_trip_share`: N, retry ปลอดภัย (ได้ token ใหม่, orphan หมดอายุ) แต่ **limit 10 active** -> ต้องเก็บ `share_id` ทันทีที่ได้ response; หลัง timeout ให้ list `trip_shares` ก่อน retry.
- `record_consent`: ซ้ำได้ (log). `verify_phone_mock`, `revoke_trip_share`, `request_account_deletion`, `export_my_data`: retry ได้.
- **POST ทั่วไปไม่มี `Idempotency-Key` header**: PostgREST ไม่รองรับ header นี้. สัญญาเทียบเท่า = client-generated PK/`client_msg_id` + unique constraint (DB เป็นตัวตัดสิน). หากมี Edge Function ที่มี side effect ภายนอก (อนาคต: SMS) ต้องรับ `Idempotency-Key` และเก็บตาราง `idempotency_keys(key, user_id, response, created_at)` TTL 24 ชม.

Retry matrix
| Operation | Auto-retry | Condition |
|---|---|---|
| GET/RPC read (`find_matches`, `get_*`, list) | Yes | transient |
| PATCH trip status / profile / contacts | Yes | transient + guard `status=eq.prev` |
| POST chat | Yes | ใช้ `client_msg_id` เดิม |
| POST sos_events | Yes (ไม่จำกัดครั้งใน 24 ชม.) | ต้องมี 0002 (`id` PK) |
| POST trips | Yes | ต้อง 0002 หรือ verify-then-treat-success |
| `request_match` | Yes | + verify-then-treat-success (7.2) |
| `create_trip_share` | Manual | list ก่อน |
| `trip_locations` | Limited (<=2, ทิ้งเมื่อเก่า) | |
| Auth signup | No | ปุ่ม disable |

---

## 8. Rate limits

0001 มี DB throttle แล้วบางจุด (ดูแถว "DB triggers ใน 0001"); ที่เหลือยังไม่มี. ชั้นที่มีจริงบน Supabase free tier + ที่ควรเพิ่ม:

| Layer | Limit | หมายเหตุ |
|---|---|---|
| Supabase Auth (dashboard, ปรับได้) | signup/sign-in ต่อ IP ~ 30/5 นาที; email send ตามแผน (built-in SMTP ต่ำมาก ~ 2-4/ชม. บน free — **ตั้ง custom SMTP** ก่อนทดสอบหลายคน) | ตอบ 429 `over_*_rate_limit` |
| PostgREST/gateway | ไม่มี per-user quota ตายตัว; ป้องกันด้วยขนาดโปรเจกต์ | ตั้ง `statement_timeout` ของ role `authenticated` (แนะนำ 8s) และ `db-max-rows` |
| Realtime (free) | จำกัด concurrent connections (~200) + messages/วินาที | client เปิดได้ <= 2 channel ต่อ user (matches + chat ของ match ที่เปิดอยู่); ปิดเมื่อออกจากหน้า |
| **Client-side budget (บังคับใน repository layer)** | ต่อ user | ดูด้านล่าง |
| Edge Function `share-view` | 60 req/นาที/IP, 10 req/นาที/(IP+token prefix) ผ่าน in-memory/KV (Deno KV หรือ Upstash free) | ตอบ 429 + `Retry-After` + `X-RateLimit-Limit/Remaining/Reset` |
| **DB triggers ใน 0001 (มีแล้ว)** | `trip_locations`: 1 แถว/5 วิ/ทริป; `chat_messages`: <=10 ข้อความ/10 วิ/(match,sender); `trips` สร้าง <=10/24 ชม. (`GWM_TRIP_RATE_LIMIT`); แก้ geometry <=3/ทริป (`GWM_TRIP_EDIT_LIMIT`); `find_matches` clamp 50 แถว | `GWM_RATE_LIMITED` = 400 `P0001` retryable หลัง >=5 วิ (ไม่มี `Retry-After` header -> client ใช้ค่า default ต่อ code); **ไม่ throttle SOS โดยเจตนา** |
| Postgres (ข้อเสนอ 0002) | เพิ่ม `find_matches` <= 12/นาที/user, `request_match` <= 10/ชม./user (กัน probing) | ใช้ code `GWM_RATE_LIMITED` เดิม |

**Client budget**: `find_matches` ยิงเมื่อ (เปิดหน้า / pull-to-refresh / Realtime แจ้งทริปใหม่) และ throttle >= 10 วิ/ครั้ง; `get_partner_live_location` poll 15-30 วิ เฉพาะตอนหน้าจอ foreground และ match accepted + in_progress; `trip_locations` ทุก 15-30 วิ เฉพาะ in_progress (ตาม requirement); `app_config` cache 10 นาที.
รูปแบบ header เมื่อเราคุมเอง (Edge Function): `X-RateLimit-Limit/Remaining/Reset` + `Retry-After`. PostgREST/GoTrue ไม่คืน `X-RateLimit-*` ครบ -> client อ่านแค่ `Retry-After` ถ้ามี.

---

## 9. External service client contracts

หลักร่วม: ทุกบริการภายนอกเข้าผ่าน **interface ใน domain** (`GeocodingService`, `RoutingService`) + config-swappable base URL (ห้าม hardcode, สอดคล้อง NFR: เปลี่ยน endpoint ได้โดยไม่แก้ตรรกะ). ผลล้มเหลวต้องไม่ทำให้แอปค้าง (US-5 AC).

### 9.1 Config (อ่านจาก `--dart-define` / `.env`; มี default สาธารณะ)
```
NOMINATIM_BASE_URL   = https://nominatim.openstreetmap.org
OSRM_BASE_URL_FOOT   = https://routing.openstreetmap.de/routed-foot
OSRM_BASE_URL_CAR    = https://router.project-osrm.org          # public demo = driving เท่านั้น
OSRM_BASE_URL_BIKE   = (ไม่ใช้ใน MVP)
GEO_USER_AGENT       = GoWithMe/0.1 (contact: <email หรือ URL ของผู้พัฒนา>)   # จำเป็นตามนโยบาย Nominatim
GEO_CONTACT_EMAIL    = <optional, ใส่ใน &email= ถ้าไม่ตั้ง UA ได้>
GEO_TIMEOUT_MS / ROUTE_TIMEOUT_MS = 6000 / 8000
```
Mode -> profile: `walk`->foot (`OSRM_BASE_URL_FOOT`, path `/route/v1/foot/`), `car`,`taxi`,`transit`->car (`/route/v1/driving/`; transit = เส้นทางถนนโดยประมาณตาม requirements). ทุกค่ามาจาก `AppConfig`/DI — สลับไป self-host/Mapbox/Photon = แก้ config หรือ implement interface ใหม่.
หมายเหตุ: OSM tile server ก็มีนโยบาย (attribution, UA, ห้าม bulk) — ใช้ `flutter_map` + User-Agent package name + attribution "© OpenStreetMap contributors"; production ควรใช้ tile provider ของตน.

### 9.2 Nominatim
| รายการ | สัญญา |
|---|---|
| Search | `GET {base}/search?q={q}&format=jsonv2&limit=5&countrycodes=th&accept-language=th&addressdetails=0` |
| Reverse | `GET {base}/reverse?lat=&lon=&format=jsonv2&zoom=18&accept-language=th` |
| Headers | `User-Agent: GEO_USER_AGENT` (บังคับ), `Accept-Language: th` |
| Policy | <= 1 req/วินาที (รวมทั้งแอปต่อ client); **ห้าม autocomplete ต่อทุกตัวอักษร** -> ค้นหาเมื่อผู้ใช้หยุดพิมพ์ >= 800 ms และ q >= 3 ตัวอักษร (หรือกดปุ่มค้นหา); ยกเลิก request เก่าเมื่อพิมพ์ใหม่ |
| Throttle | token-bucket 1 req/s ใน `GeocodingClient` (serialize queue); 2 requests ห่างกัน >= 1100 ms |
| Cache | in-memory LRU 200 รายการ, key = `normalize(q)` (trim, lowercase, collapse space) ; TTL 24 ชม.; reverse key = พิกัดปัด 4 ตำแหน่ง (~11 ม.); cache ผล "ไม่พบ" 10 นาที; persist ลง disk ได้ (ไม่เก็บ PII เพิ่ม — เก็บเฉพาะ query สถานที่) |
| Timeout | connect 3s, total 6s |
| Retry | เฉพาะ network error/timeout/`502/503/504` : 1 ครั้ง หลัง 800ms + jitter. **`429`/`403`: ห้าม retry ทันที** -> เคารพ `Retry-After` (default 60 วิ) แล้วเข้า cooldown |
| Circuit breaker | 3 ความล้มเหลวติดกันใน 60 วิ -> open 60 วิ (fail-fast) -> half-open ลอง 1 request |
| Fallback (ลำดับ) | (1) ผลจาก cache (2) ปิดโหมดค้นหา แสดงข้อความ "บริการค้นหาที่อยู่ไม่พร้อม" + **ปักหมุดบนแผนที่เอง/ใช้ตำแหน่งปัจจุบัน** (US-5 AC: ปฏิเสธ location ก็สร้างได้) (3) reverse-geocode ล้ม -> label = พิกัดย่อ ("13.7455, 100.5345") ไม่บล็อกการบันทึกทริป |
| Errors -> AppFailure | 429/403 -> `RATE_LIMITED`; timeout -> `NETWORK_TIMEOUT`; 5xx -> `SERVER_UNAVAILABLE`; ว่าง -> `NOT_FOUND` (ผลลัพธ์ปกติ ไม่ใช่ error) |
| Privacy | q ที่ส่งไป Nominatim = ข้อความค้นหาของผู้ใช้ -> แจ้งใน privacy policy; ห้าม log query/พิกัด ใน production |

### 9.3 OSRM
| รายการ | สัญญา |
|---|---|
| Route | `GET {base}/route/v1/{profile}/{lng1},{lat1};{lng2},{lat2}?overview=full&geometries=geojson&steps=false&alternatives=false` (**lng ก่อน lat**) |
| Response ใช้ | `routes[0].distance` (m), `duration` (s), `geometry` (GeoJSON LineString) -> ตรงกับ `route_distance_m` (int), `route_duration_s` (int), `route` (EWKT LINESTRING) |
| Pre-validate | ระยะตรง start-dest < 200 ม. -> ไม่เรียก OSRM แสดง `GWM_TRIP_TOO_SHORT` ฝั่ง client |
| Timeout | total 8s |
| Retry | network/timeout/`5xx`: 1 ครั้ง (700ms + jitter); `429`: ตาม `Retry-After` ไม่ retry ทันที; `code != "Ok"` (`NoRoute`, `NoSegment`, `InvalidQuery`) = **ไม่ retry** -> `ROUTE_NOT_FOUND` (US-5: ไม่บันทึกทริป) |
| Cache | key = (profile, พิกัดต้น/ปลายปัด 4 ตำแหน่ง); LRU 50, TTL 30 นาที (กัน user แก้ไข form ซ้ำ ๆ) |
| Payload size | ก่อนส่งเข้า DB: `simplify` (Douglas-Peucker ~ 10 ม.) จำกัด <= 500 จุด (ลดขนาดแถว + ลดต้นทุน ST_Buffer ใน overlap; design-db §9) |
| Circuit breaker | เช่นเดียวกับ Nominatim (3 ล้ม/60 วิ -> open 60 วิ) แยกต่อ base URL |
| Fallback (ลำดับ) | (1) cache (2) **สลับ base URL สำรอง** ถ้ากำหนด `OSRM_BASE_URL_*_FALLBACK` (3) โหมด degrade: เส้นตรงต้น-ปลายทาง + ระยะ haversine * 1.3 และเวลาประมาณจากความเร็วเฉลี่ยของ mode (walk 4.5 กม./ชม., car/taxi 30, transit 20) พร้อมธง `route_source='estimated'` (ต้องแสดง UI ว่า "เส้นทางโดยประมาณ" — **ไม่บันทึกเป็นเส้นทางจริง** ถ้าไม่ผ่าน overlap; แนะนำ: บล็อกการสร้างทริป + ให้ลองใหม่ เพราะเส้นตรงทำให้คะแนน overlap ผิด) (4) แสดงข้อความ + ปุ่มลองใหม่ |
| **Decision** | MVP เลือก (4): ล้มเหลว = ไม่ให้สร้างทริป (fail-closed) เพราะ overlap ต้องอาศัยเส้นทางจริง; (3) เป็นแค่ preview บนแผนที่ |
| Foot profile caveat | public demo `router.project-osrm.org` รองรับเฉพาะ driving -> walk ต้องใช้ host foot แยก (ค่า default ด้านบน) หรือ self-host; ระบุใน README |

### 9.4 Interface (Dart hint)
```dart
abstract interface class GeocodingService {
  Future<List<PlaceSuggestion>> search(String query, {CancelToken? cancel}); // throws AppFailure
  Future<PlaceLabel> reverse(LatLng p);
}
abstract interface class RoutingService {
  Future<RouteResult> route({required TravelMode mode, required LatLng from, required LatLng to});
  // RouteResult { List<LatLng> geometry; int distanceM; int durationS; }
}
// impl: NominatimGeocoding(http.Client, RateLimiter(1/s), LruCache, CircuitBreaker, AppConfig)
//       OsrmRouting(...same...). ทดสอบด้วย fake HttpClient + fake clock (ไม่ยิง public จริงใน CI).
```

---

## 10. Realtime & polling contract
| Channel | Event | Filter | Consumer | หมายเหตุ |
|---|---|---|---|---|
| `chat:{match_id}` | INSERT `chat_messages` | `match_id=eq.{id}` | หน้าแชท | RLS กรองตาม participant; หลัง reconnect ต้อง backfill `created_at > lastSeen` ผ่าน REST (Realtime ไม่ replay) |
| `matches:me` | INSERT/UPDATE `matches` | `target_id=eq.{me}` และอีก sub `requester_id=eq.{me}` | inbox/สถานะคำขอ | ปลดล็อกการ์ด "ได้รับคำขอ" |
| polling | `get_partner_live_location` | 15-30 วิ | หน้าติดตามคู่ | ไม่ publish `trips`/`trip_locations` (กันรั่วพิกัด) |
| polling | `find_matches` | manual/throttle 10 วิ | หน้ารายการ | Realtime ทริปใหม่ = P1 (ไม่มี publication); US-6 ยอม manual refresh |
Payload ของ Realtime = แถวเต็มตาม RLS (`chat_messages` ทุกคอลัมน์) — ไม่มีข้อมูลอ่อนไหวเกินที่ participant ควรเห็น.

---

## 11. Design Decisions (Step 6)

| Decision | Tradeoff | Rationale |
|---|---|---|
| ใช้ PostgREST CRUD สำหรับ resource ธรรมดา + RPC สำหรับ logic ที่ต้อง privacy/eligibility/race | RPC = RMM Level 1, ไม่ cache-friendly | ไม่ต้องเขียน/ดูแล API server เอง (free tier); privacy บังคับที่ DB |
| `POST` ทุก RPC แม้ read-only (`find_matches`) | GET/HTTP cache ใช้ไม่ได้ | พารามิเตอร์ไม่ติด URL/log; ผลขึ้นกับ JWT อยู่แล้ว (ห้าม cache ร่วม) |
| Versioning = additive-only + `*_v2` ชื่อใหม่ | function เก่าค้างนาน | PostgREST ไม่มี path version ต่อ resource; client mobile อัปเดตช้า ต้อง back-compat |
| Error: ใช้ `GWM_*` ใน `message` (400/403) แทน HTTP status ละเอียด; envelope กลางสร้างที่ `ErrorMapper` ฝั่ง client | ขึ้นกับ string message ของ Postgres exception | แก้ PostgREST ไม่ได้; code เสถียรกว่า status; i18n ที่ client |
| Idempotency = client-generated key เป็น PK/unique (`client_msg_id`, `sos_events.id`) แทน `Idempotency-Key` header | ต้องเพิ่ม grant `id` (0002) | PostgREST ไม่มี header support; DB constraint เป็นตัวตัดสินที่เชื่อถือได้สุด |
| SOS: insert ตรง + offline queue, ไม่ rate limit, ไม่พึ่ง Edge Function | ไม่มีการแจ้งอัตโนมัติจากเซิร์ฟเวอร์ | MVP out-of-scope; ความปลอดภัยผู้ใช้ไม่ควรพึ่ง network (โทร+share sheet ก่อน) |
| `get_shared_trip` ตรงจาก anon RPC (P0) + Edge Function `share-view` (P1 web) | เพิ่มชิ้นส่วนใน P1 | token 244-bit + hash พอสำหรับ brute force; Edge Function เพิ่ม rate limit/404 สม่ำเสมอ/HTML |
| Rate limit หลัก = client budget + Supabase built-in; DB counter เป็น 0002 | ผู้โจมตีตรง (curl) ข้าม client ได้ | ต้นทุนต่ำสุดบน free tier; ระดับ hardening ค่อยเพิ่ม |
| Nominatim/OSRM: interface + base URL config + breaker + cache; routing ล้ม = fail-closed | ผู้ใช้สร้างทริปไม่ได้ตอน OSRM ล่ม | overlap ต้องเส้นทางจริง; ผลผิดร้ายกว่าไม่ทำ |
| Pagination: keyset สำหรับ chat; limit-only ที่เหลือ | ไม่มี total count | ข้อมูลโตต่อเนื่องแบบ append-only; ที่เหลือถูกจำกัดโดย business rule |
| Repository คืน `Result<T,AppFailure>` ห่อ `Page<T>` | ชั้น mapping เพิ่ม | ไม่ให้ `PostgrestException` รั่วเข้า domain/presentation |

---

## 12. Repository-interface mapping (Dart, clean architecture)

โครง: `lib/features/<feature>/{domain/{entities,repositories},data/{datasources,repositories_impl,dto},presentation}`. Interface อยู่ใน domain; impl ใน data ใช้ `SupabaseClient` (inject). ทุกเมธอด `Future<Result<T, AppFailure>>`. State: Riverpod/Bloc ตามที่ทีมเลือก (ไม่กำหนดที่นี่).

| Feature (US) | Repository interface | เมธอด -> Supabase call | Notes |
|---|---|---|---|
| auth (US-2,3) | `AuthRepository` | `signUp(email,pw,displayName,policyVersion)` -> `auth.signUp(data:{display_name,adult_confirmed:true,policy_version})`; `signIn`; `signOut`; `sendPasswordReset`; `Stream<Session?> authChanges` | map GoTrue codes (6.2); ไม่ log pw/email |
| profile (US-4,14) | `ProfileRepository` | `getMe()` `from('profiles').select().eq('id',uid).single()`; `updateProfile(...)` PATCH; `uploadAvatar(bytes)` storage `avatars/{uid}/avatar.jpg`; `avatarUrl(path)` signed URL | column ที่แก้ได้ตาม grant |
| verification (US-4) | `VerificationRepository` | `getBadges()` `from('verifications')`; `verifyPhoneMock(phone,code)` rpc; `orgDomains()` | จุดสลับ SMS จริง = interface เดียวกัน (`PhoneVerifier`) |
| consent/PDPA (US-15) | `PrivacyRepository` | `recordConsent(kind,granted,version)` rpc; `latestConsents()`; `exportMyData()` rpc; `requestAccountDeletion()` rpc | หลังลบ: signOut + clear storage |
| emergency (US-14) | `EmergencyContactRepository` | CRUD `emergency_contacts` (สูงสุด 3 -> `GWM_EMERGENCY_CONTACT_LIMIT`) | offline cache local ให้ SOS อ่านได้โดยไม่มีเน็ต |
| trip (US-5,9,12) | `TripRepository` | `createTrip(TripDraft)` insert (EWKT lng-first); `myTrips({status, cursor})`; `startTrip/completeTrip/cancelTrip(id)` PATCH + guard; `updateTrip(...)` ; `deleteTrip(id)` soft | `TripStateMachine` (domain, pure, มี unit test) สะท้อน trigger |
| routing/geocode (US-5) | `RoutingService`, `GeocodingService` | หัวข้อ 9 | ไม่ผ่าน Supabase |
| live location (US-12, NFR) | `LocationTrackingRepository` | `pushLocations(tripId, List<Fix>)` batch insert; `partnerLocation(matchId)` rpc (poll) | รับผิดชอบ throttle 15-30 วิ + consent gate |
| matching (US-6) | `MatchFinderRepository` | `findMatches(tripId, {limit<=50})` rpc -> `List<MatchCandidate>`; `tripCard(tripId)` rpc | dto ใช้ `approx_*`; ห้ามมี field พิกัดจริง |
| match requests (US-7) | `MatchRepository` | `request(myTrip,target)` rpc (+verify-then-success 7.2); `respond(matchId,accept,{meeting})`; `setMeetingPoint`; `cancel`; `inbox({cursor})`; `Stream<MatchEvent> watch()` (Realtime) | in-flight guard + refetch on `GWM_MATCH_NOT_FOUND` |
| chat (US-8) | `ChatRepository` | `history(matchId,{cursor,limit=30})`; `send(matchId, body, clientMsgId)` (idempotent 7.4); `Stream<ChatMessage> watch(matchId)` (Realtime + backfill); `isOpen(matchId)` (จาก match+trip status สำหรับ read-only UI) | optimistic + reconcile |
| safety: block/report (US-8,14) | `SafetyRepository` | `block(userId)`/`unblock`/`blocked()`; `report(userId,matchId?,reason,details)` | block ซ้ำ 23505 = สำเร็จ |
| SOS (US-10) | `SosRepository` | `trigger(SosEvent)` -> **enqueue local แล้ว flush**: insert `sos_events` (`id` client-gen, `on_conflict=id` ignore-duplicates); `pending()`; `flush()`; `history()` | ต้อง 0002; ตัวโทร 191/1669 + share sheet อยู่ใน presentation/platform ไม่ผ่าน repo |
| share (US-11) | `TripShareRepository` | `create(tripId, ttlMin)` -> `ShareLink(id, token, expiresAt)` (ห้าม persist token/log); `revoke(id)`; `active()`; `buildShareText(link, trip)`; (viewer) `SharedTripViewer.fetch(token)` -> rpc `get_shared_trip` / edge `share-view` | URL ที่ส่ง = `{SHARE_WEB_BASE_URL}/s/{token}` (config, P1) |
| app config | `AppConfigRepository` | `publicConfig()` cache 10 นาที (`match.*` เพื่อ UI แสดง threshold, `trip.*`, `emergency.max_contacts`, `phone.mock_enabled`) | client ไม่คำนวณ match เอง |

Test seams: fake `SupabaseClient` wrapper (interface `RemoteDataSource`) เพื่อ unit-test ErrorMapper/idempotent flow; integration ด้วย `supabase start` local + สคริปต์ RLS ใน design-db §6.

---

## 13. ช่องว่าง/ข้อเสนอสำหรับ migration 0002 (สรุป)
1. `sos_events`: เพิ่ม `id` ใน insert grant (client-generated), ยืนยัน `on_conflict=id`; guard `client_created_at` ให้อยู่ในช่วงสมเหตุผล. (**P0 safety**)
2. `trips`: เพิ่ม `id` ใน insert grant (idempotent create).
3. `request_match`: คืน id เดิมถ้า requester ซ้ำ (idempotent จริง).
4. (ทำแล้วใน 0001: clamp 50, trip/chat/location throttle) เหลือ: throttle `find_matches`/`request_match` ต่อ user.
6. `app_config`: `client.min_version`, `share.web_base_url` (public).
7. ตั้ง role settings: `statement_timeout` (authenticated), `db-max-rows`.
8. ตรวจ/ทดสอบ: PATCH trip status เท่าเดิมเป็น no-op หรือ error (7.3); RLS deny on chat ให้ client แยก "ปิดแล้ว" ได้จาก `is_chat_open` RPC (ข้อเสนอ: expose `chat_state(match_id)`).
9. (P1) Edge Function `share-view`; fallback cron Edge Function `purge-cron`.

## 14. Assumptions (แทนการถามกลับ)
- ใช้ Supabase hosted/local มาตรฐาน; PostgREST map `P0001->400`, `42501->403`, `23505->409` ตามค่า default ของ PostgREST (ต้องยืนยันด้วย integration test บน `supabase start` — migration ยังไม่เคยรันกับ Postgres จริงตาม design-db §9).
- ตัวเลข rate limit ของ Supabase (Auth/Realtime) เปลี่ยนตามแผน/เวลา — ตรวจใน dashboard ก่อน; ตัวเลขในเอกสารเป็นค่าตั้งต้นที่ปรับได้ไม่ใช่การรับประกัน.
- Public OSRM/Nominatim ไม่มี SLA; ตัวเลข timeout/breaker เป็นค่าเริ่มต้นเพื่อ MVP.
- ไม่มี admin API ใน MVP; ไม่มี Idempotency-Key header (ใช้ PK/unique แทน).
- ข้อความ UI/i18n ทั้งหมดอยู่ใน ARB (ภาษาไทยเป็น default) ไม่อยู่ใน contract นี้.

## Quality Gate
- [x] HTTP verb ตรงความหมาย (ไม่มี GET side effect ธุรกิจ; ไม่มี PUT ไม่ idempotent) — ข้อยกเว้นระบุแล้ว (V7/V8, RPC=POST)
- [x] Error envelope เดียว (canonical ที่ ErrorMapper) + machine-readable `code` ทุกกรณี
- [x] ทุก list มี pagination/limit (keyset สำหรับ chat, limit-only ที่เหลือ; ห้าม unbounded)
- [x] write ที่กระทบ state สำคัญมี idempotency (SOS, chat, request_match, trips — รวมข้อเสนอ 0002 ที่ต้องทำ)
- [x] ทุก endpoint ระบุ auth/role/ownership (ตาราง 3, 5)
- [x] Version ระบุตั้งแต่แรก (`/rest/v1`, `/functions/v1`, additive-only + `_v2`)
