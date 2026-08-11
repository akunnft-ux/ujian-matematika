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
create table if not exists public.users (
  username text primary key,
  pass_hash text not null,
  role     text not null check (role in ('admin','guru')),
  aktif    boolean not null default true
);

-- Bank soal (blok teks/latex/gambar)
create table if not exists public.soal_bank (
  id         text primary key,
  mapel      text not null default '',
  kelas      text not null default '',
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
  kelas        text not null default '',
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
  nis       text not null default '',
  nama      text not null default '',
  kelas     text not null default '',
  ujian_id  text not null default '',
  status    text not null default 'belum'
);

-- Status sesi ujian siswa (anti login-ganda)
create table if not exists public.sesi (
  username    text primary key,
  nis         text not null default '',
  status      text not null default 'INACTIVE',
  login_ts    timestamptz not null default now(),
  fingerprint text not null default ''
);

-- Token sesi login (siswa & staf) untuk otentikasi request
create table if not exists public.sessions (
  id         text primary key,
  username   text not null,
  role       text not null,
  created_at timestamptz not null default now()
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

-- ============================================================
-- RLS + REVOKE: anon/authenticated tidak boleh akses tabel
-- ============================================================
alter table public.users      enable row level security;
alter table public.soal_bank  enable row level security;
alter table public.ujian      enable row level security;
alter table public.kode_ujian enable row level security;
alter table public.sesi       enable row level security;
alter table public.sessions   enable row level security;
alter table public.jawaban    enable row level security;
alter table public.hasil      enable row level security;

revoke all on public.users, public.soal_bank, public.ujian,
          public.kode_ujian, public.sesi, public.sessions,
          public.jawaban, public.hasil
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
  if v_ada then
    if v_sesi.status = 'ACTIVE' then
      return json_build_object('ok', false, 'error', 'Akun sudah dipakai di perangkat lain. Hubungi admin untuk reset.');
    end if;
    if v_sesi.status = 'SELESAI' then
      return json_build_object('ok', false, 'error', 'Anda sudah mengumpulkan ujian.');
    end if;
  end if;

  v_sid := public.token_baru('s');
  insert into public.sessions (id, username, role) values (v_sid, v_user, 'siswa');

  if v_ada then
    update public.sesi set status='ACTIVE', login_ts=now(), fingerprint=coalesce(p_payload->>'fingerprint','')
      where username = v_user;
  else
    insert into public.sesi (username, nis, status, login_ts, fingerprint)
      values (v_user, v_siswa.nis, 'ACTIVE', now(), coalesce(p_payload->>'fingerprint',''));
  end if;

  return json_build_object('ok', true, 'data', json_build_object(
    'sessionId', v_sid,
    'siswa', json_build_object('username', v_siswa.username, 'nis', v_siswa.nis, 'nama', v_siswa.nama, 'kelas', v_siswa.kelas),
    'ujian', json_build_object('id', v_ujian.id, 'kode', v_ujian.kode, 'nama', v_ujian.nama,
                               'durasiMenit', v_ujian.durasi_menit, 'soalIds', v_ujian.soal_ids)
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
           'id', s.id, 'mapel', s.mapel, 'kelas', s.kelas, 'topik', s.topik, 'kode', s.kode,
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
  insert into public.soal_bank (id, mapel, kelas, topik, kode, blocks, opsi, kunci, pembahasan, status, uploader, created)
  values (v_id,
          coalesce(v_soal->>'mapel', ''), coalesce(v_soal->>'kelas', ''), coalesce(v_soal->>'topik', ''),
          coalesce(v_soal->>'kode', ''), coalesce(v_soal->'blocks', '[]'::jsonb), coalesce(v_soal->'opsi', '[]'::jsonb),
          coalesce(v_soal->>'kunci', ''), coalesce(v_soal->>'pembahasan', ''), coalesce(v_soal->>'status', 'draft'),
          coalesce(v_soal->>'uploader', ''), now())
  on conflict (id) do update set
    mapel = excluded.mapel, kelas = excluded.kelas, topik = excluded.topik, kode = excluded.kode,
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
           'id', u.id, 'nama', u.nama, 'kode', u.kode, 'mapel', u.mapel, 'kelas', u.kelas,
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
  insert into public.ujian (id, nama, kode, mapel, kelas, durasi_menit, soal_ids, status, token, created)
  values (v_id,
          coalesce(v_ujian->>'nama', 'Ujian'), v_kode,
          coalesce(v_ujian->>'mapel', ''), coalesce(v_ujian->>'kelas', ''),
          coalesce((v_ujian->>'durasiMenit')::int, 60),
          coalesce(v_ujian->'soalIds', '[]'::jsonb), 'draft', '', now());
  return json_build_object('ok', true, 'data', json_build_object('id', v_id, 'kode', v_kode, 'status', 'draft'));
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
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null or v_role <> 'admin' then
    return json_build_object('ok', false, 'error', 'Khusus admin.');
  end if;
  update public.ujian set status = 'draft' where id = p_payload->>'id';
  return json_build_object('ok', true, 'data', json_build_object('id', p_payload->>'id', 'status', 'draft'));
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
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null then
    return json_build_object('ok', false, 'error', 'Sesi tidak valid.');
  end if;
  if coalesce(p_payload->>'soalId', '') = '' then
    return json_build_object('ok', false, 'error', 'soalId kosong');
  end if;
  insert into public.jawaban (username, nis, soal_id, jawaban, ts)
  values (coalesce(p_payload->>'username', ''), coalesce(p_payload->>'nis', ''),
          p_payload->>'soalId', coalesce(p_payload->>'jawaban', ''),
          coalesce(nullif(p_payload->>'ts', '')::timestamptz, now()));
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
begin
  v_role := public.sesi_role(p_payload->>'session_id');
  if v_role is null then
    return json_build_object('ok', false, 'error', 'Sesi tidak valid.');
  end if;
  v_username := coalesce(p_payload->>'username', '');
  v_kode_ujian := coalesce(p_payload->>'kode', '');
  v_kelas := coalesce(p_payload->>'kelas', '');
  select coalesce(ujian_id, ''), coalesce(kelas, '') into v_kode_ujian, v_kelas
    from public.kode_ujian where username = v_username;
  if coalesce(v_kode_ujian, '') = '' then v_kode_ujian := coalesce(p_payload->>'kode', ''); end if;
  if coalesce(v_kelas, '') = '' then v_kelas := coalesce(p_payload->>'kelas', ''); end if;
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
          v_kode_ujian, v_kelas, v_benar, v_total, v_nilai, now());
  update public.sesi set status = 'SELESAI' where username = v_username;
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
  update public.sesi set status = 'INACTIVE' where username = p_payload->>'username';
  return json_build_object('ok', true);
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
             'kelas', coalesce(nullif(h.kelas, ''), nullif(ku.kelas, ''), nullif(u.kelas, ''), ''),
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
    select u.kode, u.kelas
      from public.ujian u
     where u.kode = ku.ujian_id or u.id = ku.ujian_id
        or u.kode = h.kode_ujian
     limit 1
  ) u on true;
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
           'username', u.username, 'pass_hash', u.pass_hash, 'role', u.role, 'aktif', u.aktif) order by u.username), '[]'::jsonb)
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
  insert into public.users (username, pass_hash, role, aktif)
  values (v_username, encode(digest(v_user->>'passHash', 'sha256'), 'hex'),
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
