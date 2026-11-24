extends Control

## Layar pemilihan level AI (Easy, Normal, Hard, Extreme) bergaya Main Menu
## dengan 4 kartu punggung deck (Card Back) berwarna Hijau, Biru, Merah, Merah Gelap.

const CARD_BACK_SCRIPT := preload("res://scripts/ui/card_back_art.gd")

const DECK_TIERS := [
	{
		"id": "easy",
		"title": "EASY",
		"tag": "Santai",
		"base": Color(0.10, 0.26, 0.18, 1.0),      # Hijau
		"accent": Color(0.34, 0.78, 0.52, 1.0),
	},
	{
		"id": "normal",
		"title": "NORMAL",
		"tag": "Seimbang",
		"base": Color(0.11, 0.21, 0.35, 1.0),      # Biru
		"accent": Color(0.38, 0.68, 0.92, 1.0),
	},
	{
		"id": "hard",
		"title": "HARD",
		"tag": "Agresif",
		"base": Color(0.35, 0.12, 0.14, 1.0),      # Merah
		"accent": Color(0.88, 0.38, 0.40, 1.0),
	},
	{
		"id": "extreme",
		"title": "EXTREME",
		"tag": "Tanpa Ampun",
		"base": Color(0.17, 0.04, 0.06, 1.0),      # Merah Gelap
		"accent": Color(0.62, 0.15, 0.20, 1.0),
	},
]

const DECK_SIZE := Vector2(226.0, 326.0)

@onready var _deck_row: HBoxContainer = $CenterWrap/Column/DeckRow
@onready var _back_btn: Button = $CenterWrap/Column/BackBtn
@onready var _title: Label = $CenterWrap/Column/Header/Title
@onready var _subtitle: Label = $CenterWrap/Column/Header/Subtitle
@onready var _divider: Panel = $CenterWrap/Column/Header/Divider

var _cards: Array[Control] = []

func _ready() -> void:
	Audio.play_music("menu")
	_back_btn.pressed.connect(_go_back)
	_build_deck_cards()
	call_deferred("_play_entrance")

func _build_deck_cards() -> void:
	for i in DECK_TIERS.size():
		var tier: Dictionary = DECK_TIERS[i]
		var card := _make_deck_card(tier)
		_deck_row.add_child(card)
		_cards.append(card)

