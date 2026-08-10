/* ============================================================
 * Code.gs — Backend Google Apps Script (Web App)
 * ============================================================
 * CARA SETUP (1x):
 *   1. Buat Google Spreadsheet baru.
 *   2. Extensions → Apps Script → tempel file ini (Code.gs).
 *   3. Jalankan sekali fungsi setupSpreadsheet() dari editor
 *      (Memberikan izin pertama kali).
 *   4. Deploy → New deployment → Type: Web app
 *        - Execute as: Me
 *        - Who has access: Anyone
 *   5. Salin URL web app → isi ke js/config.js (API_ENDPOINT)
 *      dan set MOCK_MODE = false.
 *
 * Detail lengkap: docs/SETUP-GAS.md
 * ============================================================ */

var SHEET_NAME = {
  Users: "Users",
  SoalBank: "SoalBank",
  Ujian: "Ujian",
  SoalUjian: "SoalUjian",
  KodeUjian: "KodeUjian",
  Sesi: "Sesi",
  Jawaban: "Jawaban",
  Hasil: "Hasil",
  Config: "Config"
};

var SS = null;

function getSS_() {
  if (!SS) SS = SpreadsheetApp.getActiveSpreadsheet();
  return SS;
}

function sheet_(name) {
  var ss = getSS_();
  var sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.appendRow(header_(name));
  }
  return sh;
}

function header_(name) {
  switch (name) {
    case SHEET_NAME.Users: return ["username", "passHash", "role", "aktif"];
    case SHEET_NAME.SoalBank: return ["id", "mapel", "kelas", "topik", "kode", "blocksJson", "opsiJson", "kunci", "pembahasan", "status", "uploader", "created"];
    case SHEET_NAME.Ujian: return ["id", "nama", "kode", "mapel", "kelas", "durasiMenit", "soalIdsJson", "status", "token", "created"];
    case SHEET_NAME.SoalUjian: return ["ujianId", "soalId", "urutan"];
    case SHEET_NAME.KodeUjian: return ["username", "password", "nis", "nama", "kelas", "ujianId", "status"];
    case SHEET_NAME.Sesi: return ["username", "nis", "status", "login_ts", "fingerprint"];
    case SHEET_NAME.Jawaban: return ["username", "nis", "soalId", "jawaban", "ts"];
    case SHEET_NAME.Hasil: return ["username", "nis", "nama", "benar", "total", "nilai", "ts"];
    case SHEET_NAME.Config: return ["key", "value"];
    default: return [];
  }
}

/* ============================================================
 * SETUP — jalankan sekali dari editor untuk membuat semua sheet
 * ============================================================ */
function setupSpreadsheet() {
  Object.keys(SHEET_NAME).forEach(function (k) { sheet_(SHEET_NAME[k]); });
  var c = sheet_(SHEET_NAME.Config);
  if (!getRows_(c).length) {
    c.appendRow(["adminPassword", "ubahSaya"]);
    c.appendRow(["adminUser", "admin"]);
  }
  return "Setup selesai. Isi Config sheet (adminUser/adminPassword), lalu Deploy sebagai Web App.";
}

/* ============================================================
 * WEB APP ENTRY
 * ============================================================ */
function doPost(e) {
  return handleRequest_(e, "POST");
}
function doGet(e) {
  return handleRequest_(e, "GET");
}

