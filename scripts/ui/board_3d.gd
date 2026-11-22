class_name Board3D
extends Node3D

## Arena permainan 2.5D bergaya minimalis & sains (playmat matte, warna dua pemain
## yang tenang, pencahayaan studio lembut tanpa efek neon/bloom).
## Dipasang di dalam SubViewport pada scenes/screens/game.tscn.

signal card_clicked(uid: int)
signal discard_clicked(is_me: bool)
signal card_preview_hover(data: Dictionary, source: Node)
signal card_preview_exit(source: Node)
signal card_preview_pin(data: Dictionary, source: Node)

const CARD_3D_SCRIPT := preload("res://scripts/ui/card_3d.gd")
const CARD_BACK_SCRIPT := preload("res://scripts/ui/card_back_art.gd")
const SCIENCE_SHADER := preload("res://shaders/science_board.gdshader")

const SIZE_BASE := Vector2(1.08, 1.44)
const SIZE_SPECIAL := Vector2(0.86, 1.14)
const SIZE_SPELL := Vector2(0.98, 1.32)
const SIZE_TABLE := Vector2(0.86, 1.14)
const SIZE_PILE := Vector2(0.92, 1.24)

const CAM_LOOK_TARGET := Vector3(0.32, -0.05, 0.05)
const CAM_DIR := Vector3(0.0, 10.0, 6.2)       # sudut 2.5D dekat & besar
const CAM_BASE_DIST := 13.4                    # seluruh bingkai papan 3D pas memenuhi layar tanpa ruang kosong luar

# Palet matte minimalis: Steel Blue (Pemain), Warm Terracotta (Lawan), Muted Sage (Tengah)
const COLOR_ME_PAD := Color(0.112, 0.150, 0.198, 1.0)
const COLOR_ME_SLOT_BG := Color(0.088, 0.118, 0.158, 1.0)
const COLOR_ME_LINE := Color(0.36, 0.56, 0.74, 1.0)

const COLOR_OPP_PAD := Color(0.188, 0.122, 0.132, 1.0)
const COLOR_OPP_SLOT_BG := Color(0.148, 0.095, 0.104, 1.0)
const COLOR_OPP_LINE := Color(0.72, 0.42, 0.45, 1.0)

const COLOR_MID_PAD := Color(0.112, 0.156, 0.148, 1.0)
const COLOR_MID_SLOT_BG := Color(0.090, 0.128, 0.122, 1.0)
const COLOR_MID_LINE := Color(0.38, 0.62, 0.55, 1.0)

const COLOR_TARGET := Color(0.42, 0.80, 0.64, 1.0)

var _camera: Camera3D
var _cards_root: Node3D
var _glows: Dictionary = {}          # zone_name -> Node3D
var _glow_mats: Dictionary = {}      # zone_name -> StandardMaterial3D
var _glow_tween: Tween
var _slot_hover_frame: Node3D        # bingkai sorot 1 slot saat drag & drop kartu dasar

var _piles: Dictionary = {}          # pile_key -> { "mesh": MeshInstance3D, "count": Label3D }
var _shields: Dictionary = {}        # "me" | "opp" -> { "ring": MeshInstance3D, "label": Label3D }

var _known_uids := {}                # uid yang sudah ada di papan pada render sebelumnya
var _prev_board_cards := {}          # uid -> {id, pos, size, is_me, zone} untuk animasi asal/pindah
var _prev_deck_counts := {"me": -1, "opp": -1}
var _prev_compound_counts := {}      # jumlah salinan tiap senyawa di render sebelumnya (untuk animasi refill dari deck)
var _last_history_len := 0           # untuk mendeteksi aksi baru di riwayat
var _last_spektro_resolved := 0      # jumlah Spektrometer yang sudah selesai (picu animasi kocok deck)
var _did_initial_shuffle := false
var _fx_root: Node3D                 # wadah animasi kartu (sintesis, spell, draw, shuffle, discard)
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

	_fx_root = Node3D.new()
	_fx_root.name = "FxRoot"
	add_child(_fx_root)

func _process(delta: float) -> void:
	_time += delta
	# Rotasi lambat penanda perisai aktif
	for k in _shields:
		var ring: MeshInstance3D = _shields[k].ring
		if ring.visible:
			ring.rotation.y = _time * 0.65

# --- Lingkungan, Kamera, dan Pencahayaan Studio Matte ------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.068, 0.082, 0.102, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.88, 1.0)
	env.ambient_light_energy = 0.52
	env.glow_enabled = false         # tetap minimalis tanpa neon/bloom
	env.ssao_enabled = true          # bayangan kontak 3D di setiap celah, bingkai, & tumpukan kartu
	env.ssao_radius = 0.55
	env.ssao_intensity = 1.85
	env.ssao_power = 1.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 41.0
	_camera.near = 0.2
	_camera.far = 90.0
	add_child(_camera)
	_camera.current = true
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_camera_to_board)
	_fit_camera_to_board()

## Menyesuaikan jarak kamera otomatis mengikuti rasio layar (16:9, 16:10, ultrawide, dll.)
## agar seluruh 4 sudut papan 3D + HUD tidak pernah terpotong.
func _fit_camera_to_board() -> void:
	if _camera == null:
		return
	var aspect := 16.0 / 9.0
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.x > 1.0 and sz.y > 1.0:
			aspect = sz.x / sz.y
	var dist := CAM_BASE_DIST
	if aspect < (16.0 / 9.0):
		dist *= clampf((16.0 / 9.0) / aspect, 1.0, 1.45)
	_camera.position = CAM_LOOK_TARGET + CAM_DIR.normalized() * dist
	_camera.look_at(CAM_LOOK_TARGET, Vector3.UP)

func _setup_lights() -> void:
	# Cahaya studio utama bersudut miring (~42 derajat) supaya bingkai 3D, stand tengah,
	# dan tumpukan deck memunculkan bayangan nyata yang tegas namun lembut
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_color = Color(0.99, 0.98, 0.96, 1.0)
	sun.light_energy = 1.08
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.03
	sun.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	add_child(sun)

	# Cahaya rim/pengisi dari belakang-samping untuk menonjolkan tepian bevel 3D papan
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(0.80, 0.88, 0.96, 1.0)
	rim.light_energy = 0.32
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-30.0, -148.0, 0.0)
	add_child(rim)

# --- Meja & Playmat 3D Berundak dengan Bingkai Papan Utuh --------------------

