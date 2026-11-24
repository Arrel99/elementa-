extends Control

## Layar pilihan 5 skenario Puzzle Kimia (Mode Tantangan) bergaya Main Menu.

const PUZZLE_DB := preload("res://scripts/core/puzzle_db.gd")

@onready var _list: VBoxContainer = $CenterWrap/Column/List
@onready var _back_btn: Button = $CenterWrap/Column/BackBtn

func _ready() -> void:
	Audio.play_music("menu")
	_back_btn.pressed.connect(_go_back)
	_build_list()

func _build_list() -> void:
	for i in PUZZLE_DB.PUZZLES.size():
		var p: Dictionary = PUZZLE_DB.PUZZLES[i]
		var pid := String(p.id)
		var solved := bool(Settings.get_value("stats", "puzzle_" + pid, false))

		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 20.0
		sb.content_margin_right = 20.0
		sb.content_margin_top = 14.0
		sb.content_margin_bottom = 14.0
		sb.bg_color = Color(0.095, 0.135, 0.140, 0.94) if solved else Color(0.095, 0.115, 0.142, 0.94)
		sb.border_width_left = 3 if solved else 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.32, 0.76, 0.62, 1.0) if solved else Color(0.24, 0.30, 0.38, 1.0)
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.corner_radius_bottom_left = 10
		card.add_theme_stylebox_override("panel", sb)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		card.add_child(h)

		var num := Label.new()
		num.text = String(p.num)
		num.custom_minimum_size = Vector2(44, 0)
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 26)
		num.add_theme_color_override("font_color", Color(0.38, 0.84, 0.68) if solved else Color(0.45, 0.62, 0.78))
		h.add_child(num)

		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 2)
		h.add_child(tv)

		var title := Label.new()
		title.text = String(p.title) + ("   ✓" if solved else "")
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color(0.95, 0.97, 0.99))
		tv.add_child(title)

		var goal := Label.new()
		goal.text = String(p.goal)
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal.add_theme_font_size_override("font_size", 14)
		goal.add_theme_color_override("font_color", Color(0.70, 0.78, 0.85))
		tv.add_child(goal)

		var play_btn := Button.new()
		play_btn.text = "Main"
		play_btn.custom_minimum_size = Vector2(116, 44)
		play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		play_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.18, 0.44, 0.42, 1.0)
		bsb.border_color = Color(0.34, 0.68, 0.62, 1.0)
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(8)
		play_btn.add_theme_stylebox_override("normal", bsb)
		var bsbh := bsb.duplicate() as StyleBoxFlat
		bsbh.bg_color = Color(0.22, 0.54, 0.50, 1.0)
		play_btn.add_theme_stylebox_override("hover", bsbh)
		play_btn.add_theme_font_size_override("font_size", 17)
		play_btn.pressed.connect(_start_puzzle.bind(pid))
		h.add_child(play_btn)

		_list.add_child(card)

func _start_puzzle(pid: String) -> void:
	Net.local_test = false
	Net.vs_ai = true
	Net.tutorial_mode = false
	Net.ai_difficulty = "normal"
	Net.puzzle_id = pid
	get_tree().change_scene_to_file("res://scenes/screens/game.tscn")

func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_go_back()
