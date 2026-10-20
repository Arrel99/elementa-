class_name GameRules
extends Resource

## Semua angka aturan di satu tempat (Buku Peraturan Elementa: Kartu Reaksi).
## Ubah di res://data/game_rules.tres tanpa menyentuh kode.

@export var hand_max := 8               # batas tangan di akhir giliran (bagian 4)
@export var base_max := 6               # slot zona kartu dasar (bagian 4)
@export var special_max := 10           # slot zona kartu spesial (bagian 4)
@export var start_hand := 5             # tangan awal (bagian 5)
@export var draw_per_turn := 2          # kartu yang ditarik tiap fase menarik (bagian 6)
@export var deck_size := 60             # total kartu per deck (bagian 3, Lampiran A & C)
@export var special_win_threshold := 8  # slot terisi yang memicu hitungan mundur (bagian 9)
@export var special_win_countdown := 3  # panjang hitungan mundur dalam giliran (bagian 9)
