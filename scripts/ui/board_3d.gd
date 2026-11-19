class_name Board3D
extends Node3D

## Arena permainan 2.5D bertema sains/kimia (3D tabletop + shader molekul +
## warna wilayah berbeda untuk pemain & lawan + tumpukan kartu 3D).
## Dipasang di dalam SubViewport pada scenes/screens/game.tscn.

signal card_clicked(uid: int)
signal card_preview_hover(data: Dictionary, source: Node)
signal card_preview_exit(source: Node)
signal card_preview_pin(data: Dictionary, source: Node)

const CARD_3D_SCRIPT := preload("res://scripts/ui/card_3d.gd")
const SCIENCE_SHADER := preload("res://shaders/science_board.gdshader")

const SIZE_BASE := Vector2(1.04, 1.38)
const SIZE_SPECIAL := Vector2(0.82, 1.08)
const SIZE_SEN := Vector2(0.88, 1.18)
const SIZE_TABLE := Vector2(0.80, 1.06)
const SIZE_PILE := Vector2(0.88, 1.18)

const CAM_BASE_POS := Vector3(0.45, 10.6, 8.2)
const CAM_LOOK_TARGET := Vector3(0.45, -0.25, 0.15)

# Palet warna dua pemain + zona reaksi tengah
const COLOR_ME_PAD := Color(0.045, 0.115, 0.195, 1.0)
const COLOR_ME_SLOT_BG := Color(0.032, 0.082, 0.145, 1.0)
const COLOR_ME_ACCENT := Color(0.18, 0.76, 1.0, 1.0)

const COLOR_OPP_PAD := Color(0.185, 0.052, 0.082, 1.0)
const COLOR_OPP_SLOT_BG := Color(0.135, 0.035, 0.058, 1.0)
const COLOR_OPP_ACCENT := Color(1.0, 0.32, 0.40, 1.0)

const COLOR_MID_PAD := Color(0.042, 0.135, 0.125, 1.0)
const COLOR_MID_SLOT_BG := Color(0.032, 0.095, 0.090, 1.0)
const COLOR_MID_ACCENT := Color(0.22, 0.92, 0.68, 1.0)

const COLOR_GLOW := Color(0.32, 0.95, 0.72, 1.0)

var _camera: Camera3D
var _cards_root: Node3D
var _glows: Dictionary = {}          # zone_name -> Node3D
var _glow_mats: Dictionary = {}      # zone_name -> StandardMaterial3D
var _glow_tween: Tween

var _piles: Dictionary = {}          # pile_key -> { "mesh": MeshInstance3D, "count": Label3D }
var _shields: Dictionary = {}        # "me" | "opp" -> { "ring": MeshInstance3D, "label": Label3D }
var _atoms: Array = []               # list of { "ring1": Node3D, "ring2": Node3D, "speed": float }

var _known_uids := {}                # uid yang sudah ada di papan pada render sebelumnya
var _time := 0.0

func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_lights()
	_build_table()
	_build_science_decor()
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

	# Animasi orbital elektron pada dekorasi atom 3D di pinggir arena
	for a in _atoms:
		var spd: float = a.speed
		(a.ring1 as Node3D).rotation.y = _time * spd
		(a.ring2 as Node3D).rotation.y = -_time * spd * 0.82
		(a.ring2 as Node3D).rotation.z = sin(_time * 0.6) * 0.25 + 0.65

