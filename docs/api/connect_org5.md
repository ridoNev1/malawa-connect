# Connect (Org 5)

Status
- Members list/detail terhubung ke Supabase. Lokasi anggota menggunakan presence aktif, fallback ke presence terakhir bila `customers.location_id` kosong.

RPC
- `get_members_org5(p_tab='nearest'|'network', p_status='Semua'|'Online'|'Friends'|'Partners', p_search='', p_page=1, p_page_size=10, p_base_location_id bigint?)` → JSONB
  - Mengembalikan `items` (array members) + pagination (`page`, `pageSize`, `total`, `hasMore`).
  - Dedup koneksi (koneksi terbaru per peer) dan satu baris per anggota pada hasil halaman.
  - Field penting pada item: `id (legacy)`, `member_id (uuid)`, `name`, `avatar`, `gender`, `isOnline` (presence TTL 120s), `lastSeen`, `location_name`, `connection_status`, `connection_type`, `interests`, `preference`.
  - Untuk tab `nearest`, jika `p_base_location_id` kosong, BE menggunakan `customers.location_id` current user; pengisian `location_name` anggota tetap memakai presence/latest presence.

- `get_member_detail_org5(p_id text)` → JSONB
  - `p_id` menerima `legacy id` atau `member_id (uuid string)`.
  - Mengembalikan: `id, member_id, name, avatar, gender, interests, preference, gallery_images, location_name, isOnline, lastSeen, connection_status, connection_type`.
  - `lastSeen` diambil dari presence aktif (heartbeat/check-in), fallback: last presence timestamp → `customers.last_visit_at`. Tidak mem-format epoch 1970.
  - `location_name` diturunkan dari presence aktif → last presence → `customers.location_id`.

Catatan
- FE melakukan deduplikasi tambahan pada client untuk berjaga jika ada data historis.
- Ikon gender di FE: male → `male_rounded` (biru), female → `female_rounded` (pink), unknown → `person_outline`.
- Avatar dot “in‑app active” (Realtime broadcast) hanya untuk avatar; indikator online lain mengikuti presence TTL.