function handleRequest_(e, method) {
  var lock = LockService.getScriptLock();
  lock.tryLock(15000);
  try {
    var body;
    if (method === "POST" && e && e.postData) {
      try { body = JSON.parse(e.postData.contents); }
      catch (err) { body = JSON.parse(e.postData.contents.replace(/^.*?\{(.*)\}$/, "{$1}")); }
    }
    if (!body) return json_({ ok: false, error: "Payload kosong" });
    var action = body.action;
    var payload = body.payload || {};
    var sessionId = body.sessionId || null;
    var result = route_(action, payload, sessionId);
    return json_(result);
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    if (lock.hasLock()) lock.releaseLock();
  }
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/* ============================================================
 * ROUTING
 * ============================================================ */
function route_(action, payload, sessionId) {
  switch (action) {
    // Publik (siswa)
    case "login-siswa": return loginSiswa_(payload);
    case "mulai-ujian": return mulaiUjian_(payload);
    case "get-ujian": return listUjian_(payload, null);
    case "bank-soal": return listBankSoal_(payload, null, sessionId);
    case "jawaban": return simpanJawaban_(payload, sessionId);
    case "submit-ujian": return submitUjian_(payload, sessionId);

    // Guru / Admin (harus login)
    case "login-admin": return loginStaf_(payload);
    case "simpan-soal": return simpanSoal_(payload, sessionId);
    case "hapus-soal": return hapusSoal_(payload, sessionId);
    case "upload-siswa": return uploadSiswa_(payload, sessionId);
    case "buat-ujian": return buatUjian_(payload, sessionId);
    case "get-hasil": return listHasil_(payload, sessionId);

    // Admin saja
    case "aktifkan-ujian": return aktifkanUjian_(payload, sessionId);
    case "selesai-ujian": return selesaiUjian_(payload, sessionId);
    case "reset-login": return resetLogin_(payload, sessionId);
    case "get-progress": return listSesi_(payload, sessionId);
    case "get-users": return listUsers_(payload, sessionId);
    case "tambah-user": return tambahUser_(payload, sessionId);

    default: return { ok: false, error: "Aksi tidak dikenal: " + action };
  }
}

/* ============================================================
 * HELPERS SHEET
 * ============================================================ */
function getRows_(sh) {
  var vals = sh.getDataRange().getValues();
  if (!vals.length) return [];
  return vals.slice(1).filter(function (r) { return r.some(function (c) { return c !== ""; }); });
}

function requireStaf_(sessionId, role) {
  var s = getRows_(sheet_(SHEET_NAME.Sesi));
  // Sesi staf disimpan di Config-style sederhana; di sini kita pakai
  // pendekatan: sessionId = username untuk demo sederhana di server.
  // NOTE: untuk produksi, gunakan store sesi terpisah dengan expiry.
  return { ok: true };
}

/* ============================================================
 * AUTH
 * ============================================================ */
function hash_(str) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, String(str))
    .map(function (b) { return ("0" + ((b + 256) % 256).toString(16)).slice(-2); }).join("");
}

function loginStaf_(payload) {
  var user = String(payload.username || "").trim();
  var pass = String(payload.password || "");
  var users = getRows_(sheet_(SHEET_NAME.Users));
  var found = users.find(function (r) {
    return r[0] === user && (r[1] === pass || r[1] === hash_(pass));
  });
  if (!found) return { ok: false, error: "Username atau password salah" };
  if (!found[3]) return { ok: false, error: "Akun nonaktif" };
  var role = found[2];
  return { ok: true, data: { role: role, username: user, sessionId: "s-" + hash_(user + Date.now()).slice(0, 12) } };
}

function loginSiswa_(payload) {
  var username = String(payload.username || "").trim();
  var password = String(payload.password || "");
  var kode = String(payload.kode || "").trim();
  if (!username || !password) return { ok: false, error: "Isi username dan password." };
  var kodeRows = getRows_(sheet_(SHEET_NAME.KodeUjian));
  var siswa = kodeRows.find(function (r) {
    return String(r[0]).trim() === username && String(r[1]) === password;
  });
  if (!siswa) return { ok: false, error: "Username atau password salah." };

  var ujian = getRows_(sheet_(SHEET_NAME.Ujian)).find(function (r) {
    return String(r[2]).trim() === kode; // kolom 2 = kode ujian
  });
  if (!kode || !ujian) return { ok: false, error: "Kode ujian tidak terdeteksi. Periksa kembali." };
  if (String(ujian[7]).trim() !== "aktif") {
    return { ok: false, error: "Ujian belum diaktifkan admin. Hubungi pengawas." };
  }

  return {
    ok: true,
    data: {
      siswa: { username: username, nis: siswa[2], nama: siswa[3], kelas: siswa[4] },
      ujian: { id: ujian[0], kode: ujian[2], nama: ujian[1] }
    }
  };
}

function mulaiUjian_(payload) {
  var username = String(payload.username || "").trim();
  var kode = String(payload.kode || "").trim();
  var token = String(payload.token || "").trim();
  var kodeRows = getRows_(sheet_(SHEET_NAME.KodeUjian));
  var siswa = kodeRows.find(function (r) { return String(r[0]).trim() === username; });
  if (!siswa) return { ok: false, error: "Siswa tidak terdaftar." };

  var ujian = getRows_(sheet_(SHEET_NAME.Ujian)).find(function (r) {
    return String(r[2]).trim() === kode;
  });
  if (!ujian) return { ok: false, error: "Kode ujian tidak terdeteksi." };
  if (String(ujian[7]).trim() !== "aktif") return { ok: false, error: "Ujian belum diaktifkan admin." };
  if (String(ujian[8]).trim() !== token) return { ok: false, error: "Token salah. Periksa kembali." };

  var sesiSh = sheet_(SHEET_NAME.Sesi);
  var sesi = getRows_(sesiSh).find(function (r) { return String(r[0]) === username; });
  if (sesi && String(sesi[2]) === "ACTIVE") {
    return { ok: false, error: "Akun sudah dipakai di perangkat lain. Hubungi admin untuk reset." };
  }
  if (sesi && String(sesi[2]) === "SELESAI") {
    return { ok: false, error: "Anda sudah mengumpulkan ujian." };
  }

  var data = [username, siswa[2], "ACTIVE", new Date().toISOString(), String(payload.fingerprint || "")];
  if (sesi) {
    var idx = getRowIndex_(sesiSh, 0, username);
    sesiSh.getRange(idx + 1, 3, 1, 3).setValues([["ACTIVE", data[3], data[4]]]);
  } else {
    sesiSh.appendRow(data);
  }
  return {
    ok: true,
    data: {
      sessionId: "s-" + hash_(username + Date.now()).slice(0, 12),
      siswa: { username: username, nis: siswa[2], nama: siswa[3], kelas: siswa[4] },
      ujian: { id: ujian[0], kode: ujian[2], nama: ujian[1], durasiMenit: ujian[5], soalIds: safeParse_(ujian[6]) }
    }
  };
}