func _build_table() -> void:
	var table := Node3D.new()
	table.name = "Table"
	add_child(table)

	# 1) Meja dasar luar lebih rendah (Y = -0.22) sehingga papan duel timbul secara fisik
	var mat_plane := MeshInstance3D.new()
	mat_plane.name = "SciencePlaymat"
	var pm := PlaneMesh.new()
	pm.size = Vector2(46.0, 34.0)
	mat_plane.mesh = pm
	mat_plane.position = Vector3(0.0, -0.22, 0.0)
	var sh_mat := ShaderMaterial.new()
	sh_mat.shader = SCIENCE_SHADER
	mat_plane.material_override = sh_mat
	table.add_child(mat_plane)

	# 2) Plinth / alas papan duel tebal yang timbul di atas meja & melempar bayangan
	var plinth := _make_box(Vector3(15.3, 0.22, 9.2), Color(0.075, 0.090, 0.112, 1.0), 0.55, 0.28, true)
	plinth.position = Vector3(-0.15, -0.11, -0.05)
	table.add_child(plinth)

	# 3) Bingkai tepi 3D menonjol (anodized matte steel) mengelilingi seluruh papan duel
	var rim_col := Color(0.145, 0.172, 0.210, 1.0)
	var rim_h := 0.14
	var rim_w := 0.28
	var rims := [
		[Vector3(15.5, rim_h, rim_w), Vector3(-0.15, rim_h * 0.5 - 0.02, -4.55)],
		[Vector3(15.5, rim_h, rim_w), Vector3(-0.15, rim_h * 0.5 - 0.02, 4.45)],
		[Vector3(rim_w, rim_h, 9.28), Vector3(-7.76, rim_h * 0.5 - 0.02, -0.05)],
		[Vector3(rim_w, rim_h, 9.28), Vector3(7.46, rim_h * 0.5 - 0.02, -0.05)],
	]
	for r in rims:
		var m := _make_box(r[0], rim_col, 0.42, 0.42, true)
		m.position = r[1]
		table.add_child(m)

	# 4) Blok penjepit sudut 3D (detail fisik meja laboratorium)
	var corner_col := Color(0.20, 0.24, 0.29, 1.0)
	for cx in [-7.76, 7.46]:
		for cz in [-4.55, 4.45]:
			var cb := _make_box(Vector3(0.46, 0.19, 0.46), corner_col, 0.36, 0.52, true)
			cb.position = Vector3(cx, 0.075, cz)
			table.add_child(cb)

	# 5) Panel wilayah LAWAN (matte terakota gelap) & PEMAIN (matte biru baja gelap)
	var opp_pad := _make_box(Vector3(14.7, 0.024, 3.55), COLOR_OPP_PAD, 0.80, 0.06, false)
	opp_pad.position = Vector3(-0.15, -0.008, -2.56)
	table.add_child(opp_pad)

	var me_pad := _make_box(Vector3(14.7, 0.024, 3.55), COLOR_ME_PAD, 0.80, 0.06, false)
	me_pad.position = Vector3(-0.15, -0.008, 2.46)
	table.add_child(me_pad)

	# 6) Jembatan & rak reaksi TENGAH yang terangkat (elevated 3D display strip)
	var mid_bridge := _make_box(Vector3(14.7, 0.09, 1.46), COLOR_MID_PAD, 0.68, 0.14, true)
	mid_bridge.position = Vector3(-0.15, 0.032, -0.05)
	table.add_child(mid_bridge)

	# Rel pembatas 3D berprofil di tepi jembatan tengah
	var rail_top := _make_box(Vector3(14.7, 0.055, 0.075), COLOR_OPP_LINE.lerp(COLOR_MID_LINE, 0.45), 0.45, 0.35, true)
	rail_top.position = Vector3(-0.15, 0.068, -0.78)
	table.add_child(rail_top)

	var rail_bot := _make_box(Vector3(14.7, 0.055, 0.075), COLOR_ME_LINE.lerp(COLOR_MID_LINE, 0.45), 0.45, 0.35, true)
	rail_bot.position = Vector3(-0.15, 0.068, 0.68)
	table.add_child(rail_bot)

	# Garis tepi wilayah pemain & lawan (bervolume 3D)
	var me_edge := _make_box(Vector3(14.7, 0.04, 0.05), COLOR_ME_LINE, 0.45, 0.30, true)
	me_edge.position = Vector3(-0.15, 0.02, 4.24)
	table.add_child(me_edge)

	var opp_edge := _make_box(Vector3(14.7, 0.04, 0.05), COLOR_OPP_LINE, 0.45, 0.30, true)
	opp_edge.position = Vector3(-0.15, 0.02, -4.34)
	table.add_child(opp_edge)

	# Sekat 3D tipis antar kolom zona (melempar bayangan lembut)
	for x_div in [-3.18, 3.98, 5.28]:
		var line_me := _make_box(Vector3(0.045, 0.038, 3.45), COLOR_ME_LINE * 0.82, 0.48, 0.28, true)
		line_me.position = Vector3(x_div, 0.019, 2.46)
		table.add_child(line_me)
		var line_opp := _make_box(Vector3(0.045, 0.038, 3.45), COLOR_OPP_LINE * 0.82, 0.48, 0.28, true)
		line_opp.position = Vector3(x_div, 0.019, -2.56)
		table.add_child(line_opp)

# --- Slot Zona Minimalis -----------------------------------------------------

func _build_all_slots() -> void:
	var slots := Node3D.new()
	slots.name = "Slots"
	add_child(slots)

	# 6 slot Base lawan (terakota) & pemain (biru baja)
	for i in 6:
		_add_slot_frame(slots, _pos_base(false, i), SIZE_BASE, COLOR_OPP_SLOT_BG, COLOR_OPP_LINE)
		_add_slot_frame(slots, _pos_base(true, i), SIZE_BASE, COLOR_ME_SLOT_BG, COLOR_ME_LINE)

	# 8 slot Special (2x4) lawan & pemain
	for i in 8:
		_add_slot_frame(slots, _pos_special(false, i), SIZE_SPECIAL, COLOR_OPP_SLOT_BG, COLOR_OPP_LINE)
		_add_slot_frame(slots, _pos_special(true, i), SIZE_SPECIAL, COLOR_ME_SLOT_BG, COLOR_ME_LINE)

	# Dudukan 3D rak Tabel Senyawa di atas jembatan tengah
	var table_pad := _make_box(Vector3(9.4, 0.032, 1.24), COLOR_MID_SLOT_BG, 0.72, 0.10, true)
	table_pad.position = Vector3(-0.35, 0.088, -0.05)
	slots.add_child(table_pad)

