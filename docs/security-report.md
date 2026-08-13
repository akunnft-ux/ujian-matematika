# Security Audit Report — ujian-matematika

Tanggal: 2026-08-12 · Scope: supabase/schema.sql (RPC), guru.html, admin.html, index.html

## Severity Summary

| Severity | Count |
|----------|-------|
| High | 3 |
| Medium | 3 |
| Low | 1 |

## Temuan

### HIGH-1 — Username spoofing via RPC (rpc_jawaban, rpc_submit_ujian)
RPC hanya memvalidasi `session_id` valid; username/nis pada payload tidak dicocokkan dengan pemilik sesi. Siswa bisa mengirim jawaban atau mengumpulkan atas nama siswa lain.

**Fix:** Kedua fungsi bind sesi: `select username into v from public.sessions where id = session_id`, lalu tolak bila `v is distinct from payload.username`.

### HIGH-2 — Repeat-submit oracle (rpc_submit_ujian)
Setelah submit pertama, sesi di-set SELESAI tetapi tidak ada guard status → panggilan ulang dengan `jawaban_id` lama masih dinilai.

**Fix:** Untuk role `siswa`, tolak bila `not exists (select 1 from public.sesi where username=... and status='ACTIVE')`. Paralel di mock (`mockSubmitUjian`) agar perilaku demo konsisten.

### HIGH-3 — Credential hash bocor + duplicate kode ujian (rpc_get_users, rpc_buat_ujian)
- `rpc_get_users` mengembalikan `pass_hash` (SHA-256 tanpa salt).
- `rpc_buat_ujian` tidak cek duplikat kode → kode ujian ganda bisa dibuat.

**Fix:** Hapus `pass_hash` dari output `rpc_get_users`; tambah `if exists(...kode)` di `rpc_buat_ujian` (paralel di `mockBuatUjian`).

### MED-1 — Stored XSS (innerHTML tanpa escape)
Banyak `innerHTML` memakai data user (username, nama, kode, token, hasil, kelas, jenjang, topik) tanpa escape → stored XSS lintas pengguna.

**Fix:** Helper `esc()` ditambahkan di guru.html, admin.html, index.html dan diterapkan konsisten di semua titik render user data. Tombol aksi (`reset`, `aktifkan`, `selesai`, `hapus-user`) dipindah dari `onclick` inline ke **event delegation** dengan `data-*` — mencegah injection dan isu double-unescape di atribut.

### MED-2 — Status sesi tidak divalidasi (sesi_login)
`status` bertipe text bebas (bisa diubah via UPDATE menjadi string apa pun).

**Fix:** Tambah `check (status in ('INACTIVE','ACTIVE','SELESAI'))` pada tabel `sesi`.

### MED-3 — Autentikasi lemah (di luar perubahan)
- `sessions` stateless, tanpa expiry. Rekomendasi masa depan: sertakan `expires_at` dan perbarui saat menulis data penting.
- Password di-hash SHA-256 tanpa salt. Jika menyimpan `users.pass_hash` dibutuhkan lagi, migrasi ke `crypt` (bcrypt) + salt.
- Tidak ada rate-limit pada login. Rekomendasi: throttle per-IP/per-username.

## Remaining Known Issues (non-blocking)
- Alert/confirm menggunakan dialog browser (bukan risk) — tidak diubah.

## Deployment Note
Perubahan `supabase/schema.sql` WAJIB di-re-run di Supabase SQL Editor (create-or-replace fungsi + constraint baru `sesi_status_check`). Tanpa re-run, fix backend tidak aktif meski frontend sudah di-deploy.
