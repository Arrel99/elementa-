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
  scripts/tools/       test, simulate, validate_cards, assign_art
  scenes/ui/           card, toast, card_detail, reveal_popup
  scenes/screens/      main_menu, lobby, game, library
  scenes/tools/        test, simulate
  art/cards/           ilustrasi kartu (nama file = id kartu)
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

## Aturan (sesuai Buku Peraturan Elementa: Kartu Reaksi)

- Deck 60 kartu per pemain = **46 kartu unsur + 14 spell** (komposisi pasti di
  field `deck_copies` tiap kartu). Kartu senyawa **tidak** masuk deck.
- Batas tangan 8 **di akhir giliran** (pemain memilih kartu yang dibuang),
  zona dasar 6, zona senyawa 10, tangan awal 5.
- **Fase menarik kartu: 2 kartu**; pemain pertama tidak menarik pada giliran
  pertamanya.
- Cooldown sintesis satu giliran; kartu yang baru dipasang baru bisa dipakai
  pada giliran pemiliknya berikutnya.
- **Maksimal 1 spell per giliran**, kecuali Katalis (tidak memakai jatah).
- **Tiga kondisi menang:** menyerah; deck habis (sisa < 2 saat menarik);
  atau zona senyawa menyentuh **8 slot** → hitungan mundur **3 giliran**.
- **Hasil seri** ditentukan jumlah kartu spesial terbanyak; baru kemudian seri.

Semua angka ada di `data/game_rules.tres`.

### 9 senyawa (Lampiran B)

| Senyawa | Resep | Poin |
|---|---|---|
| H₂O — Air | H + O | 6 |
| CO₂ — Karbon dioksida | C + O | 7 |
| NH₃ — Amonia | N + H | 8 |
| CH₄ — Metana | C + H | 8 |
| HCl — Asam klorida | H + Cl | 8 |
| CaO — Kalsium oksida | Ca + O | 9 |
| NaCl — Garam dapur | Na + Cl | 10 |
| CuO — Tembaga oksida | Cu + O | 10 |
| Fe₂O₃ — Besi oksida | Fe + O | 11 |

Kartu senyawa hanya 1 salinan di Tabel Senyawa bersama; sekali diambil, resep itu
tertutup sampai ada yang memecahnya lewat Elektrolisis.

### 7 spell (Lampiran C)

| Spell | Efek |
|---|---|
| Elektrolisis | Pecah senyawa sendiri; senyawa ke Tabel Senyawa, 2 unsur ke tangan |
| Katalis | +1 aksi sintesis; tidak memakai jatah spell |
| Spektrometer | Lihat 3 kartu teratas deck sendiri; ambil 1, lalu deck diacak kembali |
| Bilas | Buang 1 kartu zona dasar sendiri, lalu tarik 1 |
| Korosi | Buang 1 kartu dasar lawan dari zona dasarnya |
| Elektrolisis Paksa | Pecah senyawa lawan; 2 unsur ke tangan lawan |
| Perisai Inert | Kebal spell gangguan lawan sampai awal giliran sendiri berikutnya |

> **Catatan:** semua nilai (poin, jumlah salinan, resep) ada di file `.tres`,
> jadi bisa diubah tanpa menyentuh kode. Efek spell ada di fungsi `_fx_*` pada
> `scripts/core/game_state.gd`.

## Tampilan & ukuran jendela

- Papan digambar pada kanvas tetap **1080 × 1350**, lalu diskalakan otomatis
  oleh `_layout()` di `scripts/screens/game.gd` setiap kali jendela berubah
  ukuran. Tidak ada skala tetap, jadi papan selalu muat dan tidak menabrak HUD.
- Jendela minimal **960 × 600**. Autoload `GameWindow` mengecilkan jendela bila
  layar lebih kecil dari 1920 × 1080 (mis. karena skala tampilan Windows 125%).
- Kartu dan tombol punya efek hover. Kartu mengubah warna border/latar (bukan
  `scale`, karena zona memakai `clip_contents`) dan menampilkan tooltip berisi
  nama + deskripsi kartu.

### Theme global

`themes/elementa.tres` didaftarkan lewat `[gui] theme/custom` di `project.godot`,
jadi berlaku untuk **semua** tombol tanpa `theme_override` di tiap scene:

| Keadaan | Tampilan |
|---|---|
| normal | panel `#1a2733`, garis `#3c5c78`, radius 10 |
| hover | panel lebih terang `#273c4f`, **garis hijau aksen** `#76d399` |
| pressed | isi hijau aksen, teks gelap |
| disabled | panel redup, teks abu |

Sebelum theme ini ada, project sama sekali tidak punya theme: semua tombol memakai
theme bawaan Godot yang hover-nya nyaris tidak terlihat di latar gelap game. Itu
sebabnya hover terasa "tidak pas" walau posisi kursor sebenarnya sudah benar.

Kursor "tangan menunjuk" **tidak bisa** diatur lewat Theme (itu properti per
`Control`), jadi autoload `UiPolish` (`scripts/core/ui_polish.gd`) memasangnya
pada setiap `Button` lewat `node_added` — termasuk tombol yang dibuat dari kode
(pilihan kartu Spektrometer) dan tombol bawaan dialog Godot (OK/Batal) yang tidak
ada di file `.tscn` mana pun.

> [!note] Kalau ingin menambah jenis tombol baru
> Cukup pakai `Button` biasa; theme dan kursor otomatis ikut. Jangan set
> `flat = true`, karena tombol flat tidak menggambar latar normal maupun hover
> sehingga efek hover-nya hilang.

## Multiplayer

Host-authoritative: host menjalankan `GameState`, klien hanya mengirim aksi dan
menerima `view_for()` sehingga isi tangan lawan tidak pernah terkirim.

Alur: host menekan **Buat Room** dan mendapat **kode 4 angka**; tamu memilih
room dari daftar (ditemukan lewat broadcast UDP) atau mengetik kodenya. IP host
hanya dipakai sebagai jalur cadangan.

| Port | Protokol | Fungsi |
|---|---|---|
| 24567 | UDP (ENet) | koneksi game |
| 24568 | UDP | penemuan room (broadcast) |

Keduanya harus diizinkan di Windows Firewall untuk jaringan **Private** pada
kedua komputer. Main lintas internet belum didukung karena masih butuh relay
WebSocket; untuk satu WiFi/hotspot sudah jalan.

## Menambah konten

- **Unsur/senyawa/spell baru** cukup 1 file `.tres` (spell dengan efek baru:
  tambah 1 fungsi `_fx_*` dan 1 baris di tabel `_effects`).
- Naikkan `Net.GAME_VERSION` setiap kali aturan atau kartu berubah agar kedua
  pemain tidak desinkron.

## Lisensi

Lihat `LICENSE`.
