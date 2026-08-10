/* ============================================================
 * auth.js — Manajemen sesi lokal (browser)
 * ------------------------------------------------------------
 * - Menyimpan sessionId, role, dan identitas login saat ini
 * - Reload halaman = tetap masuk (bukan login ganda)
 * - Anti login-ganda ditegakkan server-side (Sesi sheet)
 * ============================================================ */
(function (global) {
  "use strict";
  var KEY = "ujian_app_session";
  var KEY_IDENT = "ujian_app_ident";

  global.AppSession = {
    save: function (s) { localStorage.setItem(KEY, JSON.stringify(s)); },
    get: function () {
      try { var s = JSON.parse(localStorage.getItem(KEY) || "null"); return s ? s.sessionId : null; }
      catch (e) { return null; }
    },
    data: function () {
      try { return JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) { return null; }
    },
    clear: function () { localStorage.removeItem(KEY); },

    /** identitas siswa yang sedang login */
    simpanIdentitasSiswa: function (siswa) {
      localStorage.setItem(KEY_IDENT, JSON.stringify(siswa));
    },
    identitasSiswa: function () {
      try { return JSON.parse(localStorage.getItem(KEY_IDENT) || "null"); } catch (e) { return null; }
    },
    hapusIdentitasSiswa: function () { localStorage.removeItem(KEY_IDENT); },

    /** guard untuk halaman guru/admin */
    requireRole: function (role) {
      var s = this.data();
      if (!s || s.role !== role) {
        location.href = role === "admin" ? "admin.html" : "guru.html";
        return false;
      }
      return true;
    }
  };
})(window);
