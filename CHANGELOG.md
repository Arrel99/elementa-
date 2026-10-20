# Changelog

Format mengikuti Keep a Changelog, versi mengikuti `Net.GAME_VERSION`.

## [0.2.0] - Sesuai Buku Peraturan Elementa

### Diubah (penyesuaian ke buku peraturan)
- **Komposisi deck pasti** 60 kartu = 46 unsur + 14 spell lewat field
  `deck_copies` tiap kartu (sebelumnya acak 44:16). Kartu senyawa tidak masuk deck.
- **Poin kartu** disamakan dengan Lampiran A/B: H1 O1 C2 N2 Na3 Cl3 Ca4 Fe5 Cu5 Ne6;
  H2O6 CO2_7 NH3_8 CH4_8 HCl8 CaO9 NaCl10 CuO10 Fe2O3_11.
- **Fase menarik kartu: 2 kartu** per giliran (sebelumnya 1). Pemain pertama
  tidak menarik pada giliran pertamanya.
- **Batas tangan 8 di akhir giliran**, pemain memilih kartu yang dibuang
  (sebelumnya kartu dibakar otomatis saat tangan penuh).
- **Kondisi menang zona spesial**: dipicu pada **8 dari 10** slot lalu
  **hitungan mundur 3 giliran** untuk kedua pemain (sebelumnya pada 10 slot
  dan lawan mendapat 1 giliran terakhir).
- **Hasil seri** ditentukan oleh jumlah kartu spesial terbanyak, baru kemudian seri.
- **Deck habis** dipicu saat sisa deck kurang dari 2 kartu pada fase menarik.
- **Elektrolisis / Elektrolisis Paksa**: senyawa kembali ke Tabel Senyawa dan
  2 unsur kembali ke **tangan** pemiliknya (bukan ke zona dasar / dibuang).
- **Bilas**: setelah membuang 1 kartu dari zona dasar, tarik 1 kartu baru.
- **Spektrometer**: lihat 3 kartu teratas deck sendiri, ambil 1 ke tangan, lalu
  **deck diacak kembali** (sebelumnya melihat tangan lawan).
- **Perisai Inert**: berlaku sampai awal giliran sendiri berikutnya dan menangkal
  seluruh spell gangguan (sebelumnya sekali pakai).
- **Batas 1 spell per giliran**, kecuali Katalis yang tidak memakai jatah.
- `Net.GAME_VERSION` dinaikkan ke `0.2.0`; hash kartu kini menyertakan `deck_copies`.

### Ditambahkan
- Aksi `discard` (buang kelebihan kartu) dan `spektro` (selesaikan Spektrometer)
  pada protokol host-klien.
- Popup Spektrometer interaktif: pilih 1 dari 3 kartu teratas, lalu deck diacak.
- Validator menolak kartu senyawa berisi `deck_copies` dan memeriksa total deck.
- Uji aturan diperluas menjadi 63 assertion, termasuk jaminan kedua deck
  berisi komposisi kartu yang identik (bagian 3).
- Perubahan spektrometer: deck diacak kembali setelah kartu diambil.

## [0.1.0] - MVP (0% sampai 100% panduan)

### Ditambahkan
- Struktur project Godot 4, autoload `CardDB`, `Net`, `Settings`, `EventLog`.
- `CardData` dan `GameRules` sebagai resource; 26 kartu `.tres`
  (10 dasar, 9 senyawa, 7 spell).
- `GameState` murni: setup, place_base, synthesize, 7 spell, end_turn,
  tiga kondisi menang, `view_for` untuk menyembunyikan informasi.
- UI: `card.tscn`, papan `game.tscn` dengan Tabel Senyawa, pesan error (toast),
  layar hasil, mode uji lokal dua pemain.
- Multiplayer host-authoritative: lobby Host/Join, cek versi + hash kartu,
  penanganan koneksi putus, pewaktu giliran.
- Menu utama, Library tiga tab dengan popup detail, tutorial satu kali,
  Pengaturan volume tersimpan.
- Tool: tes aturan (`test.tscn`), simulasi 2000 game (`simulate.tscn`),
  validator data (`validate_cards.gd`).
- Log JSON per aksi di `user://logs` untuk evaluasi Computational Thinking.

### Diubah dari contoh panduan
- Id kartu memakai `String` (bukan `StringName`) agar aman lewat jaringan
  (bab 6.7 butir 2).
