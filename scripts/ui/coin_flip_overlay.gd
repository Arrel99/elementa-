extends CanvasLayer

## Overlay koin 3D logam besar untuk penentuan giliran awal pertandingan.

signal coin_call_chosen(side: String)
signal turn_order_chosen(go_first: bool)

@onready var _title: Label = $Root/Center/Card/V/Title
@onready var _world: Node3D = $Root/Center/Card/V/CoinArea/CoinViewport/SubViewport/CoinWorld
@onready var _call_row: HBoxContainer = $Root/Center/Card/V/CallButtons
@onready var _order_row: HBoxContainer = $Root/Center/Card/V/OrderButtons

var _coin_pivot: Node3D
var _is_animating := false
var _last_stage := ""
var _last_result := ""
var _pending_order_cp := {}
var _pending_local := false
var _pending_me_idx := 0
var _idle_t := 0.0
var _resting_y := 0.0

func _ready() -> void:
	hide()
	$Root/Center/Card/V/CallButtons/Heads.pressed.connect(func(): coin_call_chosen.emit("heads"))
	$Root/Center/Card/V/CallButtons/Tails.pressed.connect(func(): coin_call_chosen.emit("tails"))
	$Root/Center/Card/V/OrderButtons/First.pressed.connect(func(): turn_order_chosen.emit(true))
	$Root/Center/Card/V/OrderButtons/Second.pressed.connect(func(): turn_order_chosen.emit(false))
	_build_3d_coin_scene()

func _process(delta: float) -> void:
	if not visible or _coin_pivot == null or _is_animating:
		return
	# Goyangan 3D halus saat diam agar kilau logam dan ketebalan koin terasa nyata
	_idle_t += delta
	_coin_pivot.rotation.y = _resting_y + sin(_idle_t * 1.8) * 0.22
	_coin_pivot.rotation.x = cos(_idle_t * 1.4) * 0.12

# --- Membangun Koin Logam 3D -------------------------------------------------

func _build_3d_coin_scene() -> void:
	# Lingkungan & pencahayaan studio untuk kilau logam 3D
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.94, 1.0)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0.0, 0.15, 5.2)
	_world.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.97, 0.90, 1.0)
	key_light.light_energy = 1.85
	key_light.rotation_degrees = Vector3(-28.0, 32.0, 0.0)
	_world.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(0.68, 0.84, 1.0, 1.0)
	rim_light.light_energy = 1.15
	rim_light.rotation_degrees = Vector3(24.0, -142.0, 0.0)
	_world.add_child(rim_light)

	_coin_pivot = Node3D.new()
	_coin_pivot.name = "CoinPivot"
	_world.add_child(_coin_pivot)

	var radius := 1.28
	var thick := 0.18

	# Badan silinder koin logam (tebal nyata)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = thick
	cyl.radial_segments = 56
	body.mesh = cyl
	body.rotation_degrees.x = 90.0
	body.material_override = _metal_mat(Color(0.56, 0.50, 0.36), 0.30, 0.85)
	_coin_pivot.add_child(body)

	# === SISI DEPAN (+Z): HEADS (Emas / Perunggu + Emblem Atom Heksagon) ===
	var gold_mat := _metal_mat(Color(0.84, 0.66, 0.26), 0.26, 0.82)
	var gold_dark := _metal_mat(Color(0.46, 0.35, 0.14), 0.38, 0.72)

	var h_disc := _make_disc(radius * 0.96, 0.02, gold_dark)
	h_disc.position.z = thick * 0.5 + 0.004
	_coin_pivot.add_child(h_disc)

	var h_rim := _make_ring(radius * 0.88, radius * 1.01, 48, gold_mat)
	h_rim.position.z = thick * 0.5 + 0.015
	_coin_pivot.add_child(h_rim)

	var h_hex := _make_ring(0.46, 0.54, 6, gold_mat)
	h_hex.position = Vector3(0.0, 0.14, thick * 0.5 + 0.032)
	_coin_pivot.add_child(h_hex)

	var h_nuc := _make_sphere(0.18, gold_mat)
	h_nuc.position = Vector3(0.0, 0.14, thick * 0.5 + 0.038)
	_coin_pivot.add_child(h_nuc)

	var h_lbl := _make_coin_label("HEADS", Color(0.98, 0.88, 0.58))
	h_lbl.position = Vector3(0.0, -0.68, thick * 0.5 + 0.035)
	_coin_pivot.add_child(h_lbl)

	# === SISI BELAKANG (-Z): TAILS (Perak / Biru Baja + Emblem Molekul H2O) ===
	var silver_mat := _metal_mat(Color(0.56, 0.76, 0.94), 0.24, 0.82)
	var steel_dark := _metal_mat(Color(0.16, 0.28, 0.42), 0.38, 0.72)

	var t_disc := _make_disc(radius * 0.96, 0.02, steel_dark)
	t_disc.position.z = -(thick * 0.5 + 0.004)
	_coin_pivot.add_child(t_disc)

	var t_rim := _make_ring(radius * 0.88, radius * 1.01, 48, silver_mat)
	t_rim.position.z = -(thick * 0.5 + 0.015)
	_coin_pivot.add_child(t_rim)

	# Molekul H2O timbul 3D di sisi TAILS
	var m_o := _make_sphere(0.24, silver_mat)
	m_o.position = Vector3(0.0, 0.30, -(thick * 0.5 + 0.04))
	_coin_pivot.add_child(m_o)

	var m_h1 := _make_sphere(0.16, silver_mat)
	m_h1.position = Vector3(-0.38, -0.06, -(thick * 0.5 + 0.04))
	_coin_pivot.add_child(m_h1)

	var m_h2 := _make_sphere(0.16, silver_mat)
	m_h2.position = Vector3(0.38, -0.06, -(thick * 0.5 + 0.04))
	_coin_pivot.add_child(m_h2)

	var b1 := _make_bond(Vector3(-0.19, 0.12, -(thick * 0.5 + 0.035)), 46.0, silver_mat)
	_coin_pivot.add_child(b1)
	var b2 := _make_bond(Vector3(0.19, 0.12, -(thick * 0.5 + 0.035)), -46.0, silver_mat)
	_coin_pivot.add_child(b2)

	var t_lbl := _make_coin_label("TAILS", Color(0.84, 0.94, 1.0))
	t_lbl.position = Vector3(0.0, -0.68, -(thick * 0.5 + 0.035))
	t_lbl.rotation_degrees.y = 180.0
	_coin_pivot.add_child(t_lbl)

