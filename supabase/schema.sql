-- ============================================================
-- supabase/schema.sql — Backend Supabase untuk Ujian Matematika
-- ------------------------------------------------------------
-- Semua akses data lewat RPC function (security definer).
-- Frontend TIDAK membaca/menulis tabel langsung (RLS + revoke).
--
-- Cara pakai:
--   1. Buat project Supabase (paket gratis/Spark sudah cukup)
--   2. SQL Editor -> tempel & RUN file ini
--   3. Lalu RUN supabase/seed.sql (data demo)
--   4. Salin Project URL + anon key -> js/config.js
--      (BACKEND: "supabase")
--
-- Detail: docs/SETUP-SUPABASE.md
-- ============================================================

create extension if not exists pgcrypto;

-- ============================================================
-- TABEL
-- ============================================================

-- Akun guru & admin
-- pass_plain = password teks biasa (agar admin bisa melihat password guru lewat UI).
-- Hanya diekspos lewat RPC rpc_get_users (khusus admin). Jangan direferensikan dari klien lain.
create table if not exists public.users (
  username   text primary key,
  pass_hash  text not null,
  pass_plain text not null default '',
  role       text not null check (role in ('admin','guru')),
  aktif      boolean not null default true
);

-- Migrasi untuk DB lama yang tabel users-nya sudah ada (create table if not exists
-- tidak menambah kolom). Wajib agar rpc_get_users tidak error "column does not exist".
alter table public.users add column if not exists pass_plain text not null default '';

-- Bank soal (blok teks/latex/gambar)
create table if not exists public.soal_bank (
  id         text primary key,
  mapel      text not null default '',
  jenjang    text not null default '',
  topik      text not null default '',
  kode       text not null default '',
  blocks     jsonb not null default '[]'::jsonb,
  opsi       jsonb not null default '[]'::jsonb,
  kunci      text not null default '',
  pembahasan text not null default '',
  status     text not null default 'draft',
  uploader   text not null default '',
  created    timestamptz not null default now()
);

-- Ujian (soalIds = array id dari soal_bank)
create table if not exists public.ujian (
  id           text primary key,
  nama         text not null,
  kode         text not null unique,
  mapel        text not null default '',
  jenjang      text not null default '',
  durasi_menit integer not null default 60,
  soal_ids     jsonb not null default '[]'::jsonb,
  status       text not null default 'draft',
  token        text not null default '',
  created      timestamptz not null default now()
);

-- Akun siswa (username/password, dari upload guru)
create table if not exists public.kode_ujian (
  username text primary key,
  pass_hash text not null,
  pass_plain text not null default '',
  nis       text not null default '',
  nama      text not null default '',
  kelas     text not null default '',
  ujian_id  text not null default '',
  status    text not null default 'belum'
);

-- Migrasi untuk DB lama yang tabel kode_ujian-nya sudah ada (create table if not exists
-- tidak menambah kolom). Wajib agar rpc_generate_kartu tidak error "column does not exist".
alter table public.kode_ujian add column if not exists pass_plain text not null default '';

-- Status sesi ujian siswa (anti login-ganda)
-- ujian_id = kode ujian sesi ini; guard ACTIVE/SELESAI bersifat per-ujian
-- sehingga siswa yang sudah selesai ujian A tetap bisa mulai ujian B (kode lain).
create table if not exists public.sesi (
  username    text primary key,
  nis         text not null default '',
  status      text not null default 'INACTIVE',
  login_ts    timestamptz not null default now(),
  fingerprint text not null default '',
  ujian_id    text not null default '',
  constraint sesi_status_check check (status in ('INACTIVE','ACTIVE','SELESAI'))
);

-- Token sesi login (siswa & staf) untuk otentikasi request
create table if not exists public.sessions (
  id         text primary key,
  username   text not null,
  role       text not null,
  created_at timestamptz not null default now()
);

-- Antrean permintaan reset login dari siswa (muncul di tab Reset Siswa admin)
create table if not exists public.reset_requests (
  username     text primary key,
  nis          text not null default '',
  nama         text not null default '',
  kelas        text not null default '',
  kode_ujian   text not null default '',
  requested_at timestamptz not null default now()
);

-- Jawaban per soal
create table if not exists public.jawaban (
  id       bigserial primary key,
  username text not null default '',
  nis      text not null default '',
  soal_id  text not null default '',
  jawaban  text not null default '',
  ts       timestamptz not null default now()
);

-- Hasil akhir ujian
create table if not exists public.hasil (
  id         bigserial primary key,
  username   text not null default '',
  nis        text not null default '',
  nama       text not null default '',
  kode_ujian text not null default '',
  kelas      text not null default '',
  benar      integer not null default 0,
  total      integer not null default 0,
  nilai      integer not null default 0,
  ts         timestamptz not null default now()
);

