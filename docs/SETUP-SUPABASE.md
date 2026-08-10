# Setup Backend Supabase

Backend nyata: **PostgreSQL** yang dikelola Supabase. Semua akses data lewat
**RPC function** (bukan akses tabel langsung), sehingga RLS aktif dan frontend
tetap memakai `AppAPI.call(action, payload)` yang sama seperti mode demo.

## 1. Buat project Supabase (gratis)

1. Daftar ke <https://supabase.com> → **New project**.
2. Paket **Free** cukup (500 MB database, 50K MAU, API unlimited).
   > Catatan: project Free **pause otomatis setelah 7 hari tanpa aktivitas**.
   > Untuk ujian berkala, project akan terbangun lagi saat dipakai (butuh 20-30 dtk),
   > atau buka dashboard sekali seminggu agar tetap aktif.
3. Catat dari **Project Settings → API**:
   - **Project URL** (contoh: `https://abcdefgh.supabase.co`)
   - **anon / public key** (contoh: `eyJhbGciOi...`)

## 2. Jalankan SQL

1. Buka **SQL Editor** di dashboard Supabase.
2. Tempel isi `supabase/schema.sql` → **Run**. (Membuat tabel, RLS, dan semua RPC.)
3. Tempel isi `supabase/seed.sql` → **Run**. (Data demo: `admin`/`admin`, `guru`/`guru`,
   siswa `budi`/`budi123` & `siti`/`siti123`, ujian `EXM-2026-001` token `TKN-DEMO`.)
4. Sudah selesai — tidak perlu membuat tabel manual.

## 3. Isi konfigurasi frontend

Edit `js/config.js`:

```js
BACKEND: "supabase",
SUPABASE_URL: "https://abcdefgh.supabase.co",
SUPABASE_ANON_KEY: "eyJhbGciOi...",
```

`BACKEND: "mock"` mengembalikan ke mode demo localStorage (tanpa backend).

## 4. Cara pakai (sama seperti demo)

| Halaman | Login | Peran |
|---|---|---|
| `index.html` | `budi` / `budi123` + kode `EXM-2026-001` + token `TKN-DEMO` | Siswa |
| `guru.html` | `guru` / `guru` | Kelola soal, upload siswa, buat ujian |
| `admin.html` | `admin` / `admin` | Aktifkan ujian + token, reset login, tambah guru |

> **Penting:** semua perangkat (siswa & guru/admin) kini berbagi **satu database
> yang sama** — tidak seperti mode demo yang per-browser. Siswa bisa login dari
> HP apa pun lewat `python3 -m http.server 8000` atau hosting lain.

## Alur ujian

1. `guru.html` → upload data siswa `.xlsx` (username/password otomatis dibuat, password di-hash SHA-256).
2. `guru.html` → buat ujian dari bank soal → status `draft`.
3. `admin.html` → tab **Ujian** → **Aktifkan & Generate Token** → status `aktif`, satu token untuk semua siswa.
4. Siswa login di `index.html` (username + password + kode ujian) → masukkan token → ujian berjalan.
5. Jawaban tersimpan per soal (queue + retry tetap aktif), nilai dihitung **server-side** di Postgres saat submit.

## Arsitektur ringkas

```
index/guru/admin.html (vanilla JS)
        │  AppAPI.call(action, payload)        ← js/api.js
        ▼
POST https://<project>.supabase.co/rest/v1/rpc/<rpc_xxx>
        │  anon key + session_id
        ▼
PostgreSQL (supabase/)
  ├── tabel : users, soal_bank, ujian, kode_ujian, sesi, sessions, jawaban, hasil
  ├── RLS   : anon/authenticated TIDAK bisa akses tabel langsung
  └── RPC   : security definer, otorisasi dicek per-peran di dalam function
```

## Keamanan

- Password guru/admin & siswa di-hash **SHA-256** (`pgcrypto`) — bukan plaintext.
- Kunci jawaban & pembahasan hanya dikembalikan ke sesi `guru`/`admin`.
- Token ujian hanya dikembalikan ke sesi `guru`/`admin` (siswa menerima token dari pengawas).
- Scoring murni server-side: kunci tidak pernah dikirim ke browser siswa.
- Anti login-ganda: `mulai-ujian` menolak akun yang `ACTIVE`/`SELESAI`; admin bisa reset.
- Akses tabel langsung diblokir RLS + `REVOKE` — satu-satunya pintu masuk adalah RPC.

## Batas paket Free yang perlu diwaspadai

- **Auto-pause** setelah 7 hari tidak aktif (buka dashboard seminggu sekali jika jarang dipakai).
- **500 MB database** — sangat longgar untuk teks soal/jawaban (jutaan baris pendek).
- **5 GB egress/bulan** — muat untuk ratusan siswa per bulan.
- Tidak ada backup otomatis di Free → jangan hapus data penting tanpa backup manual.