func _make_deck_card(tier: Dictionary) -> Control:
	var base_col: Color = tier.base
	var acc_col: Color = tier.accent

	var wrap := Control.new()
	wrap.custom_minimum_size = DECK_SIZE + Vector2(14.0, 20.0)
	wrap.pivot_offset = wrap.custom_minimum_size * 0.5
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Efek ketebalan tumpukan deck (2 lapis kartu di bawah)
	for layer in [2, 1]:
		var stack := Panel.new()
		stack.position = Vector2(float(layer) * 4.5, float(layer) * 5.5)
		stack.size = DECK_SIZE
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = base_col.darkened(0.30 + float(layer) * 0.12)
		st.border_color = Color(acc_col.r, acc_col.g, acc_col.b, 0.32)
		st.set_border_width_all(1)
		st.set_corner_radius_all(12)
		stack.add_theme_stylebox_override("panel", st)
		wrap.add_child(stack)

	# Tombol utama berbentuk punggung kartu deck
	var btn := Button.new()
	btn.position = Vector2.ZERO
	btn.size = DECK_SIZE
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_sb)
	btn.add_theme_stylebox_override("hover", empty_sb)
	btn.add_theme_stylebox_override("pressed", empty_sb)
	btn.add_theme_stylebox_override("focus", empty_sb)
	wrap.add_child(btn)

	# Klip sudut membulat + CardBackArt prosedural Elementa
	var clip := PanelContainer.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var clip_sb := StyleBoxFlat.new()
	clip_sb.bg_color = base_col
	clip_sb.set_corner_radius_all(12)
	clip.add_theme_stylebox_override("panel", clip_sb)
	btn.add_child(clip)

	var back_art: Control = CARD_BACK_SCRIPT.new()
	back_art.base_color = base_col
	back_art.accent_color = acc_col
	back_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.add_child(back_art)

	# Bingkai luar halus (semakin tegas saat hover)
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b_sb := StyleBoxFlat.new()
	b_sb.bg_color = Color(0, 0, 0, 0)
	b_sb.border_color = Color(acc_col.r, acc_col.g, acc_col.b, 0.65)
	b_sb.set_border_width_all(2)
	b_sb.set_corner_radius_all(12)
	border.add_theme_stylebox_override("panel", b_sb)
	btn.add_child(border)

	# Label tingkat kesulitan di bagian bawah kartu deck
	var lbl_box := VBoxContainer.new()
	lbl_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_box.offset_top = -78.0
	lbl_box.offset_bottom = -16.0
	lbl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_box.add_theme_constant_override("separation", 2)
	lbl_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(lbl_box)

	var title_lbl := Label.new()
	title_lbl.text = String(tier.title)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 0.99, 1.0))
	lbl_box.add_child(title_lbl)

	var tag_lbl := Label.new()
	tag_lbl.text = String(tier.tag)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.add_theme_font_size_override("font_size", 14)
	tag_lbl.add_theme_color_override("font_color", acc_col.lightened(0.22))
	lbl_box.add_child(tag_lbl)

	var diff_id := String(tier.id)
	var wins := int(Settings.get_value("stats", "ai_wins_" + diff_id, 0))
	var losses := int(Settings.get_value("stats", "ai_losses_" + diff_id, 0))

	# Lencana rekor menang/kalah di pojok atas kartu deck AI
	if wins > 0 or losses > 0:
		var stat_lbl := Label.new()
		stat_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		stat_lbl.offset_top = 18.0
		stat_lbl.offset_bottom = 44.0
		stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_lbl.add_theme_font_size_override("font_size", 13)
		if wins > 0:
			stat_lbl.text = "★ %dM - %dK" % [wins, losses]
			stat_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.44, 1.0))
		else:
			stat_lbl.text = "%dM - %dK" % [wins, losses]
			stat_lbl.add_theme_color_override("font_color", Color(0.76, 0.82, 0.88, 0.9))
		btn.add_child(stat_lbl)

	# Interaksi hover & klik
	btn.pressed.connect(func(): _start_ai_match(diff_id))
	btn.mouse_entered.connect(func(): _hover_card(wrap, border, acc_col, true))
	btn.mouse_exited.connect(func(): _hover_card(wrap, border, acc_col, false))
	btn.button_down.connect(func():
		var tw := wrap.create_tween()
		tw.tween_property(wrap, "scale", Vector2(0.97, 0.97), 0.08))

	return wrap

func _hover_card(wrap: Control, border: Panel, acc_col: Color, on: bool) -> void:
	if not is_instance_valid(wrap):
		return
	if on:
		Audio.play_sfx("ui_hover", -8.0, 0.04)
	var b_sb := border.get_theme_stylebox("panel") as StyleBoxFlat
	if b_sb != null:
		b_sb.border_color = acc_col.lightened(0.18) if on else Color(acc_col.r, acc_col.g, acc_col.b, 0.65)
		b_sb.set_border_width_all(3 if on else 2)
	var tw := wrap.create_tween().set_parallel(true)
	tw.tween_property(wrap, "scale", Vector2(1.06, 1.06) if on else Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_entrance() -> void:
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_divider.pivot_offset = _divider.size * 0.5
	_divider.scale.x = 0.01
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_title, "modulate:a", 1.0, 0.36)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.36).set_delay(0.08)
	tw.tween_property(_divider, "scale:x", 1.0, 0.44).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	for i in _cards.size():
		var c: Control = _cards[i]
		c.pivot_offset = c.size * 0.5
		c.modulate.a = 0.0
		c.scale = Vector2(0.88, 0.88)
		var ctw := c.create_tween().set_parallel(true)
		var d := 0.14 + float(i) * 0.075
		ctw.tween_property(c, "modulate:a", 1.0, 0.32).set_delay(d)
		ctw.tween_property(c, "scale", Vector2.ONE, 0.36).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _start_ai_match(diff: String) -> void:
	Net.local_test = false
	Net.vs_ai = true
	Net.tutorial_mode = false
	Net.puzzle_id = ""
	Net.ai_difficulty = diff
	get_tree().change_scene_to_file("res://scenes/screens/game.tscn")

func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_go_back()
