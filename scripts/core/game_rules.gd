class_name GameRules
extends Resource

## Semua angka aturan di satu tempat (bab 11.1).
## Ubah di res://data/game_rules.tres tanpa menyentuh kode.

@export var hand_max := 8
@export var base_max := 6
@export var special_max := 10
@export var deck_size := 60
@export var start_hand := 5
@export var basic_share := 0.73   # porsi kartu dasar di deck, sisanya spell
