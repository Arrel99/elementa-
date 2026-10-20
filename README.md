# Elementa

Game kartu kimia dua pemain di Godot 4, dibangun mengikuti
**Panduan Lengkap Membuat Game Elementa di Godot (0% sampai 100%)**.

Dua pemain menyusun senyawa dari kartu unsur, memainkan spell, dan berebut
poin. Versi ini mencakup seluruh alur MVP dari panduan: logika murni, UI lokal,
7 spell, multiplayer online host-authoritative, menu, Library, dan tooling.

## Menjalankan

1. Buka folder ini sebagai project di **Godot 4.3+** (versi standar, bukan .NET).
2. Tekan **F5** untuk menjalankan `scenes/screens/main_menu.tscn`.
3. Uji aturan tanpa UI: buka `scenes/tools/test.tscn`, tekan **F6**.
4. Simulasi 2000 game (bot acak): `godot --headless res://scenes/tools/simulate.tscn`.
5. Validasi data kartu: buka `scripts/tools/validate_cards.gd` di editor script,
   **File > Run** (Ctrl+Shift+X).

## Struktur

```
res://
  data/cards/          26 file .tres (10 dasar, 9 senyawa, 7 spell)
  data/game_rules.tres aturan dalam data (11.1)
  scripts/core/        card_data, game_rules, card_db, game_state, event_log
  scripts/net/         net (host/join, RPC, cek versi)
  scripts/settings/    settings (volume + bahasa tersimpan)
  scripts/ui/          card_view, card_detail, toast, reveal_popup
  scripts/screens/     main_menu, lobby, game, library
  scripts/tools/       test, simulate, validate_cards
  scenes/ui/           card, toast, card_detail, reveal_popup
  scenes/screens/      main_menu, lobby, game, library
  scenes/tools/        test, simulate
```

Aturan emas: `scripts/core` tidak pernah menyentuh Node/Control/scene, sehingga
logika bisa dites tanpa UI dan dipakai ulang sebagai server.

## Pemetaan ke fase panduan

| Fase | Isi | Lokasi |
|------|-----|--------|
| 1 | Persiapan project | `project.godot`, `.gitignore`, autoload |
| 2 | Data kartu | `data/cards/*.tres`, `card_db.gd`, `card_data.gd` |
| 3 | Logika game murni | `game_state.gd`, `test.gd`, `simulate.gd` |
| 4 | UI papan mode lokal | `scenes/screens/game.tscn`, `game.gd` |
| 5 | Spell dan efek | `game_state.gd` bagian efek, `reveal_popup` |
| 6 | Multiplayer online | `net.gd`, `lobby.gd`, bagian RPC `game.gd` |
| 7 | Menu, Library, audio, polish | `main_menu.gd`, `library.gd`, `settings.gd` |
| 8 | Playtest, perbaikan, export | `validate_cards.gd`, `simulate.gd`, README |

## Aturan (sesuai contoh panduan, mudah diubah)

- Batas tangan 8, zona dasar 6, slot senyawa 10, deck 60 (44 dasar : 16 spell),
  tangan awal 5. Semua di `data/game_rules.tres`.
- Menang: menyerah, deck habis (dihitung poin), atau slot senyawa penuh lalu
  lawan mendapat satu giliran terakhir.
- Cooldown sintesis satu giliran; pasang kartu dasar lalu tunggu sebelum bisa
  dipakai sintesis.
- Jika tangan sudah penuh saat harus menarik kartu, kartu itu dibakar ke
  tumpukan buang. Ini menjaga deck tetap menyusut sehingga kondisi "deck habis"
  pasti tercapai dan game tidak bisa buntu (aturan ini bisa kamu ubah di
  `GameState.draw`).

### 9 resep senyawa contoh

H2O (H+O), CO2 (C+O), NaCl (Na+Cl), NH3 (N+H), CH4 (C+H), CaO (Ca+O),
CuO (Cu+O), Fe2O3 (Fe+O), HCl (H+Cl).

### 7 spell

Elektrolisis, Katalis, Spektrometer, Bilas, Korosi, Elektrolisis Paksa,
Perisai Inert.

> **Catatan dari panduan:** nama kartu, resep, dan efek spell di sini adalah
> contoh. Cocokkan dengan Buku Peraturan Elementa milikmu dengan mengedit file
> `.tres` (tanpa menyentuh kode) dan fungsi `_fx_*` di `game_state.gd`.

## Multiplayer

Host-authoritative: host menjalankan `GameState`, klien hanya mengirim aksi dan
menerima `view_for()` sehingga isi tangan lawan tidak pernah terkirim.
Port UDP 24567. Untuk main lewat internet, gunakan Tailscale/ZeroTier (tanpa
ubah kode) atau port forwarding (sering gagal di CGNAT).

## Menambah konten

- **Unsur/senyawa/spell baru** cukup 1 file `.tres` (spell dengan efek baru:
  tambah 1 fungsi `_fx_*` dan 1 baris di tabel `_effects`).
- Naikkan `Net.GAME_VERSION` setiap kali aturan atau kartu berubah agar kedua
  pemain tidak desinkron.

## Lisensi

Lihat `LICENSE`.
