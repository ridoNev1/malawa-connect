# Discounts (Org 5)

Status
- Implemented in DB and wired in FE (Home carousel).

Schema
- Tabel `public.discounts` sudah ada; ditambah kolom opsional (idempotent):
  - `image` text (opsional; URL gambar)
  - `valid_until` date (opsional)

RPC
- `get_discounts_org5(p_only_active boolean = true, p_limit int = 20)` → TABLE
  - Filter `organization_id = 5`
  - Jika `p_only_active = true`, hanya `is_active = true`
  - Urut: `COALESCE(valid_until, created_at::date)` desc, lalu `created_at` desc
  - Fields: `id, name, description, type, value, is_active, created_at, unique_code, organization_id, image, valid_until`

FE Integration
- Provider: `lib/features/home/providers/home_providers.dart` → `discountsProvider`
- API helper: `lib/core/services/supabase_api.dart` → `getDiscountsOrg5(...)`
- UI: `lib/features/home/presentation/home_page.dart`
  - Fallback label jika `valid_until` null tetap tersedia di UI

Contoh FE (Dart)
```dart
final list = await SupabaseApi.getDiscountsOrg5(onlyActive: true, limit: 20);
```

Catatan
- Tidak membutuhkan `active_organization_id` di JWT; RPC membatasi org=5.
- Bila Anda ingin, kita bisa tambahkan parameter pencarian atau pagination di RPC.