func _metal_mat(col: Color, rough: float, met: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = met
	return m

func _make_disc(r: float, h: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 48
	m.mesh = c
	m.rotation_degrees.x = 90.0
	m.material_override = mat
	return m

func _make_ring(inner_r: float, outer_r: float, segs: int, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner_r
	t.outer_radius = outer_r
	t.rings = segs
	t.ring_segments = 12
	m.mesh = t
	m.rotation_degrees.x = 90.0
	m.material_override = mat
	return m

func _make_sphere(r: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	m.mesh = s
	m.material_override = mat
	return m

func _make_bond(pos: Vector3, rot_z: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.05
	c.height = 0.48
	m.mesh = c
	m.position = pos
	m.rotation_degrees.z = rot_z
	m.material_override = mat
	return m

func _make_coin_label(txt: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 64
	l.pixel_size = 0.0042
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.06, 0.08, 0.9)
	return l

# --- Sinkronisasi & Animasi Lempar Koin 3D -----------------------------------

func sync(v: Dictionary, is_local_test: bool) -> void:
	var cp: Dictionary = v.get("coin_phase", {})
	if cp.is_empty():
		_last_stage = ""
		_last_result = ""
		_is_animating = false
		hide()
		return

	show()
	var stage := String(cp.get("stage", ""))
	var me_idx := int(v.get("me_index", 0))

	if stage == "pick_call":
		if _last_stage != "pick_call":
			_last_stage = "pick_call"
			_last_result = ""
			_resting_y = 0.0
			_coin_pivot.position = Vector3.ZERO
			_coin_pivot.rotation = Vector3.ZERO
		var caller := int(cp.get("caller", 0))
		var can_call := is_local_test or (caller == me_idx)
		if is_local_test:
			_title.text = "Pemain %d — Heads atau Tails?" % (caller + 1)
		elif can_call:
			_title.text = "Heads atau Tails?"
		else:
			_title.text = "Menunggu lawan..."
		_call_row.visible = can_call
		_order_row.visible = false

	elif stage == "pick_order":
		var res := String(cp.get("result", "heads"))
		_pending_order_cp = cp.duplicate(true)
		_pending_local = is_local_test
		_pending_me_idx = me_idx
		if _last_result != res or _last_stage != "pick_order":
			_last_stage = "pick_order"
			_last_result = res
			_play_flip_animation(res)
		elif not _is_animating:
			_show_order_choice()

func _play_flip_animation(result_side: String) -> void:
	_is_animating = true
	_call_row.visible = false
	_order_row.visible = false
	_title.text = "Memutar koin..."

	# Putar 3D nyata pada sumbu Y: 0 / 2*PI = HEADS (+Z), PI = TAILS (-Z)
	var spins := 6
	var target_y := float(spins * 2) * PI + (0.0 if result_side == "heads" else PI)
	_resting_y = 0.0 if result_side == "heads" else PI
	_coin_pivot.position = Vector3.ZERO
	_coin_pivot.rotation = Vector3.ZERO

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_coin_pivot, "rotation:y", target_y, 1.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin_pivot, "position:y", 0.55, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin_pivot, "rotation:x", 0.35, 0.52).set_trans(Tween.TRANS_SINE)
	tw.chain().set_parallel(true)
	tw.tween_property(_coin_pivot, "position:y", 0.0, 0.58).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin_pivot, "rotation:x", 0.0, 0.58).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.20)
	tw.chain().tween_callback(func():
		_coin_pivot.rotation.y = _resting_y
		_is_animating = false
		_show_order_choice())

func _show_order_choice() -> void:
	var cp := _pending_order_cp
	if cp.is_empty():
		return
	var res := String(cp.get("result", "heads")).to_upper()
	var win_p := int(cp.get("winner", 0))
	var can_pick := _pending_local or (win_p == _pending_me_idx)

	if _pending_local:
		_title.text = "%s — Pemain %d pilih giliran" % [res, win_p + 1]
	elif can_pick:
		_title.text = "%s — Pilih giliran" % res
	else:
		_title.text = "%s — Lawan memilih giliran..." % res

	_call_row.visible = false
	_order_row.visible = can_pick