alter table public.hasil add column if not exists kode_ujian text not null default '';
alter table public.hasil add column if not exists kelas text not null default '';
alter table public.sesi add column if not exists mulai_ts timestamptz;
alter table public.sesi add column if not exists ujian_id text not null default '';
alter table public.soal_bank add column if not exists jenjang text not null default '';
alter table public.soal_bank drop column if exists kelas;
alter table public.ujian drop column if exists kelas;
alter table public.ujian add column if not exists jenjang text not null default '';

-- Dedup data lama sebelum index unik dibuat (keep baris terbaru per kunci)
delete from public.jawaban a using public.jawaban b
  where a.username = b.username and a.soal_id = b.soal_id and a.id < b.id;
delete from public.hasil a using public.hasil b
  where a.username = b.username and a.kode_ujian = b.kode_ujian
    and a.kode_ujian <> '' and a.id < b.id;

create unique index if not exists uq_jawaban_user_soal on public.jawaban (username, soal_id);
create unique index if not exists uq_hasil_user_kode on public.hasil (username, kode_ujian) where kode_ujian <> '';

-- ============================================================
-- RLS + REVOKE: anon/authenticated tidak boleh akses tabel
-- ============================================================
alter table public.users      enable row level security;
alter table public.soal_bank  enable row level security;
alter table public.ujian      enable row level security;
alter table public.kode_ujian enable row level security;
alter table public.sesi       enable row level security;
alter table public.sessions   enable row level security;
alter table public.reset_requests enable row level security;
alter table public.jawaban    enable row level security;
alter table public.hasil      enable row level security;

revoke all on public.users, public.soal_bank, public.ujian,
          public.kode_ujian, public.sesi, public.sessions,
          public.jawaban, public.hasil, public.reset_requests
  from anon, authenticated;

-- ============================================================
-- HELPER
-- ============================================================
-- Peran pemilik session token (admin/guru/siswa) atau NULL
create or replace function public.sesi_role(p_token text)
returns text
language sql stable security definer set search_path = public, extensions
as $$
  select role from public.sessions where id = p_token limit 1;
$$;

-- Token sesi acak
create or replace function public.token_baru(p_prefix text)
returns text
language sql volatile security definer set search_path = public, extensions
as $$
  select p_prefix || '-' || left(replace(gen_random_uuid()::text, '-', ''), 12);
$$;

