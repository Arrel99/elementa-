class_name Board3D
extends Node3D

## Arena permainan 2.5D (3D tabletop + pencahayaan + tumpukan kartu + animasi).
## Dipasang di dalam SubViewport pada scenes/screens/game.tscn.

signal card_clicked(uid: int)
signal card_preview_hover(data: Dictionary, source: Node)
signal card_preview_exit(source: Node)
signal card_preview_pin(data: Dictionary, source: Node)

const CARD_3D_SCRIPT := preload("res://scripts/ui/card_3d.gd")

const SIZE_BASE := Vector2(1.04, 1.38)
const SIZE_SPECIAL := Vector2(0.82, 1.08)
const SIZE_SEN := Vector2(0.88, 1.18)
const SIZE_TABLE := Vector2(0.80, 1.06)
const SIZE_PILE := Vector2(0.88, 1.18)

const CAM_BASE_POS := Vector3(0.45, 10.6, 8.2)
const CAM_LOOK_TARGET := Vector3(0.45, -0.25, 0.15)

const COLOR_MAT_BG := Color(0.055, 0.085, 0.125, 1.0)
const COLOR_FRAME := Color(0.11, 0.16, 0.23, 1.0)
const COLOR_SLOT_ME := Color(0.16, 0.42, 0.56, 0.78)
const COLOR_SLOT_OPP := Color(0.56, 0.22, 0.26, 0.72)
const COLOR_SLOT_MID := Color(0.24, 0.52, 0.44, 0.72)
const COLOR_GLOW := Color(0.32, 0.88, 0.72, 1.0)

var _camera: Camera3D
var _cards_root: Node3D
var _glows: Dictionary = {}          # zone_name -> Node3D
var _glow_mats: Dictionary = {}      # zone_name -> StandardMaterial3D
var _glow_tween: Tween

var _piles: Dictionary = {}          # pile_key -> { "mesh": MeshInstance3D, "count": Label3D }
var _shields: Dictionary = {}        # "me" | "opp" -> { "ring": MeshInstance3D, "label": Label3D }

var _known_uids := {}                # uid yang sudah ada di papan pada render sebelumnya
var _time := 0.0

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_lights()
	_build_table()
	_build_all_slots()
	_build_piles()
	_build_shield_pads()
	_build_zone_glows()

	_cards_root = Node3D.new()
	_cards_root.name = "CardsRoot"
	add_child(_cards_root)

func _process(delta: float) -> void:
	_time += delta
	# Rotasi halus cincin perisai aktif
	for k in _shields:
		var ring: MeshInstance3D = _shields[k].ring
		if ring.visible:
			ring.rotation.y = _time * 1.1

# --- Lingkungan, Kamera, dan Pencahayaan -------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.032, 0.048, 0.072, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.68, 0.85, 1.0)
	env.ambient_light_energy = 0.72
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 40.0
	_camera.near = 0.2
	_camera.far = 80.0
	_camera.position = CAM_BASE_POS
	add_child(_camera)
	_camera.look_at(CAM_LOOK_TARGET, Vector3.UP)
	_camera.current = true

