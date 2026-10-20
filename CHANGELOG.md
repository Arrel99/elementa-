# Changelog

Format mengikuti Keep a Changelog, versi mengikuti `Net.GAME_VERSION`.

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
- Saat tangan penuh, kartu yang ditarik dibakar ke tumpukan buang supaya deck
  menyusut dan game selalu bisa selesai (menghindari kondisi buntu).