-- ============================================================
-- RPC: AUTH SISWA
-- ============================================================
create or replace function public.rpc_login_siswa(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_siswa public.kode_ujian%rowtype;
  v_ujian public.ujian%rowtype;
  v_user  text; v_pass text; v_kode text;
begin
  v_user := btrim(coalesce(p_payload->>'username', ''));
  v_pass := coalesce(p_payload->>'password', '');
  v_kode := btrim(coalesce(p_payload->>'kode', ''));
  if v_user = '' or v_pass = '' then
    return json_build_object('ok', false, 'error', 'Isi username dan password.');
  end if;
  select * into v_siswa from public.kode_ujian where username = v_user;
  if not found or v_siswa.pass_hash <> encode(digest(v_pass, 'sha256'), 'hex') then
    return json_build_object('ok', false, 'error', 'Username atau password salah.');
  end if;
  select * into v_ujian from public.ujian where kode = v_kode;
  if v_kode = '' or not found then
    return json_build_object('ok', false, 'error', 'Kode ujian tidak terdeteksi. Periksa kembali.');
  end if;
  if v_ujian.status <> 'aktif' then
    return json_build_object('ok', false, 'error', 'Ujian belum diaktifkan admin. Hubungi pengawas.');
  end if;
  return json_build_object('ok', true, 'data', json_build_object(
    'siswa', json_build_object('username', v_siswa.username, 'nis', v_siswa.nis, 'nama', v_siswa.nama, 'kelas', v_siswa.kelas),
    'ujian', json_build_object('id', v_ujian.id, 'kode', v_ujian.kode, 'nama', v_ujian.nama)
  ));
end $$;

-- ============================================================
-- RPC: MULAI UJIAN (validasi token + anti login-ganda)
-- ============================================================
create or replace function public.rpc_mulai_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_siswa  public.kode_ujian%rowtype;
  v_ujian  public.ujian%rowtype;
  v_sesi   public.sesi%rowtype;
  v_sid    text;
  v_user   text;
  v_ada    boolean;
  v_mulai  timestamptz;
  v_sisa   integer;
begin
  v_user := btrim(coalesce(p_payload->>'username', ''));
  select * into v_siswa from public.kode_ujian where username = v_user;
  if not found then return json_build_object('ok', false, 'error', 'Siswa tidak terdaftar.'); end if;

  select * into v_ujian from public.ujian where kode = btrim(coalesce(p_payload->>'kode', ''));
  if not found then return json_build_object('ok', false, 'error', 'Kode ujian tidak terdeteksi.'); end if;
  if v_ujian.status <> 'aktif' then return json_build_object('ok', false, 'error', 'Ujian belum diaktifkan admin.'); end if;
  if v_ujian.token <> btrim(coalesce(p_payload->>'token', '')) then
    return json_build_object('ok', false, 'error', 'Token salah. Periksa kembali.');
  end if;

  select * into v_sesi from public.sesi where username = v_user for update;
  v_ada := found;
  -- Anti login-ganda: satu akun hanya boleh punya 1 sesi ACTIVE (mana pun ujiannya).
  -- Resume diizinkan bila request datang dari sesi login yang SAMA (browser yang sama,
  -- mis. setelah refresh/F5): session_id di payload masih milik siswa ini.
  -- Perangkat lain (session_id beda/null) tetap ditolak.
  if v_ada and v_sesi.status = 'ACTIVE'
     and not exists (select 1 from public.sessions
                      where id = coalesce(p_payload->>'session_id','')
                        and username = v_user and role = 'siswa') then
    return json_build_object('ok', false, 'error', 'Akun sudah dipakai di perangkat lain. Hubungi admin untuk reset.');
  end if;
  -- Anti re-submit bersifat PER-UJIAN: blokir hanya bila siswa sudah mengumpulkan
  -- ujian dengan kode yang sama (hasil disimpan per (username, kode_ujian)).
  if exists (select 1 from public.hasil where username = v_user and kode_ujian = v_ujian.kode) then
    return json_build_object('ok', false, 'error', 'Anda sudah mengumpulkan ujian.');
  end if;

  v_sid := public.token_baru('s');
  insert into public.sessions (id, username, role) values (v_sid, v_user, 'siswa');

  -- mulai_ts ditetapkan saat pertama mulai; pertahankan saat masuk ulang
  -- untuk UJIAN YANG SAMA (jam dinding tetap berjalan). Ujian berbeda = sesi baru.
  if v_ada and v_sesi.ujian_id = v_ujian.kode then
    update public.sesi set status='ACTIVE', login_ts=now(), fingerprint=coalesce(p_payload->>'fingerprint','')
      where username = v_user;
    select mulai_ts into v_mulai from public.sesi where username = v_user;
  elsif v_ada then
    update public.sesi set status='ACTIVE', login_ts=now(), mulai_ts=now(),
      fingerprint=coalesce(p_payload->>'fingerprint',''), ujian_id=v_ujian.kode
      where username = v_user;
    v_mulai := now();
  else
    insert into public.sesi (username, nis, status, login_ts, fingerprint, mulai_ts, ujian_id)
      values (v_user, v_siswa.nis, 'ACTIVE', now(), coalesce(p_payload->>'fingerprint',''), now(), v_ujian.kode);
    v_mulai := now();
  end if;
  v_mulai := coalesce(v_mulai, now());
  v_sisa := greatest(0, v_ujian.durasi_menit * 60 - extract(epoch from (now() - v_mulai))::integer);

  return json_build_object('ok', true, 'data', json_build_object(
    'sessionId', v_sid,
    'siswa', json_build_object('username', v_siswa.username, 'nis', v_siswa.nis, 'nama', v_siswa.nama, 'kelas', v_siswa.kelas),
    'ujian', json_build_object('id', v_ujian.id, 'kode', v_ujian.kode, 'nama', v_ujian.nama,
                               'durasiMenit', v_ujian.durasi_menit, 'soalIds', v_ujian.soal_ids),
    'sisaDetik', v_sisa,
    'jawabanLama', (select coalesce(jsonb_agg(
                       jsonb_build_object('soalId', soal_id, 'jawaban', jawaban) order by ts), '[]'::jsonb)
                      from public.jawaban
                     where username = v_user and v_ujian.soal_ids ? soal_id)
  ));
end $$;

-- ============================================================
-- RPC: AUTH STAF (guru/admin)
-- ============================================================
create or replace function public.rpc_login_admin(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_user public.users%rowtype;
  v_sid  text;
begin
  select * into v_user from public.users where username = btrim(coalesce(p_payload->>'username', ''));
  if not found or v_user.pass_hash <> encode(digest(coalesce(p_payload->>'password',''), 'sha256'), 'hex') then
    return json_build_object('ok', false, 'error', 'Username atau password salah');
  end if;
  if not v_user.aktif then return json_build_object('ok', false, 'error', 'Akun nonaktif'); end if;
  v_sid := public.token_baru('a');
  insert into public.sessions (id, username, role) values (v_sid, v_user.username, v_user.role);
  return json_build_object('ok', true, 'data', json_build_object(
    'role', v_user.role, 'username', v_user.username, 'sessionId', v_sid
  ));
end $$;

-- ============================================================
-- RPC: BANK SOAL
-- kunci & pembahasan hanya untuk guru/admin.
-- ============================================================
create or replace function public.rpc_bank_soal(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out  jsonb;
begin
  v_role := coalesce(public.sesi_role(p_payload->>'session_id'), 'anon');
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'mapel', s.mapel, 'jenjang', s.jenjang, 'topik', s.topik, 'kode', s.kode,
           'blocks', s.blocks, 'opsi', s.opsi,
           'kunci', case when v_role in ('guru','admin') then s.kunci else null end,
           'pembahasan', case when v_role in ('guru','admin') then s.pembahasan else null end,
           'status', s.status, 'uploader', s.uploader
         ) order by s.created), '[]'::jsonb)
    into v_out
  from public.soal_bank s
  where v_role in ('guru','admin') or s.status = 'aktif';
  return json_build_object('ok', true, 'data', v_out);
