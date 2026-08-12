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

## 6. Kunci jawaban tidak terbaca dari .docx (auto-numbering / tabel / header satu-baris)

**Triage:** Template `25_Soal_TKA_Bahasa_Indonesia_SD_MI_Literasi.docx` memakai **auto-numbering Word** di bagian KUNCI JAWABAN (`w:numPr`): angka "1., 2., …" tampil di Word tapi tidak tersimpan di teks XML — `w:t` hanya berisi huruf `C`, `B`, dst. Regex kunci lama `/(\d{1,3})\s*[.)]?\s*([A-Ea-e])/` membutuhkan nomor → semua kunci terlewat → `kunci: ""`.

**Fix (docx-parser.js `splitQuestions`):**
- Header regex kini menangkap sisa isi baris → format `KUNCI JAWABAN: 1.A 2.B 3.C` juga didukung (regex global, semua jawaban per baris).
- **Fallback positional**: baris kunci berupa huruf tunggal `^([A-Ea-e])$` (tanpa nomor) dipetakan berurutan ke soal urutan dokumen yang belum punya kunci → menangani auto-numbering Word dan tabel 2 kolom "No | Kunci".
- `splitQuestions` di-export untuk unit test.

**Verifikasi:** 10/10 pass — file asli (25 soal, kunci urut benar), regresi template `1. B` (2 soal), header satu-baris, tabel 2 kolom, dan campuran format.

## 7. "Upload berhasil tapi Bank Soal kosong" — race simpan → reload

**Triage:** Parse `.docx` menghasilkan 25 soal valid (blocks/opsi/kunci lengkap — terbukti via harness). `rpc_simpan_soal` hanya menolak blocks kosong; `rpc_bank_soal` mengembalikan soal draft juga; tabel `soal_bank` tanpa constraint penolak. Root cause: `prosesDocx` memicu 25 `simpan-soal` async (tidak di-await) lalu **langsung** `muatBankSoal()` → di backend supabase, fetch `bank-soal` selesai sebelum insert → "0 soal". `.catch(function(){})` menelan semua error sehingga kegagalan tidak terlihat.

**Fix:**
- `guru.html prosesDocx`: kumpulkan semua promise simpan → `Promise.all` → baru `muatBankSoal()`. Hasil per-soal diubah jadi `true`/pesan error, jumlah gagal + contoh error ditampilkan (bukan disapu bersih).
- `js/api.js mockSimpanSoal`: id `Date.now().toString(36)` bertabrakan saat banyak simpan di-fire sinkron → tambah suffix random (paritas mock).

**Verifikasi:** simulasi timing membuktikan race (bank 0 sebelum await → penuh setelah). End-to-end mock: 4/4 (25 soal tersimpan, kunci & jenjang benar). Regresi: parser kunci 10/10, mock fixes 10/10. `node --check` semua lulus.

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
