# Arsitektur & PRD Ringkas

## Jenis & Stack

| | |
|---|---|
| Tipe | Web application (web app statis + backend GAS) |
| Frontend | HTML + CSS + JS murni (tanpa build step, tanpa framework) |
| Backend | Google Apps Script Web App (`apps-script/Code.gs`) |
| Data store | Google Sheets (9 tab) |
| Rendering matematika | KaTeX (CDN) |
| Parsing .docx | JSZip + (opsional omml2mathml/mathml-to-latex) |
| Parsing .xlsx | SheetJS |

## Fase & Skill

Proyek dijalankan mengikuti alur skill `tech-lead-orchestrator`:
Discovery (`ai-product-owner`) → PRD (`prd-architect-pro`) → Arsitektur (`project-architect-pro`)
→ Database (`database-architect-pro`) → UI (`ui-designer-pro`) → Implementasi
(`fullstack-engineer-pro`) → Code Review → QA → Security → Deployment.

Referensi UI memakai pola dari memory `uiux-exam-cat-app.md` (state machine setup/exam/result,
KaTeX MathText, timer, navigasi soal).

## Keputusan arsitektur kunci

1. **Modular frontend**: tiap tanggung jawab satu file JS (config/api/auth/render/editor/parser).
   Feature flags di `js/config.js` → mudah menambah/mengurangi fitur.
2. **Abstraksi backend**: semua komunikasi lewat `AppAPI.call(action, payload)`.
   Mode demo (localStorage) ↔ backend nyata (GAS) di-swap hanya via `API_ENDPOINT` + `MOCK_MODE`.
3. **Queue + retry**: jawaban siswa masuk antrean `localStorage` → dikirim berurutan,
   tidak hilang saat offline.
4. **Soal berbasis blok**: `{type: text|latex|image, value}` → renderer tunggal
   (`soal-render.js`) untuk siswa, bank soal, dan editor. Parser .docx menghasilkan format yang sama.
5. **Anti login-ganda**: status sesi di tab `Sesi` (server-side), dibuat saat `mulai-ujian`
   (bukan saat login). Reload perangkat sama aman (sessionId di localStorage); perangkat lain
   ditolak sampai admin reset. Siswa yang sudah `SELESAI` tidak bisa mulai lagi.
6. **Scoring server-side**: kunci jawaban hanya di `SoalBank` sheet; frontend tidak pernah
   menerima kunci. Nilai dihitung saat submit.
7. **Nilai di akhir**: tanpa feedback per soal → hemat request, siswa tidak dapat petunjuk.

## Tab Google Sheets

| Tab | Kolom |
|---|---|
| Users | username, passHash, role, aktif |
| SoalBank | id, mapel, jenjang, topik, kode, blocksJson, opsiJson, kunci, pembahasan, status, uploader, created |
| Ujian | id, nama, kode, mapel, jenjang, durasiMenit, soalIdsJson, status, token, created |
| SoalUjian | ujianId, soalId, urutan |
| KodeUjian | username, password, nis, nama, kelas, ujianId, status |
| Sesi | username, nis, status, login_ts, fingerprint |
| Jawaban | username, nis, soalId, jawaban, ts |
| Hasil | username, nis, nama, benar, total, nilai, ts |
| Config | key, value |

## Endpoint API (action)

`login-siswa` · `mulai-ujian` · `login-admin` · `bank-soal` · `simpan-soal` · `hapus-soal` ·
`upload-siswa` · `get-ujian` · `buat-ujian` · `aktifkan-ujian` · `jawaban` · `submit-ujian` ·
`get-hasil` · `reset-login` · `get-progress` · `get-users` · `tambah-user`

## Alur autentikasi siswa & token ujian

1. Guru upload data siswa (`upload-siswa`) → akun **username + password** (bukan token).
2. Guru buat ujian (`buat-ujian`) → status `draft`, token kosong.
3. Admin aktifkan ujian (`aktifkan-ujian`) → status `aktif` + **1 token per ujian**
   (`TKN-XXXXXXXX`) untuk semua siswa.
4. Siswa `login-siswa` dengan **username + password + kode ujian**. Login hanya mengecek
   kode valid + ujian `aktif`; siswa TIDAK ditautkan ke ujian. Belum `aktif` → ditolak.
5. Siswa melihat konfirmasi data di layar `#screen-confirm`, lalu memasukkan token.
6. `mulai-ujian` memvalidasi token (`Ujian.token`), cek status `aktif`/`SELESAI`, baru membuat
   sesi `ACTIVE` (anti login-ganda) dan mengembalikan sessionId.

## Model data soal (blok)

```json
{
  "id": "S-xxx",
  "mapel": "Matematika",
  "jenjang": "SMA",
  "topik": "Kalkulus",
  "blocks": [
    { "type": "text",  "value": "Diketahui fungsi " },
    { "type": "latex", "value": "f(x)=x^2+2x" },
    { "type": "image", "value": "https://.../rumus.png" }
  ],
  "opsi": ["$5$", "$8$", "$9$"],
  "kunci": "A",
  "status": "draft"
}
```

## Roadmap / evolusi

- Phase 1 (sekarang): ujian + bank soal + upload + edit + admin + anti login-ganda.
- Phase 2 (opsional): feedback per soal, ekspor hasil CSV, gambar via Drive, rate-limit login,
  session expiry, hash password + salt, multiple jenis soal (isian singkat, benar/salah).
