/* ============================================================
 * config.js — Konfigurasi pusat aplikasi
 * ------------------------------------------------------------
 * Satu-satunya tempat untuk:
 *   - Backend (mode mock / Supabase)
 *   - Feature flags (tambah/kurangi fitur cukup set true/false)
 *   - Pengaturan ujian default
 *
 * BACKEND:
 *   "mock"     = demo tanpa backend, data di localStorage browser.
 *   "supabase" = backend nyata Postgres via Supabase.
 *                (lihat docs/SETUP-SUPABASE.md)
 *   Lalu isi SUPABASE_URL + SUPABASE_ANON_KEY (public) dari project.
 * ============================================================ */
var AppConfig = {
  APP_NAME: "Ujian Tes Kompetensi Akademik",

  /* ---------------- BACKEND ---------------- */
  BACKEND: "supabase",        // "mock" | "supabase"
  SUPABASE_URL: "https://pufdbmbwqkjhsxwagabl.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB1ZmRibWJ3cWtqaHN4d2FnYWJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYzNjc1ODgsImV4cCI6MjEwMTk0MzU4OH0.2yWiO3buFZDmoafXUBWxFK4w7jFDhPGzKj9j2Bt2Z30",      // anon public key dari project Supabase
  REQUEST_TIMEOUT_MS: 25000,
  RETRY_MAX: 3,               // retry pengiriman jawaban saat gagal jaringan
  RETRY_DELAY_MS: 1500,

  /* ---------------- FEATURE FLAGS ---------------- */
  FEATURES: {
    antiLoginGanda: true,      // siswa hanya 1 sesi aktif, reset oleh admin
    bankSoal: true,            // bank soal + preview sebelum diujikan
    uploadDocx: true,          // upload soal .docx (OMML->LaTeX)
    uploadXlsx: true,          // upload data siswa .xlsx
    editSoalBlock: true,       // edit soal inline block-based editor
    gambarPersamaan: true,     // ganti persamaan dengan upload gambar
    tambahSoalManual: true,    // tambah soal manual satu per satu
    buatUjian: true,           // pilih soal bank -> ujian
    nilaiAkhirSaja: true,      // siswa tidak dapat feedback per soal
    adminTambahUser: true,     // admin menambah akun guru
    dataSiswa: true,           // tab Data Siswa di guru & admin (filter kelas + pencarian)
    generateKartuSiswa: true,  // admin generate kartu siswa dengan password otomatis
    mintaResetSiswa: true,     // siswa minta reset login via popup -> antrean tab Reset Siswa admin
    monitorLive: true,         // admin melihat progress live
    resetLoginAdmin: true      // admin mereset login siswa
  },

  /* ---------------- UJIAN DEFAULT ---------------- */
  EXAM: {
    opsiLabel: ["A", "B", "C", "D", "E"],
    defaultDurasiMenit: 90,
    maxOpsi: 5,
    autoSubmitSaatWaktuHabis: true
  },

  /* ---------------- IDENTITAS / SKIN ---------------- */
  THEME: {
    primary: "#2563eb",
    primaryDark: "#1d4ed8",
    bg: "#f1f5f9",
    card: "#ffffff"
  },

};

/* Feature flag helper */
AppConfig.has = function (name) {
  return !!(this.FEATURES && this.FEATURES[name]);
};
