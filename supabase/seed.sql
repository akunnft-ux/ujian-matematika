-- ============================================================
-- supabase/seed.sql — Data demo (diulang aman: ON CONFLICT DO NOTHING)
-- Jalankan SETELAH schema.sql
-- ============================================================

-- Akun staf demo: admin/admin , guru/guru
insert into public.users (username, pass_hash, role, aktif)
values
  ('admin', encode(digest('admin', 'sha256'), 'hex'), 'admin', true),
  ('guru',  encode(digest('guru',  'sha256'), 'hex'), 'guru',  true)
on conflict (username) do nothing;

-- Bank soal contoh (2 soal)
insert into public.soal_bank (id, mapel, kelas, topik, kode, blocks, opsi, kunci, pembahasan, status, uploader)
values
  ('S-001', 'Matematika', 'XII IPA', 'Kalkulus', 'M-2026-001',
   '[{"type":"text","value":"Diketahui fungsi "},{"type":"latex","value":"f(x)=2x^3-9x^2+12x+5"},{"type":"text","value":". Nilai stasioner minimumnya adalah ..."}]'::jsonb,
   '["$5$","$8$","$9$","$10$","$14$"]'::jsonb,
   'C',
   'f''(x)=6x^2-18x+12, titik stasioner x=1 dan x=2; f(2)=9 minimum lokal.',
   'aktif', 'guru'),
  ('S-002', 'Matematika', 'XII IPA', 'Integral', 'M-2026-001',
   '[{"type":"text","value":"Nilai dari "},{"type":"latex","value":"\\int_{0}^{\\pi/2} \\sin^2(x)\\cos(x)\\,dx"},{"type":"text","value":" adalah ..."}]'::jsonb,
   '["$\\frac{1}{6}$","$\\frac{1}{4}$","$\\frac{1}{3}$","$\\frac{1}{2}$","$1$"]'::jsonb,
   'C',
   'Substitusi u = sin(x).',
   'aktif', 'guru')
on conflict (id) do nothing;

-- Ujian demo EXM-2026-001 (status aktif + token TKN-DEMO)
insert into public.ujian (id, nama, kode, mapel, kelas, durasi_menit, soal_ids, status, token)
values ('U-001', 'Ujian Matematika XII IPA', 'EXM-2026-001', 'Matematika', 'XII IPA', 60,
        '["S-001","S-002"]'::jsonb, 'aktif', 'TKN-DEMO')
on conflict (kode) do nothing;

-- Akun siswa demo: budi/budi123 , siti/siti123
insert into public.kode_ujian (username, pass_hash, nis, nama, kelas, ujian_id, status)
values
  ('budi', encode(digest('budi123', 'sha256'), 'hex'), '2026001', 'Budi Santoso', 'XII IPA 1', 'EXM-2026-001', 'belum'),
  ('siti', encode(digest('siti123', 'sha256'), 'hex'), '2026002', 'Siti Rahayu',   'XII IPA 1', 'EXM-2026-001', 'belum')
on conflict (username) do nothing;
