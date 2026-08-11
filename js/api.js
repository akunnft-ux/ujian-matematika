/* ============================================================
 * api.js — Lapisan API (abstraksi backend)
 * ------------------------------------------------------------
 * Seluruh komunikasi aplikasi lewat AppAPI.call(action, payload).
 *
 * Dua mode (atur di js/config.js → BACKEND):
 *   - "mock"     (default) : data di localStorage (demo)
 *   - "supabase"           : RPC function di Postgres via PostgREST
 *
 * Fitur:
 *   - queue + retry pengiriman jawaban (anti jawaban hilang saat offline)
 *   - timeout + error terstruktur
 *   - session id disuntikkan otomatis
 *
 * Mengganti backend = isi BACKEND + SUPABASE_URL + SUPABASE_ANON_KEY
 * di config.js saja, tanpa ubah halaman.
 * ============================================================ */
(function (global) {
  "use strict";

  var MOCK_KEY = "ujian_app_mock_db";

  /* ============ MOCK DATABASE (mode demo) ============ */
  function loadMock() {
    try { return JSON.parse(localStorage.getItem(MOCK_KEY) || "{}"); }
    catch (e) { return {}; }
  }
  function saveMock(db) {
    localStorage.setItem(MOCK_KEY, JSON.stringify(db));
  }
  function mockInit() {
    var db = loadMock();
    var changed = false;
    if (!db.users) {
      db.users = [
        { username: "admin", passHash: "admin", role: "admin", aktif: true },
        { username: "guru", passHash: "guru", role: "guru", aktif: true }
      ];
      changed = true;
    }
    if (!db.bankSoal) { db.bankSoal = mockContohSoal(); changed = true; }
    if (!db.ujian) {
      db.ujian = [{
        id: "U-001", nama: "Ujian Matematika XII IPA", kode: "EXM-2026-001",
        mapel: "Matematika", kelas: "XII IPA", durasiMenit: 60,
        soalIds: ["S-001", "S-002"], status: "aktif", token: "TKN-DEMO"
      }];
      changed = true;
    }
    if (!db.kodeUjian) {
      db.kodeUjian = [
        { username: "budi", password: "budi123", nis: "2026001", nama: "Budi Santoso", kelas: "XII IPA 1", ujianId: "EXM-2026-001", status: "belum" },
        { username: "siti", password: "siti123", nis: "2026002", nama: "Siti Rahayu", kelas: "XII IPA 1", ujianId: "EXM-2026-001", status: "belum" }
      ];
      changed = true;
    }
    if (!db.sesi) { db.sesi = []; changed = true; }
    if (!db.jawaban) { db.jawaban = []; changed = true; }
    if (!db.hasil) { db.hasil = []; changed = true; }
    if (changed) saveMock(db);
    return db;
  }

  function mockContohSoal() {
    return [
      {
        id: "S-001",
        kode: "M-2026-001",
        mapel: "Matematika",
        kelas: "XII IPA",
        topik: "Kalkulus",
        blocks: [
          { type: "text", value: "Diketahui fungsi " },
          { type: "latex", value: "f(x)=2x^3-9x^2+12x+5" },
          { type: "text", value: ". Nilai stasioner minimumnya adalah ..." }
        ],
        opsi: ["$5$", "$8$", "$9$", "$10$", "$14$"],
        kunci: "C",
        pembahasan: "f'(x)=6x^2-18x+12, titik stasioner x=1 dan x=2; f(2)=9 minimum lokal.",
        status: "aktif",
        uploader: "guru"
      },
      {
        id: "S-002",
        kode: "M-2026-001",
        mapel: "Matematika",
        kelas: "XII IPA",
        topik: "Integral",
        blocks: [
          { type: "text", value: "Nilai dari " },
          { type: "latex", value: "\\int_{0}^{\\pi/2} \\sin^2(x)\\cos(x)\\,dx" },
          { type: "text", value: " adalah ..." }
        ],
        opsi: ["$\\frac{1}{6}$", "$\\frac{1}{4}$", "$\\frac{1}{3}$", "$\\frac{1}{2}$", "$1$"],
        kunci: "C",
        pembahasan: "Substitusi u = sin(x).",
        status: "aktif",
        uploader: "guru"
      }
    ];
  }

  /* ============ MOCK HANDLERS ============ */
  function mockNow() { return new Date().toISOString(); }
  function shaMock(str) { return String(str); } // demo: plain (bukan produksi!)

  function mockLoginAdmin(u, p) {
    var db = loadMock();
    var user = (db.users || []).find(function (x) {
      return x.username === u && x.passHash === p;
    });
    if (!user) return { ok: false, error: "Username atau password salah" };
    if (user.role !== "admin" && user.role !== "guru") return { ok: false, error: "Tidak diizinkan" };
    return { ok: true, data: { role: user.role, username: user.username, sessionId: "sess-" + Date.now() } };
  }

  function mockLoginSiswa(username, password, kode) {
    var db = loadMock();
    username = String(username || "").trim();
    password = String(password || "");
    kode = String(kode || "").trim();
    if (!username || !password) return { ok: false, error: "Isi username dan password." };
    var siswa = (db.kodeUjian || []).find(function (k) {
      return String(k.username || "").trim() === username && String(k.password || "") === password;
    });
    if (!siswa) return { ok: false, error: "Username atau password salah." };
    var ujian = (db.ujian || []).find(function (u) { return u.kode === kode; });
    if (!kode || !ujian) return { ok: false, error: "Kode ujian tidak terdeteksi. Periksa kembali." };
    if (ujian.status !== "aktif") {
      return { ok: false, error: "Ujian belum diaktifkan admin. Hubungi pengawas." };
    }
    return { ok: true, data: { siswa: siswa, ujian: { id: ujian.id, kode: ujian.kode, nama: ujian.nama } } };
  }

  function mockMulaiUjian(username, kode, token) {
    var db = loadMock();
    username = String(username || "").trim();
    kode = String(kode || "").trim();
    token = String(token || "").trim();
    var siswa = (db.kodeUjian || []).find(function (k) {
      return String(k.username || "").trim() === username;
    });
    if (!siswa) return { ok: false, error: "Siswa tidak terdaftar." };
    var ujian = (db.ujian || []).find(function (u) { return u.kode === kode; });
    if (!ujian) return { ok: false, error: "Kode ujian tidak terdeteksi." };
    if (ujian.status !== "aktif") return { ok: false, error: "Ujian belum diaktifkan admin." };
    if (ujian.token !== token) return { ok: false, error: "Token salah. Periksa kembali." };
    var sesi = (db.sesi || []).find(function (s) { return s.username === siswa.username; });
    if (sesi && sesi.status === "ACTIVE") {
      return { ok: false, error: "Akun sudah dipakai. Hubungi admin untuk reset." };
    }
    if (sesi && sesi.status === "SELESAI") {
      return { ok: false, error: "Anda sudah mengumpulkan ujian." };
    }
    var sesiBaru = {
      username: siswa.username, nis: siswa.nis, status: "ACTIVE",
      login_ts: mockNow(), fingerprint: navigator.userAgent.slice(0, 40)
    };
    if (sesi) { sesi.status = "ACTIVE"; sesi.login_ts = sesiBaru.login_ts; }
    else db.sesi.push(sesiBaru);
    saveMock(db);
    return { ok: true, data: { siswa: siswa, ujian: ujian, sessionId: "sess-" + Date.now() } };
  }

  function mockGetBankSoal() {
    return { ok: true, data: (loadMock().bankSoal || []).slice() };
  }
  function mockSimpanSoal(soal) {
    var db = loadMock();
    var arr = db.bankSoal || [];
    if (!soal.id) { soal.id = "S-" + (Date.now().toString(36)); }
    var idx = arr.findIndex(function (s) { return s.id === soal.id; });
    if (idx >= 0) arr[idx] = soal; else arr.push(soal);
    saveMock(db);
    return { ok: true, data: soal };
  }
  function mockHapusSoal(id) {
    var db = loadMock();
    db.bankSoal = (db.bankSoal || []).filter(function (s) { return s.id !== id; });
    saveMock(db);
    return { ok: true };
  }
  function mockUploadSiswa(rows) {
    var db = loadMock();
    var kode = db.kodeUjian || [];
    var usernames = [];
    rows.forEach(function (r) {
      var username = (r.username || r.nis || "").toString().trim();
      if (!username) username = "siswa" + Math.floor(Math.random() * 100000);
      kode.push({
        username: username,
        password: String(r.password || ""),
        nis: r.nis || "",
        nama: r.nama,
        kelas: r.kelas || "",
        ujianId: r.ujianId || "",
        status: "belum"
      });
      usernames.push(username);
    });
    db.kodeUjian = kode;
    saveMock(db);
    return { ok: true, data: { total: rows.length, usernames: usernames } };
  }
  function mockBuatUjian(ujian) {
    var db = loadMock();
    if (!ujian.id) ujian.id = "U-" + (Date.now().toString(36));
    ujian.status = "draft";
    ujian.token = "";
    (db.ujian || []).push(ujian);
    saveMock(db);
    return { ok: true, data: ujian };
  }
  function mockGetUjian() { return { ok: true, data: (loadMock().ujian || []).slice() }; }
  function mockAktifkanUjian(id) {
    var db = loadMock();
    var ujian = (db.ujian || []).find(function (u) { return u.id === id; });
    if (!ujian) return { ok: false, error: "Ujian tidak ditemukan." };
    var bank = db.bankSoal || [];
    var adaAktif = (ujian.soalIds || []).some(function (sid) {
      var s = bank.find(function (b) { return b.id === sid; });
      return s && s.status === "aktif";
    });
    if (!adaAktif) return { ok: false, error: "Tidak ada soal aktif pada ujian ini. Aktifkan dulu soal di bank soal (guru)." };
    if (!ujian.token) ujian.token = "TKN-" + Math.random().toString(36).slice(2, 8).toUpperCase().replace(/[^A-Z0-9]/g, "");
    ujian.status = "aktif";
    saveMock(db);
    return { ok: true, data: { ujian: ujian, token: ujian.token } };
  }

  function mockSelesaiUjian(id) {
    var db = loadMock();
    var ujian = (db.ujian || []).find(function (u) { return u.id === id; });
    if (!ujian) return { ok: false, error: "Ujian tidak ditemukan." };
    ujian.status = "draft";
    saveMock(db);
    return { ok: true, data: { id: id, status: "draft" } };
  }

  function mockResetLogin(username) {
    var db = loadMock();
    var sesi = (db.sesi || []).find(function (s) { return s.username === username; });
    if (sesi) sesi.status = "INACTIVE";
    saveMock(db);
    return { ok: true };
  }
  function mockGetProgress() {
    var db = loadMock();
    var sesi = db.sesi || [];
    return { ok: true, data: (db.kodeUjian || []).map(function (k) {
      var s = sesi.find(function (x) { return x.username === k.username; });
      return {
        username: k.username,
        nis: k.nis || "",
        status: s ? s.status : "INACTIVE",
        login_ts: s ? s.login_ts : null,
        fingerprint: s ? s.fingerprint : ""
      };
    }) };
  }
  function mockGetHasil() {
    var db = loadMock();
    var siswa = db.kodeUjian || [];
    var ujian = db.ujian || [];
    var hasil = (db.hasil || []).slice();
    hasil.forEach(function (h) {
      var s = siswa.find(function (x) { return x.username === h.username; });
      if (!h.kelas && s && s.kelas) h.kelas = s.kelas;
      if (!h.kode_ujian && s && s.ujianId) {
        var u = ujian.find(function (x) { return x.kode === s.ujianId; }) ||
                ujian.find(function (x) { return x.id === s.ujianId; });
        h.kode_ujian = u ? u.kode : s.ujianId;
      }
      if (!h.kelas && h.kode_ujian) {
        var un = ujian.find(function (x) { return x.kode === h.kode_ujian; });
        if (un && un.kelas) h.kelas = un.kelas;
      }
    });
    return { ok: true, data: hasil };
  }
  function mockGetUsers() { return { ok: true, data: (loadMock().users || []).slice() }; }
  function mockTambahUser(user) {
    var db = loadMock();
    (db.users || []).push(user);
    saveMock(db);
    return { ok: true };
  }
  function mockHapusUser(username) {
    var db = loadMock();
    if (username === "admin") return { ok: false, error: "Akun admin utama tidak bisa dihapus." };
    var sebelum = (db.users || []).length;
    db.users = (db.users || []).filter(function (u) { return u.username !== username; });
    if (db.users.length === sebelum) return { ok: false, error: "Akun tidak ditemukan." };
    saveMock(db);
    return { ok: true };
  }

  function mockJawaban(payload) {
    var db = loadMock();
    (db.jawaban || []).push(payload);
    saveMock(db);
    return { ok: true };
  }
  function mockSubmitUjian(payload) {
    var db = loadMock();
    var hitung = 0;
    var total = 0;
    var bank = db.bankSoal || [];
    (payload.jawaban || []).forEach(function (j) {
      var s = bank.find(function (b) { return b.id === j.soalId; });
      total++;
      if (s && s.kunci === j.jawaban) hitung++;
    });
    var nilai = total ? Math.round((hitung / total) * 100) : 0;
    db.hasil.push({
      username: payload.username, nis: payload.nis, nama: payload.nama,
      kode_ujian: payload.kode || "", kelas: payload.kelas || "",
      benar: hitung, total: total, nilai: nilai, ts: mockNow()
    });
    var sesi = (db.sesi || []).find(function (s) { return s.username === payload.username; });
    if (sesi) sesi.status = "SELESAI";
    saveMock(db);
    return { ok: true, data: { benar: hitung, total: total, nilai: nilai } };
  }

  function mockHandle(action, payload) {
    switch (action) {
      case "login-admin": return mockLoginAdmin(payload.username, payload.password);
      case "login-siswa": return mockLoginSiswa(payload.username, payload.password, payload.kode);
      case "mulai-ujian": return mockMulaiUjian(payload.username, payload.kode, payload.token);
      case "bank-soal": return mockGetBankSoal();
      case "simpan-soal": return mockSimpanSoal(payload.soal);
      case "hapus-soal": return mockHapusSoal(payload.id);
      case "upload-siswa": return mockUploadSiswa(payload.rows);
      case "buat-ujian": return mockBuatUjian(payload.ujian);
      case "get-ujian": return mockGetUjian();
      case "aktifkan-ujian": return mockAktifkanUjian(payload.id);
      case "selesai-ujian": return mockSelesaiUjian(payload.id);
      case "reset-login": return mockResetLogin(payload.username);
      case "get-progress": return mockGetProgress();
      case "get-hasil": return mockGetHasil();
      case "get-users": return mockGetUsers();
      case "tambah-user": return mockTambahUser(payload.user);
      case "hapus-user": return mockHapusUser(payload.username);
      case "jawaban": return mockJawaban(payload);
      case "submit-ujian": return mockSubmitUjian(payload);
      default: return { ok: false, error: "Aksi tidak dikenal: " + action };
    }
  }

  /* ============ SUPABASE BACKEND (PostgREST RPC) ============ */
  var RPC_MAP = {
    "login-siswa": "rpc_login_siswa",
    "mulai-ujian": "rpc_mulai_ujian",
    "login-admin": "rpc_login_admin",
    "bank-soal": "rpc_bank_soal",
    "simpan-soal": "rpc_simpan_soal",
    "hapus-soal": "rpc_hapus_soal",
    "upload-siswa": "rpc_upload_siswa",
    "get-ujian": "rpc_get_ujian",
    "buat-ujian": "rpc_buat_ujian",
    "aktifkan-ujian": "rpc_aktifkan_ujian",
    "selesai-ujian": "rpc_selesai_ujian",
    "reset-login": "rpc_reset_login",
    "get-progress": "rpc_get_progress",
    "get-hasil": "rpc_get_hasil",
    "get-users": "rpc_get_users",
    "tambah-user": "rpc_tambah_user",
    "hapus-user": "rpc_hapus_user",
    "jawaban": "rpc_jawaban",
    "submit-ujian": "rpc_submit_ujian"
  };

  function supabaseRequest(action, payload) {
    var fn = RPC_MAP[action];
    if (!fn) {
      return Promise.resolve({ ok: false, error: "Aksi tidak dikenal: " + action });
    }
    var body = payload || {};
    body.session_id = AppSession.get() || null;
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () {
        reject(new Error("Waktu habis (server lambat / tidak aktif)."));
      }, AppConfig.REQUEST_TIMEOUT_MS);
      fetch(AppConfig.SUPABASE_URL + "/rest/v1/rpc/" + fn, {
        method: "POST",
        headers: {
          "apikey": AppConfig.SUPABASE_ANON_KEY,
          "Authorization": "Bearer " + AppConfig.SUPABASE_ANON_KEY,
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: JSON.stringify({ p_payload: body })
      }).then(function (res) {
        clearTimeout(t);
        if (!res.ok) {
          return res.text().then(function (txt) {
            var msg = "HTTP " + res.status;
            try { var j = JSON.parse(txt); msg = (j.message || j.error || j.details) || msg; } catch (e) {}
            throw new Error(msg);
          });
        }
        return res.json();
      }).then(function (data) {
        resolve(data);
      }).catch(function (err) {
        clearTimeout(t);
        reject(err);
      });
    });
  }

  /* ============ QUEUE + RETRY (untuk aksi penting) ============ */
  var QUEUE_KEY = "ujian_app_outbox";
  function loadQueue() { try { return JSON.parse(localStorage.getItem(QUEUE_KEY) || "[]"); } catch (e) { return []; } }
  function saveQueue(q) { localStorage.setItem(QUEUE_KEY, JSON.stringify(q)); }

  function flushQueue() {
    var q = loadQueue();
    if (!q.length) return Promise.resolve(null);
    var head = q[0];
    return dispatch(head.action, head.payload, false).then(function (res) {
      saveQueue(loadQueue().slice(1));
      return flushQueue().then(function () { return res; });
    }).catch(function () {
      return Promise.reject(new Error("Antrean masih menunggu koneksi."));
    });
  }

  function dispatch(action, payload, isRetry) {
    if (AppConfig.BACKEND !== "supabase" || !AppConfig.SUPABASE_URL || !AppConfig.SUPABASE_ANON_KEY) {
      return Promise.resolve().then(function () {
        return mockHandle(action, payload); // resolve ok:false -> diproses pemanggil
      });
    }
    return supabaseRequest(action, payload);
  }

  function withRetry(action, payload, attempt) {
    attempt = attempt || 0;
    return dispatch(action, payload).catch(function (err) {
      if (attempt < AppConfig.RETRY_MAX) {
        return new Promise(function (res) { setTimeout(res, AppConfig.RETRY_DELAY_MS); })
          .then(function () { return withRetry(action, payload, attempt + 1); });
      }
      throw err;
    });
  }

  /* ============ PUBLIC API ============ */
  global.AppAPI = {
    initMock: mockInit,
    loadQueue: loadQueue,

    /** Panggil aksi. Penting=true -> antre + retry bila gagal (jawaban, submit). */
    call: function (action, payload, opts) {
      opts = opts || {};
      if (opts.penting && (action === "jawaban" || action === "submit-ujian")) {
        var q = loadQueue();
        q.push({ action: action, payload: payload });
        saveQueue(q);
        return flushQueue();
      }
      return withRetry(action, payload);
    },

    /** Kirim jawaban, aman offline: masuk antrean lalu dikirim berurutan. */
    kirimJawaban: function (payload) {
      return this.call("jawaban", payload, { penting: true });
    },

    flushQueue: flushQueue
  };
})(window);
