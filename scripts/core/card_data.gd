class_name CardData
extends Resource

## Data satu kartu. Semua poin, resep, dan efek disimpan di sini
## supaya balancing cukup mengedit file .tres, bukan kode.

enum Type { BASIC, SPECIAL, SPELL }

@export var id: String = ""                 # contoh: "H", "H2O", "katalis"
@export var display_name: String = ""
@export var type: Type = Type.BASIC
@export var points: int = 0                 # kartu dasar dan spesial
@export var symbol: String = ""             # H, O, Na ...
@export var atomic_number: int = 0
@export var recipe: Array[String] = []       # khusus SPECIAL: 2 id kartu dasar
@export var spell_effect: String = ""        # khusus SPELL
@export_multiline var description: String = ""
@export var art: Texture2D

# Tambahan dari bab 11.1
@export var in_deck: bool = true             # matikan kartu tanpa menghapusnya
@export var weight: int = 1                  # bobot kemunculan di deck
@export var set_id: String = "dasar"         # pengelompokan ekspansi
@export_multiline var ct_note: String = ""   # catatan Computational Thinking
