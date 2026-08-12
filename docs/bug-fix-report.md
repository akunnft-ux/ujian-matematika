# Bug Fix Report — ujian-matematika

Tanggal: 2026-08-12 · Scope: guru.html, index.html, admin.html, supabase/schema.sql, js/api.js

## Ringkasan

| # | Severity | Bug | File | Status |
|---|----------|-----|------|--------|
| 1 | High | Form simpan soal manual crash `null.value` (field `mTopik` hilang saat migrasi) | guru.html | Fixed |
| 2 | High | Jawaban pasca-resume tidak terkirim (lock `terkirim` stale) | index.html | Fixed |
| 3 | Medium | Timer tidak menampilkan/update waktu saat resume dari sisa 0 | index.html | Fixed |
| 4 | Medium | Loop kirim-ulang submit saat offline/waktu habis | index.html | Fixed |
| 5 | High | Timer dipakai untuk semua ujian meski `durasiMenit` berubah | index.html | Fixed |

## 1. Crash simpan soal manual (guru.html)

**Triage:** Saat migrasi `kelas`→`jenjang`, input `mTopik` dihapus dari HTML tetapi `simpanSoalManual` masih membaca `document.getElementById("mTopik").value` → `null.value` crash. `btnResetForm` juga kehilangan listener (handler `onclick` global dihapus).

**Fix:**
- Kembalikan field `mTopik` ke grid form (Kode/Mapel/Topik/Jenjang).
- Tambah `addEventListener` untuk `btnResetForm`.

## 2. Lock terkirim stale (index.html)

**Triage:** `state.terkirim[s.id]=true` di-set sekali. Setelah admin reset login dan siswa lanjut (resume), jawaban lama di-merge ke `state.jawaban` tapi lock tetap `true` → koreksi jawaban tidak dikirim ulang; server menilai jawaban lama.

**Fix:** `state.terkirim[s.id]` kini menyimpan **label** jawaban yang sudah terkirim. Kirim ulang hanya saat label berubah. Resume mengisi `terkirim` dari jawaban lama (tidak boros kirim ulang nilai yang sama).

## 3. Timer display tidak diinisialisasi (index.html)

**Fix:** `startTimer` langsung meng-set `textContent` dan class danger sebelum interval berjalan, sehingga tampilan konsisten meski dimulai dari sisa 0.

## 4. Loop submit saat offline (index.html)

**Fix:** Di `catch` `submitUjian`, timer hanya di-restart bila `waktuSisa > 0`, mencegah restart-percobaan-ulang yang tidak pernah selesai.

## 5. Timer mengabaikan durasi ujian (index.html)

**Fix:** Hitung batas waktu dari `sisaDetik` yang dikirim server saat mulai/resume, bukan hardcoded per-ujian.

## Verifikasi

- `node --check` semua inline script + `js/*.js`: **lulus**.
- Harness Node (mock backend, `verify_fixes.cjs`): **10/10 pass** — kode ujian duplikat ditolak, submit kedua ditolak (oracle), resume mengembalikan jawabanLama+sisaDetik, login ganda ditolak, reset setelah SELESAI ditolak.

## Catatan

Perubahan security (bind sesi, guard ACTIVE, hapus pass_hash, XSS escape, event delegation) tercatat terpisah di laporan security. Semua edit minimal-risk; tidak ada refactor.
