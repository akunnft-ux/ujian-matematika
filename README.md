# Ujian Matematika Online

WebApp ujian matematika (HTML + JS + CSS statis) dengan backend **Supabase (Postgres)**.
Multi-role: **Siswa**, **Guru**, **Admin**. Anti login-ganda, bank soal, upload .docx/.xlsx,
dan edit soal inline. (Backend lama Google Apps Script masih ada di `apps-script/` untuk referensi.)

## Cepat mulai (mode demo)

1. Buka `index.html` → login dengan username/password + kode ujian (demo: `budi`/`budi123` + kode `EXM-2026-001`), lalu masukkan token ujian dari admin (demo: `TKN-DEMO`). Data siswa juga bisa dibuat di `guru.html`.
2. Buka `guru.html` → login `guru` / `guru` → kelola bank soal, upload, buat ujian.
3. Buka `admin.html` → login `admin` / `admin` → monitor, **aktifkan ujian & generate token**, reset login, tambah guru.

Tanpa backend (mode demo), semua data tersimpan di **localStorage browser**. Untuk
backend nyata multi-perangkat: **Supabase** — lihat `docs/SETUP-SUPABASE.md`
(jalankan `supabase/schema.sql` + `supabase/seed.sql`, lalu isi `js/config.js`).

## Halaman

| File | Fungsi |
|---|---|
| `index.html` | Siswa: login username+password+kode → konfirmasi data + token → ujian → hasil |
| `guru.html` | Guru: bank soal, upload .docx/.xlsx, tambah/edit soal, buat ujian, lihat hasil |
| `admin.html` | Admin: monitor live, aktifkan ujian & generate token, reset login, tambah akun guru, lihat semua hasil |

## Struktur

```
ujian-matematika/
├── index.html / guru.html / admin.html
├── css/style.css
├── js/
│   ├── config.js        ← konfigurasi pusat + FEATURE FLAGS + backend (mock/supabase)
│   ├── api.js           ← abstraksi backend (mock/Supabase RPC) + queue retry
│   ├── auth.js          ← sesi lokal
│   ├── soal-render.js   ← render blok (teks/LaTeX/gambar) via KaTeX
│   ├── block-editor.js  ← editor blok reuse (tambah & edit soal)
│   ├── docx-parser.js   ← .docx → soal (OMML→LaTeX, JSZip)
│   └── xlsx-parser.js   ← .xlsx → data siswa (SheetJS)
├── supabase/
│   ├── schema.sql       ← tabel + RLS + RPC functions (jalankan di SQL Editor)
│   └── seed.sql         ← data demo
├── apps-script/Code.gs  ← backend lama Google Apps Script (referensi)
└── docs/                ← PRD, arsitektur, setup Supabase/GAS
```

## Alur ujian

1. Guru upload data siswa (`.xlsx`: Nama, Nomor, Username, Password) di `guru.html`.
2. Guru buat ujian dari bank soal (dengan **kode ujian**) — status masih `draft`.
3. Admin buka tab **Ujian** di `admin.html` → klik **Aktifkan** → status jadi `aktif` dan
   **satu token** (`TKN-XXXXXXXX`) dibuat untuk ujian itu (dipakai semua siswa).
4. Siswa login di `index.html` (username + password + kode ujian), verifikasi data, masukkan
   token, lalu mulai ujian. Login/mulai ditolak selama ujian belum aktif.

## Cara menambah / mengurangi fitur

Semua fitur dikendalikan di `js/config.js` → `FEATURES`. Set `false` untuk menyembunyikan fitur;
tambah fitur baru sebagai modul di `js/` lalu daftarkan aksinya di `js/api.js` (frontend)
dan `apps-script/Code.gs` `route_()` (backend).

## Format soal (.docx)

Soal bernomor (`1.`, `2.`, ...), opsi `A.`–`E.`, dan bagian **KUNCI JAWABAN** di akhir.
Baris `KODE SOAL` dan `JENJANG` (SD/SMP/SMA/SMK) di awal dokumen menjadi identitas satu paket:
```
KODE SOAL: M-2026-001
JENJANG: SMA

1. Hitunglah ...
A. ...
B. ...
C. ...
...
KUNCI JAWABAN:
1. C
```
Persamaan native Word (`Alt+=`) dikonversi otomatis OMML→LaTeX. Gambar disimpan, persamaan
yang gagal dikonversi ditandai placeholder — guru perbaiki via edit soal di bank soal.