func _add_slot_frame(parent: Node3D, pos: Vector3, size: Vector2, pad_col: Color, border_col: Color) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, pos.y + 0.006, pos.z)
	parent.add_child(holder)

	# Alas baki kartu cekung gelap matte
	var pad := _make_box(Vector3(size.x, 0.010, size.y), pad_col.darkened(0.18), 0.88, 0.04, false)
	holder.add_child(pad)

	# 4 dinding tepi baki 3D yang timbul & melempar bayangan lembut
	var t := 0.032
	var wall_h := 0.044
	var wall_col := border_col * 0.88
	var top := _make_box(Vector3(size.x + t, wall_h, t), wall_col, 0.48, 0.25, true)
	top.position = Vector3(0.0, wall_h * 0.5, -size.y * 0.5)
	holder.add_child(top)

	var bot := _make_box(Vector3(size.x + t, wall_h, t), wall_col, 0.48, 0.25, true)
	bot.position = Vector3(0.0, wall_h * 0.5, size.y * 0.5)
	holder.add_child(bot)

	var left := _make_box(Vector3(t, wall_h, size.y + t), wall_col, 0.48, 0.25, true)
	left.position = Vector3(-size.x * 0.5, wall_h * 0.5, 0.0)
	holder.add_child(left)

	var right := _make_box(Vector3(t, wall_h, size.y + t), wall_col, 0.48, 0.25, true)
	right.position = Vector3(size.x * 0.5, wall_h * 0.5, 0.0)
	holder.add_child(right)

# --- Tumpukan Deck & Discard 3D ----------------------------------------------

func _build_piles() -> void:
	var root := Node3D.new()
	root.name = "Piles"
	add_child(root)

	_create_pile(root, "opp_deck", true, Vector3(5.95, 0.0, -3.05), Color(0.32, 0.16, 0.19), COLOR_OPP_SLOT_BG, COLOR_OPP_LINE, false)
	_create_pile(root, "opp_discard", false, Vector3(5.95, 0.0, -1.62), Color(0.24, 0.15, 0.17), COLOR_OPP_SLOT_BG, COLOR_OPP_LINE, true)
	_create_pile(root, "compound_deck", true, Vector3(5.95, 0.075, -0.05), Color(0.14, 0.28, 0.25), COLOR_MID_SLOT_BG, COLOR_MID_LINE, false)
	_create_pile(root, "me_discard", false, Vector3(5.95, 0.0, 1.52), Color(0.15, 0.21, 0.28), COLOR_ME_SLOT_BG, COLOR_ME_LINE, true)
	_create_pile(root, "me_deck", true, Vector3(5.95, 0.0, 2.95), Color(0.14, 0.24, 0.36), COLOR_ME_SLOT_BG, COLOR_ME_LINE, false)

func _create_pile(parent: Node3D, key: String, show_back_top: bool, pos: Vector3,
		stack_col: Color, pad_col: Color, border_col: Color, clickable_discard: bool) -> void:
	_add_slot_frame(parent, pos, SIZE_PILE, pad_col, border_col)

	var stack := MeshInstance3D.new()
	stack.name = "Stack_" + key
	var box := BoxMesh.new()
	box.size = Vector3(SIZE_PILE.x * 0.92, 0.25, SIZE_PILE.y * 0.92)
	stack.mesh = box
	stack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = stack_col
	mat.roughness = 0.72
	mat.metallic = 0.06
	stack.material_override = mat
	stack.position = Vector3(pos.x, 0.125, pos.z)
	parent.add_child(stack)

	# Bagian atas tumpukan deck menampilkan desain belakang kartu Elementa (bukan kotak polos)
	var top_face: MeshInstance3D = null
	if show_back_top:
		top_face = MeshInstance3D.new()
		top_face.name = "TopFace_" + key
		var q := QuadMesh.new()
		q.size = Vector2(SIZE_PILE.x * 0.90, SIZE_PILE.y * 0.90)
		top_face.mesh = q
		top_face.rotation_degrees.x = -90.0
		var tmat := StandardMaterial3D.new()
		tmat.albedo_texture = CARD_BACK_SCRIPT.make_back_texture(stack_col, border_col)
		tmat.roughness = 0.55
		tmat.metallic = 0.08
		top_face.material_override = tmat
		top_face.position = Vector3(pos.x, 0.26, pos.z)
		parent.add_child(top_face)

	# Area klik pada Discard Pile supaya pemain bebas membuka isi discard keduanya
	if clickable_discard:
		var is_me_pile := (key == "me_discard")
		var area := Area3D.new()
		area.name = "Click_" + key
		area.input_ray_pickable = true
		area.position = Vector3(pos.x, 0.18, pos.z)
		var col := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = Vector3(SIZE_PILE.x * 1.05, 0.55, SIZE_PILE.y * 1.05)
		col.shape = shp
		area.add_child(col)
		area.input_event.connect(func(_cam, ev, _p, _n, _idx):
			if ev is InputEventMouseButton and ev.pressed and (
				ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT):
				discard_clicked.emit(is_me_pile))
		parent.add_child(area)

	var count_lbl := Label3D.new()
	count_lbl.text = "0"
	count_lbl.font_size = 52
	count_lbl.pixel_size = 0.0085
	count_lbl.modulate = Color(0.94, 0.95, 0.97, 1.0)
	count_lbl.outline_size = 8
	count_lbl.outline_modulate = Color(0.06, 0.07, 0.09, 0.95)
	count_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count_lbl.position = Vector3(pos.x, 0.55, pos.z)
	parent.add_child(count_lbl)

	_piles[key] = {"mesh": stack, "top_face": top_face, "count": count_lbl, "base_pos": pos}

func _update_pile(key: String, count: int) -> float:
	if not _piles.has(key):
		return 0.01
	var info: Dictionary = _piles[key]
	var mesh: MeshInstance3D = info.mesh
	var top_face: MeshInstance3D = info.top_face
	var lbl: Label3D = info.count
	var base_pos: Vector3 = info.base_pos
	lbl.text = str(count)
	if count <= 0:
		mesh.visible = false
		if top_face != null:
			top_face.visible = false
		lbl.position.y = base_pos.y + 0.25
		return base_pos.y + 0.01
	mesh.visible = true
	var h := clampf(float(count) * 0.011 + 0.04, 0.05, 0.68)
	var box := mesh.mesh as BoxMesh
	box.size.y = h
	mesh.position = Vector3(base_pos.x, base_pos.y + h * 0.5 + 0.01, base_pos.z)
	if top_face != null:
		top_face.visible = true
		top_face.position = Vector3(base_pos.x, base_pos.y + h + 0.014, base_pos.z)
	lbl.position = Vector3(base_pos.x, base_pos.y + h + 0.26, base_pos.z)
	return base_pos.y + h + 0.016

# --- Slot Spell Khusus (menggantikan slot senyawa terakhir) ------------------

func _build_shield_pads() -> void:
	var root := Node3D.new()
	root.name = "SpellSlots"
	add_child(root)
	_create_shield_pad(root, "opp", Vector3(4.60, 0.0, -2.45), COLOR_OPP_SLOT_BG, COLOR_OPP_LINE)
	_create_shield_pad(root, "me", Vector3(4.60, 0.0, 2.35), COLOR_ME_SLOT_BG, COLOR_ME_LINE)