# --- Lingkungan, Kamera, dan Pencahayaan -------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.042, 0.068, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.72, 0.86, 1.0)
	env.ambient_light_energy = 0.78
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.22
	env.glow_hdr_threshold = 0.95
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
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.8
	sun.rotation_degrees = Vector3(-58.0, 22.0, 0.0)
	add_child(sun)

	# Cahaya wilayah pemain (biru-cyan lab)
	var me_light := OmniLight3D.new()
	me_light.name = "MeAccentLight"
	me_light.light_color = COLOR_ME_ACCENT
	me_light.light_energy = 2.4
	me_light.omni_range = 16.0
	me_light.position = Vector3(0.0, 4.4, 4.2)
	add_child(me_light)

	# Cahaya wilayah lawan (merah-crimson energi)
	var opp_light := OmniLight3D.new()
	opp_light.name = "OppAccentLight"
	opp_light.light_color = COLOR_OPP_ACCENT
	opp_light.light_energy = 2.4
	opp_light.omni_range = 16.0
	opp_light.position = Vector3(0.0, 4.4, -4.4)
	add_child(opp_light)

	# Cahaya aksen zona reaksi tengah (hijau-teal)
	var mid_light := OmniLight3D.new()
	mid_light.name = "MidReactionLight"
	mid_light.light_color = COLOR_MID_ACCENT
	mid_light.light_energy = 1.35
	mid_light.omni_range = 10.0
	mid_light.position = Vector3(-0.35, 3.2, -0.05)
	add_child(mid_light)

# --- Meja & Playmat Sains 3D -------------------------------------------------

func _build_table() -> void:
	var table := Node3D.new()
	table.name = "Table"
	add_child(table)

	# Permukaan playmat penuh memenuhi layar dengan shader kisi heksagonal kimia + dua warna wilayah
	var mat_plane := MeshInstance3D.new()
	mat_plane.name = "SciencePlaymat"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 28.0)
	mat_plane.mesh = pm
	mat_plane.position = Vector3(0.0, -0.008, 0.0)
	var sh_mat := ShaderMaterial.new()
	sh_mat.shader = SCIENCE_SHADER
	mat_plane.material_override = sh_mat
	table.add_child(mat_plane)

	# Panel wilayah LAWAN (merah-crimson gelap)
	var opp_pad := _make_box(Vector3(14.5, 0.016, 3.45), COLOR_OPP_PAD, 0.58, 0.22)
	opp_pad.position = Vector3(-0.15, -0.004, -2.52)
	table.add_child(opp_pad)

	# Panel wilayah PEMAIN (biru-cyan gelap)
	var me_pad := _make_box(Vector3(14.5, 0.016, 3.45), COLOR_ME_PAD, 0.58, 0.22)
	me_pad.position = Vector3(-0.15, -0.004, 2.42)
	table.add_child(me_pad)

	# Panel ruang reaksi TENGAH (hijau-teal)
	var mid_pad := _make_box(Vector3(14.5, 0.014, 1.46), COLOR_MID_PAD, 0.55, 0.25)
	mid_pad.position = Vector3(-0.15, -0.003, -0.05)
	table.add_child(mid_pad)

	# Rel energi menyala di batas zona reaksi tengah
	var rail_top := _make_emissive_bar(Vector3(36.0, 0.016, 0.042), COLOR_OPP_ACCENT.lerp(COLOR_MID_ACCENT, 0.45), 1.45)
	rail_top.position = Vector3(0.0, 0.008, -0.78)
	table.add_child(rail_top)

	var rail_bot := _make_emissive_bar(Vector3(36.0, 0.016, 0.042), COLOR_ME_ACCENT.lerp(COLOR_MID_ACCENT, 0.45), 1.45)
	rail_bot.position = Vector3(0.0, 0.008, 0.68)
	table.add_child(rail_bot)

	# Garis aksen tepi sisi pemain (cyan) & sisi lawan (crimson)
	var me_edge := _make_emissive_bar(Vector3(14.6, 0.02, 0.055), COLOR_ME_ACCENT, 1.7)
	me_edge.position = Vector3(-0.15, 0.01, 4.16)
	table.add_child(me_edge)

	var opp_edge := _make_emissive_bar(Vector3(14.6, 0.02, 0.055), COLOR_OPP_ACCENT, 1.7)
	opp_edge.position = Vector3(-0.15, 0.01, -4.26)
	table.add_child(opp_edge)

	# Garis sirkuit pemisah vertikal antar kolom zona (sisi pemain & lawan)
	for x_div in [-3.18, 3.98, 5.28]:
		var line_me := _make_emissive_bar(Vector3(0.026, 0.012, 3.25), COLOR_ME_ACCENT, 0.95)
		line_me.position = Vector3(x_div, 0.007, 2.42)
		table.add_child(line_me)
		var line_opp := _make_emissive_bar(Vector3(0.026, 0.012, 3.25), COLOR_OPP_ACCENT, 0.95)
		line_opp.position = Vector3(x_div, 0.007, -2.52)
		table.add_child(line_opp)

	# Label zona di permukaan meja
	_add_zone_label(table, "ZONA SENYAWA LAWAN", Vector3(-4.95, 0.016, -3.82), Color(1.0, 0.62, 0.66))
	_add_zone_label(table, "ZONA DASAR LAWAN", Vector3(0.35, 0.016, -3.44), Color(1.0, 0.62, 0.66))
	_add_zone_label(table, "TABEL REAKSI SENYAWA", Vector3(-0.35, 0.016, -0.68), Color(0.55, 0.96, 0.84))
	_add_zone_label(table, "ZONA SENYAWA KAMU", Vector3(-4.95, 0.016, 3.74), Color(0.58, 0.88, 1.0))
	_add_zone_label(table, "ZONA DASAR KAMU", Vector3(0.35, 0.016, 3.32), Color(0.58, 0.88, 1.0))
	_add_zone_label(table, "SENYAWA TERAKHIR", Vector3(4.60, 0.016, -3.30), Color(1.0, 0.68, 0.70))
	_add_zone_label(table, "SENYAWA TERAKHIR", Vector3(4.60, 0.016, 3.18), Color(0.58, 0.88, 1.0))

