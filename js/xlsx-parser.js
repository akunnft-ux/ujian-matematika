/* ============================================================
 * xlsx-parser.js — Parser data siswa dari .xlsx
 * ------------------------------------------------------------
 * Memakai SheetJS (xlsx) via CDN.
 * Mapping kolom fleksibel:
 *   - "nis"/"nip"/"no induk"     → NIS
 *   - "nama"                     → nama
 *   - "kelas"                    → kelas
 *   - "username"/"user"          → username
 *   - "password"                 → password
 *   - "kode ujian"/"kode soal"   → ujianId (kode ujian)
 * Baris pertama diasumsikan header. Baris tanpa nama diabaikan.
 * ============================================================ */
(function (global) {
  "use strict";

  function normalizeHeader(h) {
    return String(h || "").toLowerCase().replace(/\s+/g, " ").trim();
  }

  global.XlsxParser = {
    parse: function (file) {
      return new Promise(function (resolve, reject) {
        if (typeof XLSX === "undefined") {
          reject(new Error("Library SheetJS belum dimuat.")); return;
        }
        var rd = new FileReader();
        rd.onload = function (e) {
          try {
            var wb = XLSX.read(e.target.result, { type: "array" });
            var sheet = wb.Sheets[wb.SheetNames[0]];
            var rows = XLSX.utils.sheet_to_json(sheet, { header: 1 });
            var out = [];
            if (rows.length < 2) { resolve(out); return; }
            var header = rows[0].map(normalizeHeader);
            var idxNis = header.findIndex(function (h) {
              return /nis|nip|induk|^id/.test(h);
            });
            var idxNama = header.findIndex(function (h) { return /^nama|siswa|murid/.test(h); });
            var idxKelas = header.findIndex(function (h) { return /kelas|rombel|^rom/.test(h); });
            var idxUsername = header.findIndex(function (h) { return /username|^user/.test(h); });
            var idxPassword = header.findIndex(function (h) { return /^password|^pass/.test(h); });
            var idxUjian = header.findIndex(function (h) { return /kode\s*(ujian|soal)?$/.test(h) || /^kode\s*ujian/.test(h); });
            if (idxNama < 0) { reject(new Error("Kolom 'Nama' tidak ditemukan.")); return; }

            for (var i = 1; i < rows.length; i++) {
              var r = rows[i];
              if (!r) continue;
              var nama = (r[idxNama] != null ? String(r[idxNama]).trim() : "");
              if (!nama) continue;
              var username = idxUsername >= 0 && r[idxUsername] != null ? String(r[idxUsername]).trim() : "";
              var password = idxPassword >= 0 && r[idxPassword] != null ? String(r[idxPassword]).trim() : "";
              var ujianId = idxUjian >= 0 && r[idxUjian] != null ? String(r[idxUjian]).trim() : "";
              if (!username) username = (idxNis >= 0 && r[idxNis] != null ? String(r[idxNis]).trim() : "") || nama;
              out.push({
                nis: idxNis >= 0 ? (r[idxNis] != null ? String(r[idxNis]).trim() : "") : "",
                nama: nama,
                kelas: idxKelas >= 0 && r[idxKelas] != null ? String(r[idxKelas]).trim() : "",
                username: username,
                password: password,
                ujianId: ujianId
              });
            }
            resolve(out);
          } catch (err) {
            reject(new Error("Gagal membaca .xlsx: " + err.message));
          }
        };
        rd.onerror = function () { reject(new Error("Gagal membaca file.")); };
        rd.readAsArrayBuffer(file);
      });
    }
  };
})(window);