func _create_shield_pad(parent: Node3D, key: String, pos: Vector3, pad_col: Color, border_col: Color) -> void:
	_add_slot_frame(parent, pos, SIZE_SPELL, pad_col, border_col)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	torus.rings = 16
	torus.ring_segments = 6        # heksagonal kimia minimalis
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = border_col.lightened(0.28)
	mat.roughness = 0.42
	mat.metallic = 0.35
	ring.material_override = mat
	ring.position = Vector3(pos.x, 0.14, pos.z)
	ring.visible = false
	parent.add_child(ring)

	_shields[key] = {"ring": ring}

func _update_shield(key: String, active: bool) -> void:
	if not _shields.has(key):
		return
	var ring: MeshInstance3D = _shields[key].ring
	ring.visible = active

# --- Bingkai Penanda Zona Target (bersih, tanpa neon berlebihan) -------------

func _build_zone_glows() -> void:
	var root := Node3D.new()
	root.name = "ZoneGlows"
	add_child(root)

	_create_zone_glow(root, "my_base", Vector3(0.35, 0.022, 2.35), Vector2(7.16, 1.62))
	_create_zone_glow(root, "opp_base", Vector3(0.35, 0.022, -2.45), Vector2(7.16, 1.62))
	_create_zone_glow(root, "my_special", Vector3(-4.95, 0.022, 2.35), Vector2(3.86, 2.48))
	_create_zone_glow(root, "opp_special", Vector3(-4.95, 0.022, -2.45), Vector2(3.86, 2.48))
	_create_zone_glow(root, "my_spell", Vector3(4.60, 0.022, 2.35), SIZE_SPELL + Vector2(0.18, 0.18))

	# Bingkai sorot 1 slot khusus saat pemain menyeret kartu dasar ke slot pilihan
	_slot_hover_frame = _create_single_slot_highlight(root)