function getRowIndex_(sh, colIdx, val) {
  var vals = sh.getDataRange().getValues();
  for (var i = 1; i < vals.length; i++) {
    if (String(vals[i][colIdx]) === val) return i;
  }
  return -1;
}

/* ============================================================
 * BANK SOAL
 * ============================================================ */
function listBankSoal_(payload, sessionId, actualSession) {
  var rows = getRows_(sheet_(SHEET_NAME.SoalBank));
  var out = rows.map(function (r) {
    return {
      id: r[0], mapel: r[1], kelas: r[2], topik: r[3], kode: r[4],
      blocks: safeParse_(r[5]), opsi: safeParse_(r[6]),
      kunci: r[7], pembahasan: r[8], status: r[9], uploader: r[10]
    };
  });
  return { ok: true, data: out };
}

function simpanSoal_(payload, sessionId) {
  var s = payload.soal || {};
  if (!s.blocks) return { ok: false, error: "Soal tidak valid (blocks kosong)" };
  var id = s.id || ("S-" + new Date().getTime().toString(36).toUpperCase());
  var sh = sheet_(SHEET_NAME.SoalBank);
  var idx = getRowIndex_(sh, 0, id);
  var row = [
    id, s.mapel || "", s.kelas || "", s.topik || "", s.kode || "",
    JSON.stringify(s.blocks || []), JSON.stringify(s.opsi || []),
    s.kunci || "", s.pembahasan || "", s.status || "draft",
    s.uploader || "", new Date().toISOString()
  ];
  if (idx >= 0) sh.getRange(idx + 1, 1, 1, row.length).setValues([row]);
  else sh.appendRow(row);
  return { ok: true, data: { id: id } };
}

function hapusSoal_(payload, sessionId) {
  var sh = sheet_(SHEET_NAME.SoalBank);
  var idx = getRowIndex_(sh, 0, payload.id);
  if (idx >= 0) sh.deleteRow(idx + 1);
  return { ok: true };
}

/* ============================================================
 * UPLOAD SISWA → DAFTAR AKUN (username/password)
 * ============================================================ */
function uploadSiswa_(payload, sessionId) {
  var rows = payload.rows || [];
  var sh = sheet_(SHEET_NAME.KodeUjian);
  var usernames = [];
  rows.forEach(function (r) {
    var username = String(r.username || r.nis || "").trim();
    if (!username) username = "siswa" + Math.floor(Math.random() * 100000);
    sh.appendRow([username, String(r.password || ""), r.nis || "", r.nama || "", r.kelas || "", r.ujianId || "", "belum"]);
    usernames.push(username);
  });
  return { ok: true, data: { total: rows.length, usernames: usernames } };
}

/* ============================================================
 * UJIAN
 * ============================================================ */
function randomToken_() {
  var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  var out = "";
  for (var i = 0; i < 8; i++) out += chars[Math.floor(Math.random() * chars.length)];
  return out;
}

function listUjian_(payload, sessionId) {
  var rows = getRows_(sheet_(SHEET_NAME.Ujian));
  var out = rows.map(function (r) {
    return {
      id: r[0], nama: r[1], kode: r[2], mapel: r[3], kelas: r[4],
      durasiMenit: r[5], soalIds: safeParse_(r[6]), status: r[7], token: r[8]
    };
  });
  return { ok: true, data: out };
}

function buatUjian_(payload, sessionId) {
  var u = payload.ujian || {};
  if (!u.soalIds || !u.soalIds.length) return { ok: false, error: "Pilih minimal 1 soal" };
  var id = "U-" + new Date().getTime().toString(36).toUpperCase();
  sheet_(SHEET_NAME.Ujian).appendRow([
    id, u.nama || "Ujian", u.kode || "", u.mapel || "", u.kelas || "",
    u.durasiMenit || 60, JSON.stringify(u.soalIds), "draft", "", new Date().toISOString()
  ]);
  var su = sheet_(SHEET_NAME.SoalUjian);
  u.soalIds.forEach(function (sid, i) { su.appendRow([id, sid, i + 1]); });
  return { ok: true, data: { id: id, kode: u.kode, status: "draft" } };
}