func _setup_lights() -> void:
	# Cahaya utama dari atas-depan dengan bayangan lembut
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(0.95, 0.97, 1.0, 1.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.8
	sun.rotation_degrees = Vector3(-58.0, 22.0, 0.0)
	add_child(sun)

	# Cahaya aksen biru-cyan di sisi pemain (nuansa duel lab)
	var me_light := OmniLight3D.new()
	me_light.name = "MeAccentLight"
	me_light.light_color = Color(0.28, 0.78, 1.0, 1.0)
	me_light.light_energy = 1.6
	me_light.omni_range = 14.0
	me_light.position = Vector3(0.0, 4.2, 4.6)
	add_child(me_light)

	# Cahaya aksen merah-oranye hangat di sisi lawan
	var opp_light := OmniLight3D.new()
	opp_light.name = "OppAccentLight"
	opp_light.light_color = Color(1.0, 0.42, 0.36, 1.0)
	opp_light.light_energy = 1.45
	opp_light.omni_range = 14.0
	opp_light.position = Vector3(0.0, 4.2, -4.6)
	add_child(opp_light)

# --- Meja & Playmat 3D -------------------------------------------------------

func _build_table() -> void:
	var table := Node3D.new()
	table.name = "Table"
	add_child(table)

	# Permukaan playmat penuh memenuhi seluruh layar di semua rasio jendela
	var mat_box := _make_box(Vector3(38.0, 0.08, 26.0), COLOR_MAT_BG, 0.68, 0.10)
	mat_box.position = Vector3(0.0, -0.04, 0.0)
	table.add_child(mat_box)

	# Panel area arena aktif sedikit menonjol di tengah playmat
	var arena_pad := _make_box(Vector3(14.8, 0.02, 8.6), Color(0.068, 0.105, 0.152, 1.0), 0.62, 0.14)
	arena_pad.position = Vector3(-0.15, -0.005, -0.05)
	table.add_child(arena_pad)

	# Garis pembatas tengah menyala (pemisah sisi lawan & pemain, memanjang penuh)
	var divider := _make_emissive_bar(Vector3(36.0, 0.014, 0.045), Color(0.22, 0.66, 0.84, 1.0), 1.4)
	divider.position = Vector3(0.0, 0.008, -0.05)
	table.add_child(divider)

	# Garis aksen tepi sisi pemain (cyan) & sisi lawan (merah hangat)
	var me_edge := _make_emissive_bar(Vector3(14.8, 0.018, 0.05), Color(0.24, 0.72, 0.92, 1.0), 1.3)
	me_edge.position = Vector3(-0.15, 0.01, 4.25)
	table.add_child(me_edge)

	var opp_edge := _make_emissive_bar(Vector3(14.8, 0.018, 0.05), Color(0.92, 0.34, 0.36, 1.0), 1.3)
	opp_edge.position = Vector3(-0.15, 0.01, -4.35)
	table.add_child(opp_edge)

	# Label zona di permukaan meja
	_add_zone_label(table, "ZONA SENYAWA LAWAN", Vector3(-4.95, 0.015, -3.76), Color(0.85, 0.55, 0.58))
	_add_zone_label(table, "ZONA DASAR LAWAN", Vector3(0.35, 0.015, -3.38), Color(0.85, 0.55, 0.58))
	_add_zone_label(table, "TABEL SENYAWA", Vector3(-0.35, 0.015, -0.78), Color(0.55, 0.85, 0.76))
	_add_zone_label(table, "ZONA SENYAWA KAMU", Vector3(-4.95, 0.015, 3.74), Color(0.55, 0.82, 0.96))
	_add_zone_label(table, "ZONA DASAR KAMU", Vector3(0.35, 0.015, 3.30), Color(0.55, 0.82, 0.96))
	_add_zone_label(table, "SENYAWA TERAKHIR", Vector3(4.60, 0.015, -3.26), Color(0.82, 0.64, 0.66))
	_add_zone_label(table, "SENYAWA TERAKHIR", Vector3(4.60, 0.015, 3.16), Color(0.55, 0.82, 0.96))

func _add_zone_label(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 24
	lbl.pixel_size = 0.0085
	lbl.modulate = color
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.02, 0.04, 0.07, 0.9)
	lbl.rotation_degrees.x = -90.0
	lbl.position = pos
	parent.add_child(lbl)

# --- Slot Zona ---------------------------------------------------------------

func _build_all_slots() -> void:
	var slots := Node3D.new()
	slots.name = "Slots"
	add_child(slots)

	# 6 slot Base lawan & pemain
	for i in 6:
		_add_slot_frame(slots, _pos_base(false, i), SIZE_BASE, COLOR_SLOT_OPP)
		_add_slot_frame(slots, _pos_base(true, i), SIZE_BASE, COLOR_SLOT_ME)

	# 8 slot Special (2x4) lawan & pemain
	for i in 8:
		_add_slot_frame(slots, _pos_special(false, i), SIZE_SPECIAL, COLOR_SLOT_OPP)
		_add_slot_frame(slots, _pos_special(true, i), SIZE_SPECIAL, COLOR_SLOT_ME)

	# Slot Senyawa Terakhir
	_add_slot_frame(slots, _pos_sen(false), SIZE_SEN, COLOR_SLOT_OPP)
	_add_slot_frame(slots, _pos_sen(true), SIZE_SEN, COLOR_SLOT_ME)

	# Panel dasar Tabel Senyawa di tengah
	var table_pad := _make_box(Vector3(9.4, 0.012, 1.32), Color(0.065, 0.115, 0.135, 1.0), 0.7, 0.1)
	table_pad.position = Vector3(-0.35, 0.005, -0.05)
	slots.add_child(table_pad)

func _add_slot_frame(parent: Node3D, pos: Vector3, size: Vector2, border_col: Color) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, 0.006, pos.z)
	parent.add_child(holder)

	# Alas slot cekung gelap
	var pad := _make_box(Vector3(size.x, 0.008, size.y), Color(0.04, 0.062, 0.092, 1.0), 0.8, 0.05)
	holder.add_child(pad)

	# 4 garis tepi slot
	var t := 0.028
	var top := _make_emissive_bar(Vector3(size.x + t, 0.012, t), border_col, 0.65)
	top.position = Vector3(0.0, 0.004, -size.y * 0.5)
	holder.add_child(top)

	var bot := _make_emissive_bar(Vector3(size.x + t, 0.012, t), border_col, 0.65)
	bot.position = Vector3(0.0, 0.004, size.y * 0.5)
	holder.add_child(bot)

	var left := _make_emissive_bar(Vector3(t, 0.012, size.y + t), border_col, 0.65)
	left.position = Vector3(-size.x * 0.5, 0.004, 0.0)
	holder.add_child(left)

	var right := _make_emissive_bar(Vector3(t, 0.012, size.y + t), border_col, 0.65)
	right.position = Vector3(size.x * 0.5, 0.004, 0.0)
	holder.add_child(right)