end $$;

-- ============================================================
-- RPC: SOAL (guru/admin)
-- ============================================================
create or replace function public.rpc_simpan_soal(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_soal jsonb;
  v_id   text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('guru','admin') then
    return json_build_object('ok', false, 'error', 'Anda harus login sebagai guru/admin.');
  end if;
  v_soal := coalesce(p_payload->'soal', '{}'::jsonb);
  if coalesce(v_soal->'blocks', '[]'::jsonb) = '[]'::jsonb then
    return json_build_object('ok', false, 'error', 'Soal tidak valid (blocks kosong)');
  end if;
  v_id := coalesce(nullif(v_soal->>'id', ''), 'S-' || to_hex((floor(random() * 900000) + 100000)::bigint));
  insert into public.soal_bank (id, mapel, jenjang, topik, kode, blocks, opsi, kunci, pembahasan, status, uploader, created)
  values (v_id,
          coalesce(v_soal->>'mapel', ''), coalesce(v_soal->>'jenjang', ''), coalesce(v_soal->>'topik', ''),
          coalesce(v_soal->>'kode', ''), coalesce(v_soal->'blocks', '[]'::jsonb), coalesce(v_soal->'opsi', '[]'::jsonb),
          coalesce(v_soal->>'kunci', ''), coalesce(v_soal->>'pembahasan', ''), coalesce(v_soal->>'status', 'draft'),
          coalesce(v_soal->>'uploader', ''), now())
  on conflict (id) do update set
    mapel = excluded.mapel, jenjang = excluded.jenjang, topik = excluded.topik, kode = excluded.kode,
    blocks = excluded.blocks, opsi = excluded.opsi, kunci = excluded.kunci,
    pembahasan = excluded.pembahasan, status = excluded.status, uploader = excluded.uploader;
  return json_build_object('ok', true, 'data', json_build_object('id', v_id));
end $$;

create or replace function public.rpc_hapus_soal(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('guru','admin') then
    return json_build_object('ok', false, 'error', 'Anda harus login sebagai guru/admin.');
  end if;
  delete from public.soal_bank where id = p_payload->>'id';
  return json_build_object('ok', true);
end $$;

-- ============================================================
-- RPC: UPLOAD SISWA (guru/admin)
-- ============================================================
create or replace function public.rpc_upload_siswa(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_rows jsonb;
  v_el   jsonb;
  v_user text;
  v_pass text;
  v_total integer := 0;
  v_users jsonb := '[]'::jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('guru','admin') then
    return json_build_object('ok', false, 'error', 'Anda harus login sebagai guru/admin.');
  end if;
  v_rows := coalesce(p_payload->'rows', '[]'::jsonb);
  for v_el in select * from jsonb_array_elements(v_rows) loop
    v_user := btrim(coalesce(v_el->>'username', v_el->>'nis', ''));
    v_pass := coalesce(v_el->>'password', '');
    if v_user = '' then v_user := 'siswa' || (floor(random() * 100000))::int; end if;
    insert into public.kode_ujian (username, pass_hash, nis, nama, kelas, ujian_id, status)
    values (v_user, encode(digest(v_pass, 'sha256'), 'hex'),
            coalesce(v_el->>'nis', ''), coalesce(v_el->>'nama', ''), coalesce(v_el->>'kelas', ''),
            coalesce(v_el->>'ujianId', ''), 'belum')
    on conflict (username) do nothing;
    if found then
      v_total := v_total + 1;
      v_users := v_users || to_jsonb(v_user);
    end if;
  end loop;
  return json_build_object('ok', true, 'data', json_build_object('total', v_total, 'usernames', v_users));
end $$;

-- ============================================================
-- RPC: UJIAN
-- ============================================================
create or replace function public.rpc_get_ujian(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out  jsonb;
begin
  v_role := coalesce(public.sesi_role(p_payload->>'session_id'), 'anon');
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id, 'nama', u.nama, 'kode', u.kode, 'mapel', u.mapel, 'jenjang', u.jenjang,
           'durasiMenit', u.durasi_menit, 'soalIds', u.soal_ids, 'status', u.status,
           'token', case when v_role in ('guru','admin') then u.token else null end
         ) order by u.created), '[]'::jsonb)
    into v_out
  from public.ujian u;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_buat_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_ujian jsonb;
  v_id text;
  v_kode text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('guru','admin') then
    return json_build_object('ok', false, 'error', 'Anda harus login sebagai guru/admin.');
  end if;
  v_ujian := coalesce(p_payload->'ujian', '{}'::jsonb);
  if coalesce(v_ujian->'soalIds', '[]'::jsonb) = '[]'::jsonb then
    return json_build_object('ok', false, 'error', 'Pilih minimal 1 soal');
  end if;
  v_id := 'U-' || to_hex((floor(random() * 900000) + 100000)::bigint);
  v_kode := btrim(coalesce(v_ujian->>'kode', ''));
  if v_kode = '' then
    v_kode := 'EXM-' || to_char(now(), 'YYYYMM') || '-' || lpad((floor(random()*100000))::int::text, 5, '0');
  end if;
  if exists (select 1 from public.ujian where kode = v_kode) then
    return json_build_object('ok', false, 'error', 'Kode ujian sudah dipakai. Gunakan kode lain.');
  end if;
  insert into public.ujian (id, nama, kode, mapel, jenjang, durasi_menit, soal_ids, status, token, created)
  values (v_id,
          coalesce(v_ujian->>'nama', 'Ujian'), v_kode,
          coalesce(v_ujian->>'mapel', ''), coalesce(v_ujian->>'jenjang', ''),
          coalesce((v_ujian->>'durasiMenit')::int, 60),
          coalesce(v_ujian->'soalIds', '[]'::jsonb), 'draft', '', now());
  return json_build_object('ok', true, 'data', json_build_object('id', v_id, 'kode', v_kode, 'status', 'draft'));
end $$;

create or replace function public.rpc_hapus_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_ujian public.ujian%rowtype;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('guru','admin') then
    return json_build_object('ok', false, 'error', 'Anda harus login sebagai guru/admin.');
  end if;
  select * into v_ujian from public.ujian where id = p_payload->>'id';
  if not found then return json_build_object('ok', false, 'error', 'Ujian tidak ditemukan.'); end if;
  delete from public.sesi where username in (
    select username from public.kode_ujian
    where ujian_id = v_ujian.kode or ujian_id = v_ujian.id
  );
  delete from public.kode_ujian
   where ujian_id = v_ujian.kode or ujian_id = v_ujian.id;
  delete from public.ujian where id = v_ujian.id;
  return json_build_object('ok', true, 'data', json_build_object('id', v_ujian.id));
end $$;

create or replace function public.rpc_aktifkan_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_ujian public.ujian%rowtype;
  v_token text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  select * into v_ujian from public.ujian where id = p_payload->>'id';
  if not found then return json_build_object('ok', false, 'error', 'Ujian tidak ditemukan.'); end if;
  if not exists (
    select 1 from public.soal_bank s
    where s.status = 'aktif' and v_ujian.soal_ids ? s.id
  ) then
    return json_build_object('ok', false, 'error', 'Tidak ada soal aktif pada ujian ini. Aktifkan dulu soal di bank soal (guru).');
  end if;
  v_token := btrim(v_ujian.token);
  if v_token = '' then
    v_token := 'TKN-' || upper(left(replace(gen_random_uuid()::text, '-', ''), 8));
    update public.ujian set token = v_token where id = v_ujian.id;
  end if;
  update public.ujian set status = 'aktif' where id = v_ujian.id;
  return json_build_object('ok', true, 'data', json_build_object('id', v_ujian.id, 'token', v_token, 'status', 'aktif'));
end $$;
create or replace function public.rpc_selesai_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$

declare
  v_role text;
  v_ujian public.ujian%rowtype;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;

  -- Temukan ujian sebelum melakukan update
  select * into v_ujian from public.ujian where id = p_payload->>'id';
  if not found then
    return json_build_object('ok', false, 'error', 'Ujian tidak ditemukan.');
  end if;

  -- Set ujian kembali ke draft
  update public.ujian set status = 'draft' where id = p_payload->>'id';

  -- Reset status siswa ke INACTIVE untuk semua sesi ujian yang baru selesai
  update public.sesi set status = 'INACTIVE' where ujian_id = v_ujian.kode;

  return json_build_object('ok', true, 'data', json_build_object('id', p_payload->>'id', 'status', 'draft', 'activeSessionsReset', true));
end $$;

-- ============================================================
-- RPC: JAWABAN & SUBMIT (scoring server-side)
-- ============================================================
create or replace function public.rpc_jawaban(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_sess_user text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null then
    return json_build_object('ok', false, 'error', 'Sesi tidak valid.');
  end if;
  -- Anti spoofing: sesi siswa hanya boleh menulis jawaban untuk dirinya sendiri.
  if v_role = 'siswa' then
    select username into v_sess_user from public.sessions where id = p_payload->>'session_id';
    if v_sess_user is distinct from coalesce(p_payload->>'username', '') then
      return json_build_object('ok', false, 'error', 'Sesi tidak sesuai akun.');
    end if;
  end if;
  if coalesce(p_payload->>'soalId', '') = '' then
    return json_build_object('ok', false, 'error', 'soalId kosong');
  end if;
  insert into public.jawaban (username, nis, soal_id, jawaban, ts)
  values (coalesce(p_payload->>'username', ''), coalesce(p_payload->>'nis', ''),
          p_payload->>'soalId', coalesce(p_payload->>'jawaban', ''),
          coalesce(nullif(p_payload->>'ts', '')::timestamptz, now()))
  on conflict (username, soal_id) do update
    set jawaban = excluded.jawaban, nis = excluded.nis, ts = excluded.ts;
  return json_build_object('ok', true);
end $$;

create or replace function public.rpc_submit_ujian(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$

declare
  v_role text;
  v_ans  jsonb;
  v_j    jsonb;
  v_kunci text;
  v_benar integer := 0;
  v_total integer := 0;
  v_kosong integer := 0;
  v_salah integer := 0;
  v_nilai integer := 0;
  v_username text;
  v_kode_ujian text;
  v_kelas text;
  v_sess_user text;
  v_start_ts timestamptz;
  v_durasi_menit integer;
  v_sisa_detik integer;
  v_elapsed integer;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null then
    return json_build_object('ok', false, 'error', 'Sesi tidak valid.');
  end if;
  v_username := coalesce(p_payload->>'username', '');
  v_kode_ujian := coalesce(p_payload->>'kode', '');
  v_kelas := coalesce(p_payload->>'kelas', '');
  -- Kode ujian yang dikerjakan = kode di payload (sama dengan yang dipakai siswa
  -- saat mulai & tersimpan di sesi.ujian_id). kode_ujian.ujian_id hanya fallback
  -- bila payload kosong, supaya hasil tercatat ke ujian yang benar (konsisten dgn mock).
  select coalesce(ujian_id, ''), coalesce(kelas, '') into v_kode_ujian, v_kelas
    from public.kode_ujian where username = v_username and coalesce(p_payload->>'kode', '') = '';
  if coalesce(v_kode_ujian, '') = '' then v_kode_ujian := coalesce(p_payload->>'kode', ''); end if;
  if coalesce(v_kelas, '') = '' then v_kelas := coalesce(p_payload->>'kelas', ''); end if;
  -- Anti spoofing + anti oracle: sesi siswa hanya boleh mengumpulkan untuk
  -- dirinya sendiri, dan hanya saat sesi UJIAN INI masih ACTIVE (belum pernah submit).
  if v_role = 'siswa' then
    select username into v_sess_user from public.sessions where id = p_payload->>'session_id';
    if v_sess_user is distinct from v_username then
      return json_build_object('ok', false, 'error', 'Sesi tidak sesuai akun.');
    end if;
    if not exists (select 1 from public.sesi
                    where username = v_username and status = 'ACTIVE'
                      and ujian_id = coalesce(p_payload->>'kode', '')) then
      return json_build_object('ok', false, 'error', 'Sesi tidak aktif — jawaban sudah dikumpulkan atau belum mulai.');
    end if;
  end if;
  -- Validasi waktu: pastikan sesi masih dalam batas waktu ujian
  select mulai_ts, durasi_menit into v_start_ts, v_durasi_menit
    from public.sesi join public.ujian on ujian.kode = sesi.ujian_id
    where username = v_username and sesi.ujian_id = v_kode_ujian
    limit 1;
  if v_start_ts is not null and v_durasi_menit is not null then
    v_sisa_detik := greatest(0, v_durasi_menit * 60 - extract(epoch from (now() - v_start_ts))::integer);
    -- Cek apakah waktu sudah habis (sisaDetik <= 0 berarti waktu habis)
    if v_sisa_detik <= 0 then
      return json_build_object('ok', false, 'error', 'Waktu ujian telah berakhir. Tidak bisa mengirim jawaban.');
    end if;
  end if;
  v_ans := coalesce(p_payload->'jawaban', '[]'::jsonb);
  for v_j in select * from jsonb_array_elements(v_ans) loop
    v_total := v_total + 1;
    select kunci into v_kunci from public.soal_bank where id = v_j->>'soalId';
    if coalesce(v_j->>'jawaban', '') = '' then
      v_kosong := v_kosong + 1;
    elsif v_kunci = v_j->>'jawaban' then
      v_benar := v_benar + 1;
    else
      v_salah := v_salah + 1;
    end if;
  end loop;
  v_nilai := case when v_total > 0 then round((v_benar * 100.0) / v_total) else 0 end;
  insert into public.hasil (username, nis, nama, kode_ujian, kelas, benar, total, nilai, ts)
  values (v_username, coalesce(p_payload->>'nis', ''), coalesce(p_payload->>'nama', ''),
          v_kode_ujian, v_kelas, v_benar, v_total, v_nilai, now())
  on conflict (username, kode_ujian) where kode_ujian <> '' do update
    set nis = excluded.nis, nama = excluded.nama, kelas = excluded.kelas,
        benar = excluded.benar, total = excluded.total, nilai = excluded.nilai, ts = excluded.ts;
  update public.sesi set status = 'SELESAI'
    where username = v_username and ujian_id = coalesce(p_payload->>'kode', '');
  return json_build_object('ok', true, 'data', json_build_object(
    'benar', v_benar, 'salah', v_salah, 'kosong', v_kosong, 'total', v_total, 'nilai', v_nilai
  ));
end $$;

-- ============================================================
-- RPC: ADMIN (monitor, reset, user)
-- ============================================================
create or replace function public.rpc_get_progress(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'username', ku.username, 'nis', ku.nis,
           -- kode ujian yang benar = sesi yang sedang/sudah dikerjakan siswa
           'kode_ujian', coalesce(nullif(s.ujian_id, ''), ku.ujian_id, ''),
           'status', coalesce(s.status, 'INACTIVE'),
           'login_ts', s.login_ts, 'fingerprint', s.fingerprint) order by s.login_ts desc nulls last), '[]'::jsonb)
    into v_out
  from public.kode_ujian ku
  left join public.sesi s on s.username = ku.username;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_reset_login(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  if exists (select 1 from public.hasil where username = p_payload->>'username')
     or exists (select 1 from public.sesi where username = p_payload->>'username' and status = 'SELESAI') then
    return json_build_object('ok', false, 'error', 'Siswa sudah mengumpulkan ujian; hasil tidak bisa dibatalkan lewat reset.');
  end if;
  update public.sesi set status = 'INACTIVE' where username = p_payload->>'username';
  delete from public.reset_requests where username = p_payload->>'username';
  return json_build_object('ok', true);
end $$;

-- Siswa meminta reset login (dikonfirmasi ulang dengan password, hanya saat sesi terkunci ACTIVE)
create or replace function public.rpc_minta_reset(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_user  text;
  v_pass  text;
  v_kode  text;
  v_siswa public.kode_ujian%rowtype;
  v_sesi  public.sesi%rowtype;
begin
  v_user := btrim(coalesce(p_payload->>'username', ''));
  v_pass := coalesce(p_payload->>'password', '');
  v_kode := btrim(coalesce(p_payload->>'kode', ''));
  if v_user = '' or v_pass = '' then
    return json_build_object('ok', false, 'error', 'Username/password kosong.');
  end if;
  select * into v_siswa from public.kode_ujian where username = v_user;
  if not found or v_siswa.pass_hash <> encode(digest(v_pass, 'sha256'), 'hex') then
    return json_build_object('ok', false, 'error', 'Kredensial tidak valid.');
  end if;
  select * into v_sesi from public.sesi where username = v_user;
  if not found or v_sesi.status <> 'ACTIVE' then
    return json_build_object('ok', false, 'error', 'Akun tidak sedang terkunci. Tidak perlu reset.');
  end if;
  v_kode := coalesce(nullif(v_kode, ''), v_sesi.ujian_id);
  if exists (select 1 from public.hasil where username = v_user and kode_ujian = v_kode) then
    return json_build_object('ok', false, 'error', 'Ujian sudah dikumpulkan; tidak bisa direset.');
  end if;
  insert into public.reset_requests (username, nis, nama, kelas, kode_ujian, requested_at)
  values (v_user, v_siswa.nis, v_siswa.nama, v_siswa.kelas, v_kode, now())
  on conflict (username) do update
    set nis = excluded.nis, nama = excluded.nama, kelas = excluded.kelas,
        kode_ujian = excluded.kode_ujian, requested_at = excluded.requested_at;
  return json_build_object('ok', true);
end $$;

-- Daftar permintaan reset login (khusus admin, tab Reset Siswa)
create or replace function public.rpc_get_reset_requests(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'username', r.username, 'nis', r.nis, 'nama', r.nama,
           'kelas', r.kelas, 'kode_ujian', r.kode_ujian,
           'requested_at', r.requested_at) order by r.requested_at desc), '[]'::jsonb)
    into v_out
  from public.reset_requests r;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_get_hasil(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('admin','guru') then
    return json_build_object('ok', false, 'error', 'Khusus guru/admin.');
  end if;
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'username', h.username, 'nis', h.nis, 'nama', h.nama,
             'kode_ujian', coalesce(nullif(h.kode_ujian, ''), nullif(u.kode, ''), nullif(ku.ujian_id, ''), ''),
             'kelas', coalesce(nullif(h.kelas, ''), nullif(ku.kelas, ''), ''),
             'benar', h.benar, 'total', h.total, 'nilai', h.nilai, 'ts', h.ts
           ) order by h.ts desc), '[]'::jsonb)
    into v_out
  from public.hasil h
  left join lateral (
    select ku.ujian_id, ku.kelas
      from public.kode_ujian ku
     where ku.username = h.username
     limit 1
  ) ku on true
  left join lateral (
    select u.kode
      from public.ujian u
     where u.kode = ku.ujian_id or u.id = ku.ujian_id
        or u.kode = h.kode_ujian
     limit 1
  ) u on true;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_get_siswa(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role not in ('admin','guru') then
    return json_build_object('ok', false, 'error', 'Khusus guru/admin.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'username', ku.username, 'nis', ku.nis, 'nama', ku.nama,
           'kelas', ku.kelas, 'ujianId', ku.ujian_id) order by ku.nama), '[]'::jsonb)
    into v_out
  from public.kode_ujian ku;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_get_users(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_out jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'username', u.username, 'role', u.role, 'aktif', u.aktif,
           'pass', coalesce(u.pass_plain, '')) order by u.username), '[]'::jsonb)
    into v_out from public.users u;
  return json_build_object('ok', true, 'data', v_out);
