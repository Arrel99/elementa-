extends Node

## Autoload UiPolish: memaksa kursor "tangan menunjuk" pada semua tombol.
##
## Kenapa lewat autoload, bukan theme: warna hover diatur oleh Theme
## (themes/elementa.tres), tetapi properti kursor BUKAN bagian dari Theme --
## ia properti per-Control. Tombol yang dibuat dari kode (pilihan kartu di popup
## Spektrometer) dan tombol bawaan dialog Godot (OK/Batal) tidak ada di file
## .tscn mana pun, jadi tidak bisa diset lewat scene.
##
## node_added dipakai supaya tombol yang muncul belakangan ikut kena tanpa perlu
## menyentuh tiap scene atau memanggil fungsi khusus.

const POINTING_HAND := Control.CURSOR_POINTING_HAND

func _ready() -> void:
	_apply(get_tree().root)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	# Button mencakup CheckBox, CheckButton, OptionButton, dan MenuButton --
	# semuanya bisa diklik, jadi semuanya pantas memakai kursor tangan.
	if node is Button:
		var b := node as Button
		if b.mouse_default_cursor_shape != POINTING_HAND:
			b.mouse_default_cursor_shape = POINTING_HAND

func _apply(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_apply(child)