func _add_zone_label(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 24
	lbl.pixel_size = 0.0085
	lbl.modulate = color
	lbl.outline_size = 5
	lbl.outline_modulate = Color(0.02, 0.03, 0.06, 0.95)
	lbl.rotation_degrees.x = -90.0
	lbl.position = pos
	parent.add_child(lbl)

# --- Dekorasi Sains / Kimia 3D di Latar & Pinggir Arena ----------------------

func _build_science_decor() -> void:
	var decor := Node3D.new()
	decor.name = "ScienceDecor"
	add_child(decor)

	# 1) Model atom 3D berputar di sisi kiri & kanan latar (biru untuk pemain, merah untuk lawan)
	_build_atom_emblem(decor, Vector3(-7.75, 0.42, 2.35), COLOR_ME_ACCENT, 0.68, 1.15)
	_build_atom_emblem(decor, Vector3(-7.75, 0.42, -2.45), COLOR_OPP_ACCENT, 0.68, -1.05)
	_build_atom_emblem(decor, Vector3(7.45, 0.42, 2.35), COLOR_ME_ACCENT, 0.56, 1.3)
	_build_atom_emblem(decor, Vector3(7.45, 0.42, -2.45), COLOR_OPP_ACCENT, 0.56, -1.2)

	# 2) Cincin molekul benzena (heksagon + ikatan atom) di sudut luar papan
	_build_benzene_ring(decor, Vector3(-7.4, 0.02, -0.05), 0.72, COLOR_MID_ACCENT)
	_build_benzene_ring(decor, Vector3(7.35, 0.02, -0.05), 0.68, COLOR_MID_ACCENT)
	_build_benzene_ring(decor, Vector3(-7.9, 0.02, 3.85), 0.55, COLOR_ME_ACCENT)
	_build_benzene_ring(decor, Vector3(-7.9, 0.02, -3.95), 0.55, COLOR_OPP_ACCENT)
	_build_benzene_ring(decor, Vector3(7.6, 0.02, 3.85), 0.52, COLOR_ME_ACCENT)
	_build_benzene_ring(decor, Vector3(7.6, 0.02, -3.95), 0.52, COLOR_OPP_ACCENT)

	# 3) Node titik energi di persimpangan rel tengah
	for x_node in [-6.85, -3.18, 3.98, 5.28, 6.75]:
		_add_energy_node(decor, Vector3(x_node, 0.024, -0.78), COLOR_OPP_ACCENT.lerp(COLOR_MID_ACCENT, 0.45))
		_add_energy_node(decor, Vector3(x_node, 0.024, 0.68), COLOR_ME_ACCENT.lerp(COLOR_MID_ACCENT, 0.45))

func _build_atom_emblem(parent: Node3D, pos: Vector3, color: Color, radius: float, speed: float) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)

	# Inti atom menyala
	var nuc := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = radius * 0.22
	sp.height = radius * 0.44
	nuc.mesh = sp
	nuc.material_override = _make_emissive_mat(color, 2.2)
	root.add_child(nuc)

	# Dua cincin orbit elektron miring
	var ring1 := _make_orbit_ring(radius, color)
	ring1.rotation_degrees = Vector3(58.0, 0.0, 24.0)
	root.add_child(ring1)

	var ring2 := _make_orbit_ring(radius * 0.92, color.lightened(0.25))
	ring2.rotation_degrees = Vector3(-52.0, 40.0, -28.0)
	root.add_child(ring2)

	_atoms.append({"ring1": ring1, "ring2": ring2, "speed": speed})