# --- Tumpukan Deck & Discard 3D ----------------------------------------------

func _build_piles() -> void:
	var root := Node3D.new()
	root.name = "Piles"
	add_child(root)

	_create_pile(root, "opp_deck", "DECK", Vector3(5.95, 0.0, -3.05), Color(0.20, 0.16, 0.24), COLOR_SLOT_OPP)
	_create_pile(root, "opp_discard", "BUANG", Vector3(5.95, 0.0, -1.62), Color(0.18, 0.14, 0.16), COLOR_SLOT_OPP)
	_create_pile(root, "compound_deck", "SENYAWA", Vector3(5.95, 0.0, -0.05), Color(0.12, 0.26, 0.24), COLOR_SLOT_MID)
	_create_pile(root, "me_discard", "BUANG", Vector3(5.95, 0.0, 1.52), Color(0.14, 0.18, 0.24), COLOR_SLOT_ME)
	_create_pile(root, "me_deck", "DECK", Vector3(5.95, 0.0, 2.95), Color(0.13, 0.22, 0.34), COLOR_SLOT_ME)

func _create_pile(parent: Node3D, key: String, title: String, pos: Vector3,
		stack_col: Color, border_col: Color) -> void:
	_add_slot_frame(parent, pos, SIZE_PILE, border_col)

	var stack := MeshInstance3D.new()
	stack.name = "Stack_" + key
	var box := BoxMesh.new()
	box.size = Vector3(SIZE_PILE.x * 0.92, 0.25, SIZE_PILE.y * 0.92)
	stack.mesh = box
	stack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = stack_col
	mat.roughness = 0.52
	mat.metallic = 0.18
	stack.material_override = mat
	stack.position = Vector3(pos.x, 0.125, pos.z)
	parent.add_child(stack)

	var count_lbl := Label3D.new()
	count_lbl.text = "0"
	count_lbl.font_size = 56
	count_lbl.pixel_size = 0.0085
	count_lbl.modulate = Color(0.95, 0.98, 1.0, 1.0)
	count_lbl.outline_size = 10
	count_lbl.outline_modulate = Color(0.02, 0.04, 0.08, 1.0)
	count_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count_lbl.position = Vector3(pos.x, 0.55, pos.z)
	parent.add_child(count_lbl)

	var title_lbl := Label3D.new()
	title_lbl.text = title
	title_lbl.font_size = 22
	title_lbl.pixel_size = 0.008
	title_lbl.modulate = Color(0.72, 0.82, 0.92, 0.95)
	title_lbl.outline_size = 4
	title_lbl.outline_modulate = Color(0.02, 0.04, 0.08, 1.0)
	title_lbl.rotation_degrees.x = -90.0
	title_lbl.position = Vector3(pos.x, 0.016, pos.z + SIZE_PILE.y * 0.5 + 0.16)
	parent.add_child(title_lbl)

	_piles[key] = {"mesh": stack, "count": count_lbl, "base_pos": pos}

