# Setup Backend Google Apps Script (GAS)

Frontend berjalan mandiri dalam **mode demo** selama `API_ENDPOINT` kosong.
Untuk penyimpanan nyata ke Google Sheets, ikuti langkah berikut.

## 1. Buat Spreadsheet

Buka Google Sheets baru → catat nama tab default (Sheet1 tidak dipakai, akan dibuat otomatis).

## 2. Tempel Code.gs

1. Di Spreadsheet: **Extensions → Apps Script**.
2. Hapus konten default, tempel isi `apps-script/Code.gs`.
3. Simpan (beri nama project, mis. "UjianMatematika").

## 3. Jalankan setup sekali

Di editor Apps Script, pilih fungsi `setupSpreadsheet` lalu klik **Run**.
Izinkan akses saat diminta (pertama kali saja).

Ini membuat semua tab: `Users`, `SoalBank`, `Ujian`, `SoalUjian`, `KodeUjian`, `Sesi`, `Jawaban`, `Hasil`, `Config`.

## 4. Konfigurasi akun admin

Buka Spreadsheet → tab **Config**:

| key | value |
|---|---|
| `adminUser` | `admin` |
| `adminPassword` | (password admin, mis. `admin123`) |

Atau tambahkan akun guru via tab **Users** dengan kolom `username, passHash, role, aktif`
(role = `guru`/`admin`). Catatan: pada implementasi saat ini `passHash` bisa diisi teks
biasa; untuk produksi ganti dengan `hash_()` di Code.gs.

## 5. Deploy sebagai Web App

1. Di Apps Script: **Deploy → New deployment**.
2. Pilih type **Web app**.
   - **Execute as:** *Me*
   - **Who has access:** *Anyone*
3. Deploy → salin **Web app URL** (format: `https://script.google.com/macros/s/.../exec`).

## 6. Hubungkan frontend

Edit `js/config.js`:

```js
API_ENDPOINT: "https://script.google.com/macros/s/XXXX/exec",
MOCK_MODE: false,
```

Setiap kali **mengubah kode** di Apps Script, klik **Deploy → Manage deployments →
Edit (pensil) → Version: New version → Deploy** agar URL tetap sama tapi menjalankan kode terbaru.

## 7. Unggah halaman ke hosting statis

Frontend murni statis, bisa di-host gratis:
- **GitHub Pages** (lihat pola di memory project sebelumnya), Netlify, Vercel, atau Google Cloud Storage.
- Pastikan CDN (KaTeX, JSZip, SheetJS) bisa diakses dari jaringan siswa.

## Kuota & catatan

- Kuota gratis Apps Script: ~20rb eksekusi/hari — cukup untuk <60 siswa.
- CORS sudah ditangani web app (bisa dipanggil dari origin mana pun).
- Kunci jawaban & password **tidak pernah** berada di frontend; scoring server-side.
- Untuk produksi yang lebih ketat, ganti `passHash` plain dengan `hash_()` + salt,
  dan tambahkan rate-limit login admin.