function aktifkanUjian_(payload, sessionId) {
  var sh = sheet_(SHEET_NAME.Ujian);
  var rows = sh.getDataRange().getValues();
  var idx = -1;
  for (var i = 1; i < rows.length; i++) {
    if (String(rows[i][0]) === String(payload.id)) { idx = i; break; }
  }
  if (idx < 0) return { ok: false, error: "Ujian tidak ditemukan." };
  var token = String(rows[idx][8] || "");
  if (!token) {
    token = "TKN-" + randomToken_();
    sh.getRange(idx + 1, 9).setValue(token);
  }
  sh.getRange(idx + 1, 8).setValue("aktif");
  return { ok: true, data: { id: payload.id, token: token, status: "aktif" } };
}

function selesaiUjian_(payload, sessionId) {
  var sh = sheet_(SHEET_NAME.Ujian);
  var idx = getRowIndex_(sh, 0, payload.id);
  if (idx < 0) return { ok: false, error: "Ujian tidak ditemukan." };
  sh.getRange(idx + 1, 8).setValue("draft");
  return { ok: true, data: { id: payload.id, status: "draft" } };
}

/* ============================================================
 * JAWABAN & SUBMIT
 * ============================================================ */
function simpanJawaban_(payload, sessionId) {
  if (!payload.soalId) return { ok: false, error: "soalId kosong" };
  sheet_(SHEET_NAME.Jawaban).appendRow([
    payload.username || "", payload.nis || "", payload.soalId,
    payload.jawaban || "", payload.ts || new Date().toISOString()
  ]);
  return { ok: true };
}

function submitUjian_(payload, sessionId) {
  var username = payload.username || "";
  var bank = getRows_(sheet_(SHEET_NAME.SoalBank));
  var kunciMap = {};
  bank.forEach(function (r) { kunciMap[r[0]] = r[6]; });

  var benar = 0, total = 0;
  (payload.jawaban || []).forEach(function (j) {
    total++;
    if (j.jawaban && kunciMap[j.soalId] === j.jawaban) benar++;
  });
  var nilai = total ? Math.round((benar / total) * 100) : 0;

  sheet_(SHEET_NAME.Hasil).appendRow([
    username, payload.nis || "", payload.nama || "", benar, total, nilai, new Date().toISOString()
  ]);
  var sesiSh = sheet_(SHEET_NAME.Sesi);
  var idx = getRowIndex_(sesiSh, 0, username);
  if (idx >= 0) sesiSh.getRange(idx + 1, 3).setValue("SELESAI");

  return { ok: true, data: { benar: benar, total: total, nilai: nilai, kosong: total - benar } };
}

/* ============================================================
 * ADMIN
 * ============================================================ */
function listSesi_(payload, sessionId) {
  var rows = getRows_(sheet_(SHEET_NAME.Sesi));
  return { ok: true, data: rows.map(function (r) {
    return { username: r[0], nis: r[1], status: r[2], login_ts: r[3], fingerprint: r[4] };
  }) };
}

function resetLogin_(payload, sessionId) {
  var sesiSh = sheet_(SHEET_NAME.Sesi);
  var idx = getRowIndex_(sesiSh, 0, payload.username);
  if (idx >= 0) sesiSh.getRange(idx + 1, 3).setValue("INACTIVE");
  return { ok: true };
}

function listHasil_(payload, sessionId) {
  var rows = getRows_(sheet_(SHEET_NAME.Hasil));
  return { ok: true, data: rows.map(function (r) {
    return { username: r[0], nis: r[1], nama: r[2], benar: r[3], total: r[4], nilai: r[5], ts: r[6] };
  }) };
}

function listUsers_(payload, sessionId) {
  var rows = getRows_(sheet_(SHEET_NAME.Users));
  return { ok: true, data: rows.map(function (r) {
    return { username: r[0], passHash: r[1], role: r[2], aktif: r[3] };
  }) };
}

function tambahUser_(payload, sessionId) {
  var u = payload.user || {};
  if (!u.username || !u.passHash) return { ok: false, error: "Username/password kosong" };
  var users = getRows_(sheet_(SHEET_NAME.Users));
  if (users.some(function (r) { return r[0] === u.username; })) {
    return { ok: false, error: "Username sudah ada" };
  }
  sheet_(SHEET_NAME.Users).appendRow([u.username, u.passHash, u.role || "guru", u.aktif !== false]);
  return { ok: true };
}

/* ============================================================
 * UTIL
 * ============================================================ */
function safeParse_(json) {
  if (!json) return [];
  try { var v = JSON.parse(json); return Array.isArray(v) ? v : []; }
  catch (e) { return []; }
}