func _make_orbit_ring(radius: float, color: Color) -> Node3D:
	var holder := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.022
	torus.outer_radius = radius + 0.022
	torus.rings = 28
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _make_emissive_mat(color, 1.5)
	holder.add_child(ring)

	# Elektron kecil yang mengorbit di cincin
	var el := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.065
	sp.height = 0.13
	el.mesh = sp
	el.material_override = _make_emissive_mat(Color.WHITE.lerp(color, 0.35), 2.8)
	el.position = Vector3(radius, 0.0, 0.0)
	holder.add_child(el)
	return holder

func _build_benzene_ring(parent: Node3D, pos: Vector3, radius: float, color: Color) -> void:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)

	# Cincin heksagonal luar (6 sisi)
	var outer := MeshInstance3D.new()
	var t_out := TorusMesh.new()
	t_out.inner_radius = radius - 0.024
	t_out.outer_radius = radius + 0.024
	t_out.rings = 6
	t_out.ring_segments = 6
	outer.mesh = t_out
	outer.material_override = _make_emissive_mat(color, 1.25)
	holder.add_child(outer)

	# Cincin resonansi dalam
	var inner := MeshInstance3D.new()
	var t_in := TorusMesh.new()
	t_in.inner_radius = radius * 0.62 - 0.014
	t_in.outer_radius = radius * 0.62 + 0.014
	t_in.rings = 18
	t_in.ring_segments = 6
	inner.mesh = t_in
	inner.material_override = _make_emissive_mat(color, 0.9)
	holder.add_child(inner)

	# Titik atom di ke-6 sudut heksagon
	var dot_mat := _make_emissive_mat(color.lightened(0.35), 2.0)
	for i in 6:
		var ang := float(i) * TAU / 6.0
		var dot := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.055
		sp.height = 0.11
		dot.mesh = sp
		dot.material_override = dot_mat
		dot.position = Vector3(cos(ang) * radius, 0.02, sin(ang) * radius)
		holder.add_child(dot)