func _update_pile(key: String, count: int) -> void:
	if not _piles.has(key):
		return
	var info: Dictionary = _piles[key]
	var mesh: MeshInstance3D = info.mesh
	var lbl: Label3D = info.count
	var base_pos: Vector3 = info.base_pos
	lbl.text = str(count)
	if count <= 0:
		mesh.visible = false
		lbl.position.y = 0.25
		return
	mesh.visible = true
	var h := clampf(float(count) * 0.011 + 0.04, 0.05, 0.68)
	var box := mesh.mesh as BoxMesh
	box.size.y = h
	mesh.position = Vector3(base_pos.x, h * 0.5 + 0.01, base_pos.z)
	lbl.position = Vector3(base_pos.x, h + 0.26, base_pos.z)

# --- Pad Status Perisai / Spell ----------------------------------------------

func _build_shield_pads() -> void:
	var root := Node3D.new()
	root.name = "ShieldPads"
	add_child(root)
	_create_shield_pad(root, "opp", Vector3(4.60, 0.0, -1.08), COLOR_SLOT_OPP)
	_create_shield_pad(root, "me", Vector3(4.60, 0.0, 0.98), COLOR_SLOT_ME)

func _create_shield_pad(parent: Node3D, key: String, pos: Vector3, border_col: Color) -> void:
	_add_slot_frame(parent, pos, Vector2(0.92, 0.72), border_col)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.34
	torus.rings = 16
	torus.ring_segments = 6        # heksagonal khas kimia!
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.92, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.28, 0.85, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.1
	ring.material_override = mat
	ring.position = Vector3(pos.x, 0.14, pos.z)
	ring.visible = false
	parent.add_child(ring)

	var lbl := Label3D.new()
	lbl.text = "SPELL"
	lbl.font_size = 20
	lbl.pixel_size = 0.008
	lbl.modulate = Color(0.65, 0.78, 0.88, 0.9)
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.02, 0.04, 0.08, 1.0)
	lbl.rotation_degrees.x = -90.0
	lbl.position = Vector3(pos.x, 0.018, pos.z)
	parent.add_child(lbl)

	_shields[key] = {"ring": ring, "label": lbl}

func _update_shield(key: String, active: bool) -> void:
	if not _shields.has(key):
		return
	var info: Dictionary = _shields[key]
	var ring: MeshInstance3D = info.ring
	var lbl: Label3D = info.label
	ring.visible = active
	lbl.text = "PERISAI" if active else "SPELL"
	lbl.modulate = Color(0.45, 0.96, 1.0, 1.0) if active else Color(0.62, 0.72, 0.82, 0.75)

# --- Bingkai Glow Zona Target ------------------------------------------------

func _build_zone_glows() -> void:
	var root := Node3D.new()
	root.name = "ZoneGlows"
	add_child(root)

	_create_zone_glow(root, "my_base", Vector3(0.35, 0.025, 2.35), Vector2(7.16, 1.62))
	_create_zone_glow(root, "opp_base", Vector3(0.35, 0.025, -2.45), Vector2(7.16, 1.62))
	_create_zone_glow(root, "my_special", Vector3(-4.95, 0.025, 2.35), Vector2(3.86, 2.48))
	_create_zone_glow(root, "opp_special", Vector3(-4.95, 0.025, -2.45), Vector2(3.86, 2.48))