func _create_single_slot_highlight(parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "SlotHoverHighlight"
	holder.visible = false
	parent.add_child(holder)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.88, 0.68, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var sz := SIZE_BASE + Vector2(0.10, 0.10)
	var t := 0.05
	var specs := [
		[Vector3(sz.x + t, 0.022, t), Vector3(0.0, 0.0, -sz.y * 0.5)],
		[Vector3(sz.x + t, 0.022, t), Vector3(0.0, 0.0, sz.y * 0.5)],
		[Vector3(t, 0.022, sz.y + t), Vector3(-sz.x * 0.5, 0.0, 0.0)],
		[Vector3(t, 0.022, sz.y + t), Vector3(sz.x * 0.5, 0.0, 0.0)],
	]
	for sp in specs:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = sp[0]
		m.mesh = b
		m.position = sp[1]
		m.material_override = mat
		holder.add_child(m)
	return holder

func highlight_base_slot(slot_idx: int) -> void:
	if _slot_hover_frame == null:
		return
	if slot_idx < 0 or slot_idx >= 6:
		_slot_hover_frame.visible = false
		return
	var pos := _pos_base(true, slot_idx)
	_slot_hover_frame.position = Vector3(pos.x, 0.028, pos.z)
	_slot_hover_frame.visible = true

func clear_slot_highlight() -> void:
	if _slot_hover_frame != null:
		_slot_hover_frame.visible = false

func _create_zone_glow(parent: Node3D, zone: String, center: Vector3, size: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "Glow_" + zone
	holder.position = center
	holder.visible = false
	parent.add_child(holder)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_TARGET
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var t := 0.055
	var specs := [
		[Vector3(size.x + t, 0.016, t), Vector3(0.0, 0.0, -size.y * 0.5)],
		[Vector3(size.x + t, 0.016, t), Vector3(0.0, 0.0, size.y * 0.5)],
		[Vector3(t, 0.016, size.y + t), Vector3(-size.x * 0.5, 0.0, 0.0)],
		[Vector3(t, 0.016, size.y + t), Vector3(size.x * 0.5, 0.0, 0.0)],
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
	mat.albedo_color.a = 0.92
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(mat, "albedo_color:a", 0.35, 0.55).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(mat, "albedo_color:a", 0.92, 0.55).set_trans(Tween.TRANS_SINE)

func clear_glow() -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null
	for z in _glows:
		(_glows[z] as Node3D).visible = false
	clear_slot_highlight()

## Menentukan index slot Zona Dasar pemain (0..5) di bawah koordinat layar, atau -1 jika di luar.
func pick_base_slot_at(screen_pos: Vector2) -> int:
	if _camera == null or not is_inside_tree():
		return -1
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return -1
	var pt: Vector3 = hit
	var half_x := SIZE_BASE.x * 0.56
	var half_z := SIZE_BASE.y * 0.58
	for i in 6:
		var sp := _pos_base(true, i)
		if absf(pt.x - sp.x) <= half_x and absf(pt.z - sp.z) <= half_z:
			return i
	return -1

## Raycast dari koordinat layar ke kartu 3D di papan (dipakai saat drag & drop spell bertarget).
func pick_card_uid_at(screen_pos: Vector2) -> int:
	if _camera == null or not is_inside_tree():
		return -1
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 50.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	var col: Object = hit.get("collider")
	if col is Node:
		var parent := (col as Node).get_parent()
		if parent != null and "uid" in parent:
			return int(parent.uid)
	return -1

# --- Posisi Slot -------------------------------------------------------------

func _pos_base(is_me: bool, idx: int) -> Vector3:
	var z := 2.35 if is_me else -2.45
	var x := -2.60 + float(idx) * 1.18
	return Vector3(x, 0.012, z)

func _pos_special(is_me: bool, idx: int) -> Vector3:
	var col := idx % 4
	var row := idx / 4
	var x := -6.36 + float(col) * 0.94
	var z := (1.75 + float(row) * 1.20) if is_me else (-3.05 + float(row) * 1.20)
	return Vector3(x, 0.012, z)

# --- Render Seluruh Papan 3D -------------------------------------------------

func render_board(v: Dictionary, playable: Dictionary, easy_mode: bool) -> void:
	for ch in _cards_root.get_children():
		_cards_root.remove_child(ch)
		ch.queue_free()

	var next_uids := {}
	var next_board_cards := {}
	var playable_base: Array = playable.get("base", [])

	# Kartu Zona Dasar Pemain (mengikuti slot pilihan pemain)
	for i in v.me.base.size():
		if i >= 6:
			break
		var c: Dictionary = v.me.base[i]
		var uid := int(c.get("uid", -1))
		var slot_idx := clampi(int(c.get("slot", i)), 0, 5)
		var pos := _pos_base(true, slot_idx)
		next_uids[uid] = true
		next_board_cards[uid] = {"id": String(c.get("id", "")), "pos": pos, "size": SIZE_BASE, "is_me": true, "zone": "base"}
		var is_cd := int(c.get("placed_turn", -1)) == int(v.turn_no)
		var is_play := playable_base.has(uid)
		_spawn_card(c, pos, SIZE_BASE, true, true, true, "", Color.WHITE,
			is_cd, is_play, not _known_uids.has(uid), true)

	# Kartu Zona Dasar Lawan (mengikuti slot pilihan lawan)
	for i in v.opp.base.size():
		if i >= 6:
			break
		var c: Dictionary = v.opp.base[i]
		var uid := int(c.get("uid", -1))
		var slot_idx := clampi(int(c.get("slot", i)), 0, 5)
		var pos := _pos_base(false, slot_idx)
		next_uids[uid] = true
		next_board_cards[uid] = {"id": String(c.get("id", "")), "pos": pos, "size": SIZE_BASE, "is_me": false, "zone": "base"}
		_spawn_card(c, pos, SIZE_BASE, true, true, true, "", Color.WHITE,
			false, false, not _known_uids.has(uid), false)

	# Kartu Zona Spesial Pemain (maks 8 tampil di grid; 2 kartu dasar menempel di belakangnya)
	for i in v.me.special.size():
		var c: Dictionary = v.me.special[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		var slot_idx := mini(i, 7)
		var pos := _pos_special(true, slot_idx)
		if i >= 8:
			pos.y += float(i - 7) * 0.095
		next_board_cards[uid] = {"id": String(c.get("id", "")), "pos": pos, "size": SIZE_SPECIAL, "is_me": true, "zone": "special", "parts": c.get("parts", [])}
		var top_y := _spawn_attached_under(c, pos, SIZE_SPECIAL)
		_spawn_card(c, Vector3(pos.x, top_y, pos.z), SIZE_SPECIAL, true, true, true, "", Color.WHITE,
			false, false, false, true)

	# Kartu Zona Spesial Lawan (2 kartu dasar menempel di belakangnya)
	for i in v.opp.special.size():
		var c: Dictionary = v.opp.special[i]
		var uid := int(c.get("uid", -1))
		next_uids[uid] = true
		var slot_idx := mini(i, 7)
		var pos := _pos_special(false, slot_idx)
		if i >= 8:
			pos.y += float(i - 7) * 0.095
		next_board_cards[uid] = {"id": String(c.get("id", "")), "pos": pos, "size": SIZE_SPECIAL, "is_me": false, "zone": "special", "parts": c.get("parts", [])}
		var top_y := _spawn_attached_under(c, pos, SIZE_SPECIAL)
		_spawn_card(c, Vector3(pos.x, top_y, pos.z), SIZE_SPECIAL, true, true, true, "", Color.WHITE,
			false, false, false, false)

	# Tabel Senyawa di garis tengah (sedikit dimiringkan ke kamera agar resep mudah dibaca)
	_render_compound_table(v.compound_pile, v.me.base, easy_mode)

	# Tumpukan 3D & Perisai (kartu buang teratas tampil terbuka menghadap atas!)
	_update_pile("opp_deck", int(v.opp.deck_count))
	var opp_disc_cards: Array = v.opp.get("discard", [])
	var opp_disc_y := _update_pile("opp_discard", int(v.opp.discard_count))
	if not opp_disc_cards.is_empty():
		var top_opp: Dictionary = opp_disc_cards[opp_disc_cards.size() - 1]
		var top_o_node := _spawn_discard_top_card(top_opp, Vector3(5.95, opp_disc_y, -1.62), false)
		top_o_node.name = "TopOppDiscard"

	_update_pile("compound_deck", v.compound_pile.size())

	var me_disc_cards: Array = v.me.get("discard", [])
	var me_disc_y := _update_pile("me_discard", me_disc_cards.size())
	if not me_disc_cards.is_empty():
		var top_me: Dictionary = me_disc_cards[me_disc_cards.size() - 1]
		var top_m_node := _spawn_discard_top_card(top_me, Vector3(5.95, me_disc_y, 1.52), true)
		top_m_node.name = "TopMeDiscard"

	_update_pile("me_deck", int(v.me.deck_count))
	_update_shield("opp", bool(v.opp.shield))
	_update_shield("me", bool(v.me.shield))

	# Animasi awal pertandingan (kocok kedua deck) + animasi draw + animasi kartu yang baru keluar/masuk
	_animate_deck_events(v)
	_animate_removed_cards(v, next_uids)
	_animate_new_spells(v)

	_known_uids = next_uids
	_prev_board_cards = next_board_cards

func _spawn_discard_top_card(card: Dictionary, pos: Vector3, is_me: bool) -> Node3D:
	var c3d: Node3D = CARD_3D_SCRIPT.new()
	_cards_root.add_child(c3d)
	c3d.position = pos
	c3d.setup(card, SIZE_PILE * 0.94, true, true, true, "", Color.WHITE, false, false)
	c3d.preview_hover.connect(func(d, s): card_preview_hover.emit(d, s))
	c3d.preview_exit.connect(func(s): card_preview_exit.emit(s))
	# Klik kiri maupun klik kanan pada Discard Pile membuka daftar Discard Pile
	c3d.clicked.connect(func(_u): discard_clicked.emit(is_me))
	c3d.preview_pin.connect(func(_d, _s): discard_clicked.emit(is_me))
	return c3d

## Animasi kocok deck awal, kocok deck setelah Spektrometer, dan animasi menarik kartu dari deck.
func _animate_deck_events(v: Dictionary) -> void:
	if not v.get("coin_phase", {}).is_empty():
		return
	var me_dc := int(v.me.deck_count)
	var opp_dc := int(v.opp.deck_count)

	if not _did_initial_shuffle:
		_did_initial_shuffle = true
		play_shuffle_anim(true)
		play_shuffle_anim(false)
		_play_draw_anim(true, 5)
		_play_draw_anim(false, 5)
		_prev_deck_counts = {"me": me_dc, "opp": opp_dc}
		return

	# Deteksi draw kartu (saat jumlah deck berkurang, kecuali sedang pending Spektrometer)
	if v.pending.is_empty():
		var prev_me := int(_prev_deck_counts.get("me", me_dc))
		var prev_opp := int(_prev_deck_counts.get("opp", opp_dc))
		if me_dc < prev_me and (prev_me - me_dc) <= 5:
			_play_draw_anim(true, prev_me - me_dc)
		if opp_dc < prev_opp and (prev_opp - opp_dc) <= 5:
			_play_draw_anim(false, prev_opp - opp_dc)

	# Deteksi Spektrometer baru selesai -> animasi kocok deck pemiliknya!
	var spektro_done := 0
	var last_spektro_me := true
	var me_idx := int(v.get("me_index", 0))
	for h in v.get("history", []):
		if String(h.get("card_id", "")) == "spektrometer":
			var subs: Array = h.get("sub_moves", [])
			if subs.size() >= 2:
				spektro_done += 1
				last_spektro_me = (int(h.get("player", 0)) == me_idx)
	if spektro_done > _last_spektro_resolved:
		play_shuffle_anim(last_spektro_me)
	_last_spektro_resolved = spektro_done

	_prev_deck_counts = {"me": me_dc, "opp": opp_dc}

## Animasi kocok deck 3D (belah tumpukan kiri-kanan lalu satukan kembali 2 kali).
func play_shuffle_anim(is_me: bool) -> void:
	var key := "me_deck" if is_me else "opp_deck"
	if not _piles.has(key):
		return
	if is_me:
		Audio.play_sfx("card_shuffle", -2.0, 0.05)
	var base_pos: Vector3 = _piles[key].base_pos
	var stack_col := Color(0.14, 0.24, 0.36) if is_me else Color(0.32, 0.16, 0.19)
	var border_col := COLOR_ME_LINE if is_me else COLOR_OPP_LINE
	var back_tex := CARD_BACK_SCRIPT.make_back_texture(stack_col, border_col)

	var packets: Array[MeshInstance3D] = []
	for k in 2:
		var pkt := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(SIZE_PILE.x * 0.90, 0.14, SIZE_PILE.y * 0.90)
		pkt.mesh = box
		pkt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = back_tex
		mat.roughness = 0.58
		pkt.material_override = mat
		pkt.position = Vector3(base_pos.x, 0.24 + float(k) * 0.16, base_pos.z)
		_fx_root.add_child(pkt)
		packets.append(pkt)

	for k in 2:
		var p: MeshInstance3D = packets[k]
		var dir := -1.0 if k == 0 else 1.0
		var home := p.position
		var split_pos := home + Vector3(dir * 0.62, 0.22, 0.0)
		var tw := p.create_tween()
		# Kocokan 1
		tw.set_parallel(true)
		tw.tween_property(p, "position", split_pos, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "rotation_degrees:z", -dir * 12.0, 0.18)
		tw.chain().set_parallel(true)
		tw.tween_property(p, "position", home + Vector3(0.0, 0.08, 0.0), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "rotation_degrees:z", 0.0, 0.16)
		# Kocokan 2
		tw.chain().set_parallel(true)
		tw.tween_property(p, "position", split_pos * Vector3(1.0, 1.0, 1.0) - Vector3(dir * 0.12, 0.04, 0.0), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "rotation_degrees:z", -dir * 9.0, 0.16)
		tw.chain().set_parallel(true)
		tw.tween_property(p, "position", home, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(p, "rotation_degrees:z", 0.0, 0.18)
		tw.chain().tween_callback(p.queue_free)

## Animasi menarik kartu dari puncak Deck 3D meluncur ke tangan pemain.
func _play_draw_anim(is_me: bool, count: int) -> void:
	var deck_pos := Vector3(5.95, 0.48, 2.95 if is_me else -3.05)
	var hand_dest := Vector3(0.35, 1.25, 5.6 if is_me else -5.6)
	for i in count:
		var c3d: Node3D = CARD_3D_SCRIPT.new()
		_fx_root.add_child(c3d)
		c3d.setup({"uid": -1, "id": "back", "placed_turn": -1}, SIZE_PILE * 0.94, false, false, false)
		c3d.position = deck_pos
		var tw := c3d.create_tween()
		if i > 0:
			tw.tween_interval(float(i) * 0.14)
		if is_me:
			tw.chain().tween_callback(func(): Audio.play_sfx("card_draw", -4.0, 0.08))
		tw.chain().set_parallel(true)
		tw.tween_property(c3d, "position", deck_pos + Vector3(-0.35, 0.55, 0.0), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c3d, "rotation_degrees:x", 18.0 if is_me else -18.0, 0.18)
		tw.chain().set_parallel(true)
		tw.tween_property(c3d, "position", hand_dest, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(c3d, "rotation_degrees:y", 16.0 if is_me else -16.0, 0.36)
		tw.tween_property(c3d, "scale", Vector3(0.85, 0.85, 0.85), 0.36)
		tw.chain().tween_callback(c3d.queue_free)

## Animasi kartu yang hilang dari papan karena Korosi / Bilas (meluncur ke Discard)
## atau Elektrolisis (senyawa kembali ke Deck Senyawa, 2 unsur kembali ke tangan).
func _animate_removed_cards(v: Dictionary, next_uids: Dictionary) -> void:
	var hist: Array = v.get("history", [])
	var latest_action := ""
	if hist.size() > _last_history_len and not hist.is_empty():
		latest_action = String(hist[hist.size() - 1].get("action", ""))
	if latest_action == "synth":
		return     # sudah ditangani animasi sintesis

	for uid in _prev_board_cards:
		if next_uids.has(uid):
			continue
		var prev: Dictionary = _prev_board_cards[uid]
		var cid := String(prev.get("id", ""))
		var start_pos: Vector3 = prev.get("pos", Vector3.ZERO)
		var sz: Vector2 = prev.get("size", SIZE_BASE)
		var is_me: bool = bool(prev.get("is_me", true))
		var zone := String(prev.get("zone", "base"))

		if zone == "base":
			Audio.play_sfx("card_discard", -2.0, 0.06)
			var disc_pos := Vector3(5.95, 0.36, 1.52 if is_me else -1.62)
			var c3d: Node3D = CARD_3D_SCRIPT.new()
			_fx_root.add_child(c3d)
			c3d.setup({"uid": -1, "id": cid, "placed_turn": -1}, sz, true, false, false)
			c3d.position = start_pos
			var tw := c3d.create_tween()
			tw.set_parallel(true)
			tw.tween_property(c3d, "position", start_pos + Vector3(0.0, 0.75, 0.0), 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(c3d, "rotation_degrees:z", 12.0, 0.20)
			tw.chain().set_parallel(true)
			tw.tween_property(c3d, "position", disc_pos, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(c3d, "scale", Vector3(0.76, 0.76, 0.76), 0.38)
			tw.chain().tween_callback(c3d.queue_free)
		elif zone == "special":
			Audio.play_sfx("card_discard", -1.5, 0.05)
			# Senyawa meluncur kembali ke Deck Senyawa di tengah kanan
			var comp_deck := Vector3(5.95, 0.48, -0.05)
			var sc3d: Node3D = CARD_3D_SCRIPT.new()
			_fx_root.add_child(sc3d)
			sc3d.setup({"uid": -1, "id": cid, "placed_turn": -1}, sz, true, false, false)
			sc3d.position = start_pos
			var tws := sc3d.create_tween()
			tws.set_parallel(true)
			tws.tween_property(sc3d, "position", start_pos + Vector3(0.0, 0.9, 0.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tws.chain().set_parallel(true)
			tws.tween_property(sc3d, "position", comp_deck, 0.44).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			tws.tween_property(sc3d, "scale", Vector3(0.75, 0.75, 0.75), 0.44)
			tws.chain().tween_callback(sc3d.queue_free)
			# 2 unsur yang menempel terbang kembali ke tangan pemiliknya
			var parts: Array = prev.get("parts", [])
			for k in mini(parts.size(), 2):
				var p3d: Node3D = CARD_3D_SCRIPT.new()
				_fx_root.add_child(p3d)
				p3d.setup({"uid": -1, "id": String(parts[k]), "placed_turn": -1}, SIZE_SPECIAL, true, false, false)
				p3d.position = start_pos + Vector3((float(k) - 0.5) * 0.35, 0.1, 0.0)
				var hand_pos := Vector3(0.35 + (float(k) - 0.5) * 1.1, 1.3, 5.5 if is_me else -5.5)
				var twp := p3d.create_tween()
				twp.tween_interval(0.14 + float(k) * 0.10)
				twp.chain().set_parallel(true)
				twp.tween_property(p3d, "position", hand_pos, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				twp.tween_property(p3d, "scale", Vector3(0.82, 0.82, 0.82), 0.46)
				twp.chain().tween_callback(p3d.queue_free)

func _animate_new_spells(v: Dictionary) -> void:
	var hist: Array = v.get("history", [])
	if hist.size() < _last_history_len:
		_last_history_len = hist.size()
		return
	var me_idx := int(v.get("me_index", 0))
	for i in range(_last_history_len, hist.size()):
		var item: Dictionary = hist[i]
		var act := String(item.get("action", ""))
		var cid := String(item.get("card_id", ""))
		var is_me := (int(item.get("player", 0)) == me_idx)
		if act == "spell" and cid != "" and CardDB.cards.has(cid):
			_play_spell_slot_anim(cid, is_me)
		elif act == "synth" and cid != "" and CardDB.cards.has(cid):
			var spec_arr: Array = v.me.special if is_me else v.opp.special
			var target_slot := mini(maxi(spec_arr.size() - 1, 0), 7)
			_play_synth_anim(cid, is_me, target_slot)
	_last_history_len = hist.size()

## Animasi sintesis 3D: 2 kartu unsur terbang bergabung di tengah, memunculkan cincin
## reaksi heksagonal + partikel molekul, lalu senyawa baru meluncur masuk ke Zona Senyawa.
func _play_synth_anim(result_id: String, is_me: bool, target_slot: int) -> void:
	var d: CardData = CardDB.get_card(result_id)
	var parts: Array = d.recipe if (d != null and d.recipe.size() == 2) else []
	var merge_pos := Vector3(0.35, 1.85, 0.90 if is_me else -0.95)
	var dest_pos := _pos_special(is_me, target_slot) + Vector3(0.0, 0.08, 0.0)
	var base_z := 2.35 if is_me else -2.45

	# 1) Dua kartu unsur melayang dari slot asalnya & menyatu di titik reaksi tengah
	var starts := [Vector3(-1.1, 0.25, base_z), Vector3(1.8, 0.25, base_z)]
	var found_starts: Array[Vector3] = []
	for uid in _prev_board_cards:
		var prev: Dictionary = _prev_board_cards[uid]
		if bool(prev.get("is_me", true)) == is_me and String(prev.get("zone", "")) == "base":
			if parts.has(String(prev.get("id", ""))):
				found_starts.append(prev.get("pos", Vector3.ZERO))
	if found_starts.size() >= 2:
		starts = [found_starts[0], found_starts[1]]

	for k in mini(parts.size(), 2):
		var part_card: Node3D = CARD_3D_SCRIPT.new()
		_fx_root.add_child(part_card)
		part_card.setup({"uid": -1, "id": String(parts[k]), "placed_turn": -1}, SIZE_BASE * 0.94, true, false, false)
		part_card.position = starts[k]
		var tw_p := part_card.create_tween()
		tw_p.set_parallel(true)
		tw_p.tween_property(part_card, "position", merge_pos, 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw_p.tween_property(part_card, "rotation_degrees:y", 180.0 if k == 0 else -180.0, 0.46).set_trans(Tween.TRANS_CUBIC)
		tw_p.tween_property(part_card, "scale", Vector3(0.28, 0.28, 0.28), 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_p.chain().tween_callback(part_card.queue_free)

	# 2) Cincin reaksi heksagonal + 6 titik ikatan molekul mengembang saat bergabung
	var burst := Node3D.new()
	burst.position = merge_pos
	burst.scale = Vector3(0.05, 0.05, 0.05)
	_fx_root.add_child(burst)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 0.98
	torus.rings = 6
	torus.ring_segments = 8
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.46, 0.88, 0.72, 0.92)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	burst.add_child(ring)

	for i in 6:
		var ang := float(i) * TAU / 6.0
		var orb := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.09
		sp.height = 0.18
		orb.mesh = sp
		orb.material_override = rmat
		orb.position = Vector3(cos(ang) * 0.94, 0.0, sin(ang) * 0.94)
		burst.add_child(orb)

	var tw_b := burst.create_tween()
	tw_b.tween_interval(0.42)
	tw_b.chain().tween_callback(func(): Audio.play_sfx("synth_success", -1.0, 0.03))
	tw_b.chain().set_parallel(true)
	tw_b.tween_property(burst, "scale", Vector3(1.65, 1.65, 1.65), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_b.tween_property(burst, "rotation_degrees:y", 85.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	tw_b.tween_property(rmat, "albedo_color:a", 0.0, 0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_b.chain().tween_callback(burst.queue_free)

	# 3) Kartu Senyawa hasil sintesis muncul membesar, lalu meluncur masuk ke Zona Senyawa
	var res_card: Node3D = CARD_3D_SCRIPT.new()
	_fx_root.add_child(res_card)
	res_card.setup({"uid": -1, "id": result_id, "placed_turn": -1}, SIZE_SPECIAL * 1.18, true, false, false)
	res_card.position = merge_pos
	res_card.rotation_degrees.x = 22.0
	res_card.scale = Vector3(0.01, 0.01, 0.01)

	var tw_r := res_card.create_tween()
	tw_r.tween_interval(0.42)
	tw_r.chain().tween_property(res_card, "scale", Vector3(1.25, 1.25, 1.25), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_r.chain().tween_interval(0.45)
	tw_r.chain().set_parallel(true)
	tw_r.tween_property(res_card, "position", dest_pos, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw_r.tween_property(res_card, "rotation_degrees:x", 0.0, 0.42).set_trans(Tween.TRANS_CUBIC)
	tw_r.tween_property(res_card, "scale", Vector3(0.86, 0.86, 0.86), 0.42).set_trans(Tween.TRANS_CUBIC)
	tw_r.chain().tween_callback(res_card.queue_free)

## Animasi kartu Spell mendarat ke Slot Spell, tampil jelas, lalu meluncur ke Discard Pile.
func _play_spell_slot_anim(card_id: String, is_me: bool) -> void:
	Audio.play_sfx("spell_cast", -2.0, 0.04)
	var slot_pos := Vector3(4.60, 0.04, 2.35 if is_me else -2.45)
	var disc_pos := Vector3(5.95, 0.36, 1.52 if is_me else -1.62)
	var c3d: Node3D = CARD_3D_SCRIPT.new()
	_fx_root.add_child(c3d)
	c3d.setup({"uid": -1, "id": card_id, "placed_turn": -1}, SIZE_SPELL, true, false, false)
	c3d.position = Vector3(2.2, 1.45, 4.8 if is_me else -4.8)
	c3d.rotation_degrees.x = -24.0 if is_me else 24.0
	c3d.scale = Vector3(1.18, 1.18, 1.18)

	var tw := c3d.create_tween()
	# 1) Meluncur & mendarat mantap ke Slot Spell
	tw.set_parallel(true)
	tw.tween_property(c3d, "position", slot_pos, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c3d, "rotation_degrees:x", 0.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c3d, "scale", Vector3(1.04, 1.04, 1.04), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) Tahan agar pemain jelas melihat kartu Spell aktif di Slot Spell
	tw.chain().tween_interval(0.78)
	# 3) Meluncur halus masuk ke tumpukan Discard Pile
	tw.chain().set_parallel(true)
	tw.tween_property(c3d, "position", disc_pos, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c3d, "scale", Vector3(0.76, 0.76, 0.76), 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(c3d.queue_free)

## Menampilkan 2 kartu unsur dasar yang menempel di bawah/belakang kartu senyawa
## (mirip kartu Energy di belakang Pokemon TCG Live). Mengembalikan posisi Y untuk kartu utama di atasnya.
func _spawn_attached_under(special_card: Dictionary, base_pos: Vector3, card_sz: Vector2) -> float:
	var attached: Array = special_card.get("attached", [])
	if attached.is_empty():
		var parts: Array = special_card.get("parts", [])
		for pid in parts:
			attached.append({"uid": -1, "id": String(pid), "placed_turn": -1})
	if attached.is_empty():
		return base_pos.y
	var offsets := [
		Vector3(0.095, 0.0, -0.055),
		Vector3(0.165, 0.034, -0.025),
	]
	var rots := [-4.0, -7.5]
	for idx in mini(attached.size(), 2):
		var ac: Dictionary = attached[idx]
		var off: Vector3 = offsets[idx]
		var node := _spawn_card(
			ac,
			base_pos + off,
			card_sz * 0.96,
			true, false, false, "", Color(0.86, 0.89, 0.93), false, false, false)
		node.rotation_degrees.y = rots[idx]
	return base_pos.y + 0.072

func _render_compound_table(ids: Array, my_base: Array, easy_mode: bool) -> void:
	var mine := {}
	for c in my_base:
		mine[c.id] = true
	var counts := {}
	var kinds: Array[String] = []
	for raw_id in ids:
		var sid := String(raw_id)
		counts[sid] = int(counts.get(sid, 0)) + 1
		if not kinds.has(sid):
			kinds.append(sid)
	var n := kinds.size()
	if n == 0:
		_prev_compound_counts = {}
		return
	var spacing := minf(1.02, 8.8 / float(maxi(n, 1)))
	var start_x := -0.35 - (float(n - 1) * spacing) * 0.5
	var deck_origin := Vector3(5.95, 0.42, -0.05)

	for i in n:
		var id: String = kinds[i]
		var d: CardData = CardDB.get_card(id)
		if d == null or d.recipe.size() != 2:
			continue
		var have := int(mine.has(d.recipe[0])) + int(mine.has(d.recipe[1]))
		var pos := Vector3(start_x + float(i) * spacing, 0.25, -0.05)
		var card_node := _spawn_card(
			{"uid": -1, "id": id, "placed_turn": -1},
			pos, SIZE_TABLE, true, false, true, "", Color.WHITE, false, false, false)
		card_node.rotation_degrees.x = 18.0   # menengadah jelas di atas rak 3D tanpa terpotong

		# Animasi bingkai pinggiran berdenyut seperti kartu di tangan (tanpa menimpa warna gambar)
		if have == 2:
			card_node.set_border_pulse(true, Color(0.32, 0.90, 0.58, 1.0))
		elif have == 1 and easy_mode:
			card_node.set_border_pulse(true, Color(0.95, 0.80, 0.30, 1.0))

		# Jika jumlah salinan senyawa ini baru berkurang (diambil sintesis) dan masih ada stok di deck,
		# animasikan kartu pengganti langsung meluncur keluar dari Deck Senyawa ke slot tengah!
		var prev_c := int(_prev_compound_counts.get(id, counts[id]))
		if int(counts[id]) < prev_c:
			card_node.position = deck_origin
			card_node.scale = Vector3(0.85, 0.85, 0.85)
			var tw := card_node.create_tween().set_parallel(true)
			tw.tween_property(card_node, "position", pos, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(card_node, "scale", Vector3.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_prev_compound_counts = counts

func _spawn_card(card: Dictionary, pos: Vector3, size_3d: Vector2,
		face_up: bool, can_click: bool, can_preview: bool,
		recipe_text: String, tint: Color, is_cd: bool, is_play: bool,
		animate_drop: bool, from_me := true) -> Node3D:
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
		c3d.position = Vector3(pos.x, pos.y + 1.15, pos.z + (2.2 if from_me else -2.2))
		c3d.rotation_degrees.x = -24.0 if from_me else 24.0
		c3d.scale = Vector3(1.14, 1.14, 1.14)
		var tw := c3d.create_tween().set_parallel(true)
		tw.tween_property(c3d, "position", pos, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c3d, "rotation_degrees:x", 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c3d, "scale", Vector3.ONE, 0.44).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func(): Audio.play_sfx("card_place", -1.5, 0.06))
	return c3d

# --- Bantuan Mesh & Material Matte -------------------------------------------

func _make_box(size: Vector3, color: Color, roughness: float, metallic: float,
		cast_shadows := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	m.material_override = mat
	return m

func _make_flat_bar(size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	mat.metallic = 0.08
	m.material_override = mat
	return m