end $$;

create or replace function public.rpc_tambah_user(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_user jsonb;
  v_username text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  v_user := coalesce(p_payload->'user', '{}'::jsonb);
  v_username := btrim(coalesce(v_user->>'username', ''));
  if v_username = '' or coalesce(v_user->>'passHash', '') = '' then
    return json_build_object('ok', false, 'error', 'Username/password kosong');
  end if;
  if exists (select 1 from public.users where username = v_username) then
    return json_build_object('ok', false, 'error', 'Username sudah ada');
  end if;
  insert into public.users (username, pass_hash, pass_plain, role, aktif)
  values (v_username, encode(digest(v_user->>'passHash', 'sha256'), 'hex'),
          coalesce(v_user->>'passHash', ''),
          coalesce(v_user->>'role', 'guru'), coalesce(v_user->>'aktif', 'true')::boolean);
  return json_build_object('ok', true);
end $$;

create or replace function public.rpc_hapus_user(p_payload jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_username text;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  v_username := btrim(coalesce(p_payload->>'username', ''));
  if v_username = '' then
    return json_build_object('ok', false, 'error', 'Username kosong');
  end if;
  if v_username = 'admin' then
    return json_build_object('ok', false, 'error', 'Akun admin utama tidak bisa dihapus.');
  end if;
  delete from public.users where username = v_username;
  return json_build_object('ok', true);
end $$;

-- ============================================================
-- RPC: GENERATE KARTU SISWA
-- ============================================================
create or replace function public.rpc_generate_kartu(p_payload jsonb default '{}'::jsonb)
returns json
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role text;
  v_usernames jsonb;
  v_username text;
  v_password text;
  v_total integer := 0;
  v_updated jsonb := '[]'::jsonb;
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;

  -- Ambil daftar username yang akan digenerate password
  -- Jika tidak ada filter, generate untuk semua siswa
  v_usernames := coalesce(p_payload->'usernames', '[]'::jsonb);
  if jsonb_array_length(v_usernames) = 0 then
    select jsonb_agg(username) into v_usernames from public.kode_ujian;
  end if;

  -- Generate password random 8 karakter alfabetik dan update database
  FOR v_username IN SELECT jsonb_array_elements_text(v_usernames) LOOP
    -- Generate password acak 8 karakter readable (tanpa karakter ambigu 0/O/1/I/l)
    v_password := substring(
      translate(
        md5(random()::text),
        '0123456789abcdef',
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
      ) from 1 for 8
    );
    update public.kode_ujian set pass_plain = v_password where username = v_username;
    v_total := v_total + 1;
    v_updated := v_updated || to_jsonb(jsonb_build_object('username', v_username, 'password', v_password, 'nis', (select nis from public.kode_ujian where username = v_username), 'nama', (select nama from public.kode_ujian where username = v_username), 'kelas', (select kelas from public.kode_ujian where username = v_username)));
  end loop;

  return json_build_object('ok', true, 'data', json_build_object('total', v_total, 'updated', v_updated));
end $$;