func _create_zone_glow(parent: Node3D, zone: String, center: Vector3, size: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "Glow_" + zone
	holder.position = center
	holder.visible = false
	parent.add_child(holder)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_GLOW
	mat.emission_enabled = true
	mat.emission = COLOR_GLOW
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var t := 0.075
	var specs := [
		[Vector3(size.x + t, 0.024, t), Vector3(0.0, 0.0, -size.y * 0.5)],
		[Vector3(size.x + t, 0.024, t), Vector3(0.0, 0.0, size.y * 0.5)],
		[Vector3(t, 0.024, size.y + t), Vector3(-size.x * 0.5, 0.0, 0.0)],
		[Vector3(t, 0.024, size.y + t), Vector3(size.x * 0.5, 0.0, 0.0)],
	]
	for sp in specs:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = sp[0]
		m.mesh = b
		m.position = sp[1]
		m.material_override = mat
		holder.add_child(m)

	_glows[zone] = holder
	_glow_mats[zone] = mat

func highlight_zone(zone: String) -> void:
	clear_glow()
	if not _glows.has(zone):
		return
	var holder: Node3D = _glows[zone]
	var mat: StandardMaterial3D = _glow_mats[zone]
	holder.visible = true
	mat.albedo_color.a = 0.95
	mat.emission_energy_multiplier = 2.2
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(mat, "emission_energy_multiplier", 0.65, 0.55).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(mat, "emission_energy_multiplier", 2.4, 0.55).set_trans(Tween.TRANS_SINE)

func clear_glow() -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null
	for z in _glows:
		(_glows[z] as Node3D).visible = false

# --- Posisi Slot -------------------------------------------------------------

func _pos_base(is_me: bool, idx: int) -> Vector3:
	var z := 2.35 if is_me else -2.45
	var x := -2.60 + float(idx) * 1.18
	return Vector3(x, 0.01, z)

func _pos_special(is_me: bool, idx: int) -> Vector3:
	var col := idx % 4
	var row := idx / 4
	var x := -6.36 + float(col) * 0.94
	var z := (1.75 + float(row) * 1.20) if is_me else (-3.05 + float(row) * 1.20)
	return Vector3(x, 0.01, z)

func _pos_sen(is_me: bool) -> Vector3:
	return Vector3(4.60, 0.01, 2.35 if is_me else -2.45)

# --- Render Seluruh Papan 3D -------------------------------------------------

func render_board(v: Dictionary, playable: Dictionary, easy_mode: bool) -> void:
	for ch in _cards_root.get_children():
		ch.queue_free()

	var next_uids := {}
	var playable_base: Array = playable.get("base", [])

	# Kartu Zona Dasar Pemain
	for i in v.me.base.size():
		if i >= 6:
			break
		var c: Dictionary = v.me.base[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		var is_cd := int(c.get("placed_turn", -1)) == int(v.turn_no)
		var is_play := playable_base.has(uid)
		_spawn_card(c, _pos_base(true, i), SIZE_BASE, true, true, true, "", Color.WHITE,
			is_cd, is_play, not _known_uids.has(uid))

	# Kartu Zona Dasar Lawan
	for i in v.opp.base.size():
		if i >= 6:
			break
		var c: Dictionary = v.opp.base[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		_spawn_card(c, _pos_base(false, i), SIZE_BASE, true, true, true, "", Color.WHITE,
			false, false, not _known_uids.has(uid))

	# Kartu Zona Spesial Pemain (maks 8 tampil di grid, jika lebih ditumpuk di slot terakhir)
	for i in v.me.special.size():
		var c: Dictionary = v.me.special[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		var slot_idx := mini(i, 7)
		var pos := _pos_special(true, slot_idx)
		if i >= 8:
			pos.y += float(i - 7) * 0.045
		_spawn_card(c, pos, SIZE_SPECIAL, true, true, true, "", Color.WHITE,
			false, false, not _known_uids.has(uid))

	# Kartu Zona Spesial Lawan
	for i in v.opp.special.size():
		var c: Dictionary = v.opp.special[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		var slot_idx := mini(i, 7)
		var pos := _pos_special(false, slot_idx)
		if i >= 8:
			pos.y += float(i - 7) * 0.045
		_spawn_card(c, pos, SIZE_SPECIAL, true, true, true, "", Color.WHITE,
			false, false, not _known_uids.has(uid))

	# Senyawa Terakhir Pemain & Lawan (hanya pratinjau, bukan target klik)
	if not v.me.special.is_empty():
		var last_me: Dictionary = v.me.special[v.me.special.size() - 1]
		_spawn_card(last_me, _pos_sen(true), SIZE_SEN, true, false, true, "", Color.WHITE, false, false, false)
	if not v.opp.special.is_empty():
		var last_opp: Dictionary = v.opp.special[v.opp.special.size() - 1]
		_spawn_card(last_opp, _pos_sen(false), SIZE_SEN, true, false, true, "", Color.WHITE, false, false, false)

	# Tabel Senyawa di garis tengah (sedikit dimiringkan ke kamera agar resep mudah dibaca)
	_render_compound_table(v.compound_pile, v.me.base, easy_mode)

	# Tumpukan 3D & Perisai
	_update_pile("opp_deck", int(v.opp.deck_count))
	_update_pile("opp_discard", int(v.opp.discard_count))
	_update_pile("compound_deck", v.compound_pile.size())
	_update_pile("me_discard", v.me.discard.size())
	_update_pile("me_deck", int(v.me.deck_count))
	_update_shield("opp", bool(v.opp.shield))
	_update_shield("me", bool(v.me.shield))

	_known_uids = next_uids

func _render_compound_table(ids: Array, my_base: Array, easy_mode: bool) -> void:
	var mine := {}
	for c in my_base:
		mine[c.id] = true
	var seen := {}
	var kinds: Array = []
	for id in ids:
		if seen.has(id):
			continue
		seen[id] = true
		kinds.append(id)
	var n := kinds.size()
	if n == 0:
		return
	var spacing := minf(0.96, 8.6 / float(maxi(n, 1)))
	var start_x := -0.35 - (float(n - 1) * spacing) * 0.5
	for i in n:
		var id: String = kinds[i]
		var d: CardData = CardDB.get_card(id)
		if d == null or d.recipe.size() != 2:
			continue
		var a: CardData = CardDB.get_card(d.recipe[0])
		var b: CardData = CardDB.get_card(d.recipe[1])
		if a == null or b == null:
			continue
		var recipe_txt := "%s + %s" % [a.symbol, b.symbol]
		var have := int(mine.has(d.recipe[0])) + int(mine.has(d.recipe[1]))
		var tint := Color.WHITE
		if have == 2:
			tint = Color(0.55, 1.0, 0.55)
		elif have == 1 and easy_mode:
			tint = Color(1.0, 0.92, 0.45)
		var pos := Vector3(start_x + float(i) * spacing, 0.04, -0.05)
		var card_node := _spawn_card(
			{"uid": -1, "id": id, "placed_turn": -1},
			pos, SIZE_TABLE, true, false, true, recipe_txt, tint, false, false, false)
		card_node.rotation_degrees.x = 12.0   # sedikit menengadah ke arah kamera

func _spawn_card(card: Dictionary, pos: Vector3, size_3d: Vector2,
		face_up: bool, can_click: bool, can_preview: bool,
		recipe_text: String, tint: Color, is_cd: bool, is_play: bool,
		animate_drop: bool) -> Node3D:
	var c3d: Node3D = CARD_3D_SCRIPT.new()
	_cards_root.add_child(c3d)
	c3d.position = pos
	c3d.setup(card, size_3d, face_up, can_click, can_preview, recipe_text, tint, is_cd, is_play)
	c3d.preview_hover.connect(func(d, s): card_preview_hover.emit(d, s))
	c3d.preview_exit.connect(func(s): card_preview_exit.emit(s))
	c3d.preview_pin.connect(func(d, s): card_preview_pin.emit(d, s))
	if can_click:
		c3d.clicked.connect(func(u): card_clicked.emit(u))
	if animate_drop:
		c3d.position.y = pos.y + 0.85
		c3d.scale = Vector3(1.12, 1.12, 1.12)
		var tw := c3d.create_tween().set_parallel(true)
		tw.tween_property(c3d, "position:y", pos.y, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c3d, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return c3d

# --- Bantuan Mesh ------------------------------------------------------------

func _make_box(size: Vector3, color: Color, roughness: float, metallic: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	m.material_override = mat
	return m

func _make_emissive_bar(size: Vector3, color: Color, energy: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	return m