func _add_energy_node(parent: Node3D, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.085
	cyl.bottom_radius = 0.095
	cyl.height = 0.03
	cyl.radial_segments = 6
	m.mesh = cyl
	m.position = pos
	m.material_override = _make_emissive_mat(color, 2.0)
	parent.add_child(m)

# --- Slot Zona ---------------------------------------------------------------

func _build_all_slots() -> void:
	var slots := Node3D.new()
	slots.name = "Slots"
	add_child(slots)

	# 6 slot Base lawan (merah) & pemain (biru-cyan)
	for i in 6:
		_add_slot_frame(slots, _pos_base(false, i), SIZE_BASE, COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
		_add_slot_frame(slots, _pos_base(true, i), SIZE_BASE, COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)

	# 8 slot Special (2x4) lawan & pemain
	for i in 8:
		_add_slot_frame(slots, _pos_special(false, i), SIZE_SPECIAL, COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
		_add_slot_frame(slots, _pos_special(true, i), SIZE_SPECIAL, COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)

	# Slot Senyawa Terakhir
	_add_slot_frame(slots, _pos_sen(false), SIZE_SEN, COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
	_add_slot_frame(slots, _pos_sen(true), SIZE_SEN, COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)

	# Panel dasar Tabel Senyawa di tengah (hijau-teal)
	var table_pad := _make_box(Vector3(9.4, 0.012, 1.26), COLOR_MID_SLOT_BG, 0.65, 0.18)
	table_pad.position = Vector3(-0.35, 0.006, -0.05)
	slots.add_child(table_pad)

func _add_slot_frame(parent: Node3D, pos: Vector3, size: Vector2, pad_col: Color, border_col: Color) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(pos.x, 0.008, pos.z)
	parent.add_child(holder)

	# Alas slot cekung berwarna sesuai wilayah pemain
	var pad := _make_box(Vector3(size.x, 0.008, size.y), pad_col, 0.72, 0.12)
	holder.add_child(pad)

	# 4 garis tepi slot menyala halus
	var t := 0.024
	var dim_col := border_col * 0.78
	var top := _make_emissive_bar(Vector3(size.x + t, 0.012, t), dim_col, 0.8)
	top.position = Vector3(0.0, 0.004, -size.y * 0.5)
	holder.add_child(top)

	var bot := _make_emissive_bar(Vector3(size.x + t, 0.012, t), dim_col, 0.8)
	bot.position = Vector3(0.0, 0.004, size.y * 0.5)
	holder.add_child(bot)

	var left := _make_emissive_bar(Vector3(t, 0.012, size.y + t), dim_col, 0.8)
	left.position = Vector3(-size.x * 0.5, 0.004, 0.0)
	holder.add_child(left)

	var right := _make_emissive_bar(Vector3(t, 0.012, size.y + t), dim_col, 0.8)
	right.position = Vector3(size.x * 0.5, 0.004, 0.0)
	holder.add_child(right)

	# Siku sudut lab beraksen terang (memberi nuansa sci-fi/sains pada tiap slot)
	var clen := minf(size.x, size.y) * 0.22
	var ct := 0.036
	var corners := [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
		Vector2(-1.0, 1.0), Vector2(1.0, 1.0),
	]
	for c in corners:
		var sx: float = c.x
		var sz: float = c.y
		var bx := _make_emissive_bar(Vector3(clen, 0.016, ct), border_col, 1.45)
		bx.position = Vector3(sx * (size.x * 0.5 - clen * 0.5), 0.006, sz * size.y * 0.5)
		holder.add_child(bx)
		var bz := _make_emissive_bar(Vector3(ct, 0.016, clen), border_col, 1.45)
		bz.position = Vector3(sx * size.x * 0.5, 0.006, sz * (size.y * 0.5 - clen * 0.5))
		holder.add_child(bz)

# --- Tumpukan Deck & Discard 3D ----------------------------------------------

func _build_piles() -> void:
	var root := Node3D.new()
	root.name = "Piles"
	add_child(root)

	_create_pile(root, "opp_deck", "DECK", Vector3(5.95, 0.0, -3.05), Color(0.42, 0.12, 0.17), COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
	_create_pile(root, "opp_discard", "BUANG", Vector3(5.95, 0.0, -1.62), Color(0.28, 0.11, 0.14), COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
	_create_pile(root, "compound_deck", "SENYAWA", Vector3(5.95, 0.0, -0.05), Color(0.10, 0.34, 0.30), COLOR_MID_SLOT_BG, COLOR_MID_ACCENT)
	_create_pile(root, "me_discard", "BUANG", Vector3(5.95, 0.0, 1.52), Color(0.11, 0.21, 0.33), COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)
	_create_pile(root, "me_deck", "DECK", Vector3(5.95, 0.0, 2.95), Color(0.12, 0.29, 0.48), COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)

func _create_pile(parent: Node3D, key: String, title: String, pos: Vector3,
		stack_col: Color, pad_col: Color, border_col: Color) -> void:
	_add_slot_frame(parent, pos, SIZE_PILE, pad_col, border_col)

	var stack := MeshInstance3D.new()
	stack.name = "Stack_" + key
	var box := BoxMesh.new()
	box.size = Vector3(SIZE_PILE.x * 0.92, 0.25, SIZE_PILE.y * 0.92)
	stack.mesh = box
	stack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = stack_col
	mat.roughness = 0.48
	mat.metallic = 0.24
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
	title_lbl.modulate = border_col.lightened(0.35)
	title_lbl.outline_size = 4
	title_lbl.outline_modulate = Color(0.02, 0.04, 0.08, 1.0)
	title_lbl.rotation_degrees.x = -90.0
	title_lbl.position = Vector3(pos.x, 0.018, pos.z + SIZE_PILE.y * 0.5 + 0.16)
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
	_create_shield_pad(root, "opp", Vector3(4.60, 0.0, -1.08), COLOR_OPP_SLOT_BG, COLOR_OPP_ACCENT)
	_create_shield_pad(root, "me", Vector3(4.60, 0.0, 0.98), COLOR_ME_SLOT_BG, COLOR_ME_ACCENT)

func _create_shield_pad(parent: Node3D, key: String, pos: Vector3, pad_col: Color, border_col: Color) -> void:
	_add_slot_frame(parent, pos, Vector2(0.92, 0.72), pad_col, border_col)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.34
	torus.rings = 16
	torus.ring_segments = 6        # heksagonal khas kimia!
	ring.mesh = torus
	var mat := _make_emissive_mat(border_col.lightened(0.2), 2.2)
	ring.material_override = mat
	ring.position = Vector3(pos.x, 0.14, pos.z)
	ring.visible = false
	parent.add_child(ring)

	var lbl := Label3D.new()
	lbl.text = "SPELL"
	lbl.font_size = 20
	lbl.pixel_size = 0.008
	lbl.modulate = border_col.lightened(0.35)
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.02, 0.04, 0.08, 1.0)
	lbl.rotation_degrees.x = -90.0
	lbl.position = Vector3(pos.x, 0.02, pos.z)
	parent.add_child(lbl)

	_shields[key] = {"ring": ring, "label": lbl, "accent": border_col}

func _update_shield(key: String, active: bool) -> void:
	if not _shields.has(key):
		return
	var info: Dictionary = _shields[key]
	var ring: MeshInstance3D = info.ring
	var lbl: Label3D = info.label
	var acc: Color = info.accent
	ring.visible = active
	lbl.text = "PERISAI" if active else "SPELL"
	lbl.modulate = acc.lightened(0.45) if active else acc.lerp(Color(0.6, 0.65, 0.72), 0.5)

# --- Bingkai Glow Zona Target ------------------------------------------------

func _build_zone_glows() -> void:
	var root := Node3D.new()
	root.name = "ZoneGlows"
	add_child(root)

	_create_zone_glow(root, "my_base", Vector3(0.35, 0.028, 2.35), Vector2(7.16, 1.62))
	_create_zone_glow(root, "opp_base", Vector3(0.35, 0.028, -2.45), Vector2(7.16, 1.62))
	_create_zone_glow(root, "my_special", Vector3(-4.95, 0.028, 2.35), Vector2(3.86, 2.48))
	_create_zone_glow(root, "opp_special", Vector3(-4.95, 0.028, -2.45), Vector2(3.86, 2.48))

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
	return Vector3(x, 0.012, z)

func _pos_special(is_me: bool, idx: int) -> Vector3:
	var col := idx % 4
	var row := idx / 4
	var x := -6.36 + float(col) * 0.94
	var z := (1.75 + float(row) * 1.20) if is_me else (-3.05 + float(row) * 1.20)
	return Vector3(x, 0.012, z)

func _pos_sen(is_me: bool) -> Vector3:
	return Vector3(4.60, 0.012, 2.35 if is_me else -2.45)

# --- Render Seluruh Papan 3D -------------------------------------------------

func render_board(v: Dictionary, playable: Dictionary, easy_mode: bool) -> void:
	for ch in _cards_root.get_children():
		_cards_root.remove_child(ch)
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

# --- Bantuan Mesh & Material -------------------------------------------------

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
	m.material_override = _make_emissive_mat(color, energy)
	return m

func _make_emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
