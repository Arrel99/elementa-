class_name Card3D
extends Node3D

## Kartu 3D di atas arena 2.5D menggunakan tekstur full-art PNG langsung
## (tanpa SubViewport sehingga jauh lebih tajam, instan, dan hemat memori).

signal clicked(uid: int)
signal preview_hover(data: Dictionary, source: Node)
signal preview_exit(source: Node)
signal preview_pin(data: Dictionary, source: Node)

const CARD_BACK_SCRIPT := preload("res://scripts/ui/card_back_art.gd")
const CARD_THICKNESS := 0.052

const COLOR_EDGE := Color(0.14, 0.17, 0.21, 1.0)
const COLOR_PLAYABLE := Color(0.38, 0.84, 0.60, 1.0)
const COLOR_HOVER := Color(0.82, 0.90, 0.98, 1.0)

var uid := -1
var interactive := false
var previewable := false
var card_size := Vector2(1.12, 1.50)

var _data := {}
var _hovered := false
var _playable := false
var _pulse_color := COLOR_PLAYABLE

var _visual: Node3D
var _body_mesh: MeshInstance3D
var _front_mesh: MeshInstance3D
var _back_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _front_mat: StandardMaterial3D
var _back_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _area: Area3D
var _hover_tween: Tween
var _play_tween: Tween

func _init() -> void:
	_build_nodes()

func _build_nodes() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# Badan kartu (ketebalan 3D)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_EDGE
	body_mat.roughness = 0.55
	body_mat.metallic = 0.16
	_body_mesh.material_override = body_mat
	_visual.add_child(_body_mesh)

	# Muka depan kartu (langsung memakai tekstur full-art PNG!)
	_front_mesh = MeshInstance3D.new()
	_front_mesh.name = "Front"
	_front_mesh.rotation_degrees.x = -90.0
	_front_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front_mat = StandardMaterial3D.new()
	_front_mat.roughness = 0.72
	_front_mat.metallic = 0.02
	_front_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_front_mat.alpha_scissor_threshold = 0.25
	_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_front_mesh.material_override = _front_mat
	_visual.add_child(_front_mesh)

	# Sisi belakang kartu 3D (bermotif Elementa)
	_back_mesh = MeshInstance3D.new()
	_back_mesh.name = "Back"
	_back_mesh.rotation_degrees.x = 90.0
	_back_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_back_mat = StandardMaterial3D.new()
	_back_mat.albedo_texture = CARD_BACK_SCRIPT.make_back_texture(
		Color(0.11, 0.145, 0.195, 1.0), Color(0.38, 0.58, 0.76, 1.0))
	_back_mat.roughness = 0.52
	_back_mat.metallic = 0.08
	_back_mesh.material_override = _back_mat
	_visual.add_child(_back_mesh)

	# Bingkai penanda bersih (status playable & hover)
	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = "GlowRim"
	_glow_mesh.rotation_degrees.x = -90.0
	_glow_mesh.visible = false
	_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(COLOR_PLAYABLE.r, COLOR_PLAYABLE.g, COLOR_PLAYABLE.b, 0.90)
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mesh.material_override = _glow_mat
	_visual.add_child(_glow_mesh)

	# Area3D untuk raycast klik & hover mouse
	_area = Area3D.new()
	_area.name = "PickArea"
	_area.input_ray_pickable = true
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = BoxShape3D.new()
	_area.add_child(col)
	add_child(_area)

	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)
	_area.input_event.connect(_on_input_event)

func setup(card: Dictionary, size_3d: Vector2, face_up := true, can_click := true,
		can_preview := true, _recipe_text := "", tint := Color.WHITE,
		is_cooldown := false, is_playable := false) -> void:
	uid = int(card.get("uid", -1))
	card_size = size_3d
	interactive = can_click
	_data = card.duplicate(true)
	var id := String(card.get("id", ""))
	var show_face := face_up and id != "back" and CardDB.cards.has(id)
	previewable = can_preview and show_face

	_apply_geometry()

	if show_face:
		var d: CardData = CardDB.get_card(id)
		_front_mat.albedo_texture = d.art if d != null else null
		var col := tint
		if is_cooldown:
			col = col * Color(0.55, 0.56, 0.62, 1.0)
		_front_mat.albedo_color = col
	else:
		_front_mat.albedo_texture = _back_mat.albedo_texture
		_front_mat.albedo_color = Color.WHITE

	_area.input_ray_pickable = interactive or previewable
	set_playable(is_playable)

func _apply_geometry() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(card_size.x * 0.96, CARD_THICKNESS, card_size.y * 0.96)
	_body_mesh.mesh = box
	_body_mesh.position.y = CARD_THICKNESS * 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2(card_size.x, card_size.y)
	_front_mesh.mesh = quad
	_front_mesh.position.y = CARD_THICKNESS + 0.003

	var back_quad := QuadMesh.new()
	back_quad.size = Vector2(card_size.x, card_size.y)
	_back_mesh.mesh = back_quad
	_back_mesh.position.y = -0.002

	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(card_size.x + 0.11, card_size.y + 0.11)
	_glow_mesh.mesh = glow_quad
	_glow_mesh.position.y = 0.012

	var col: CollisionShape3D = _area.get_node("Shape")
	var shape := col.shape as BoxShape3D
	shape.size = Vector3(card_size.x, 0.20, card_size.y)
	col.position.y = 0.10

func set_playable(on: bool) -> void:
	set_border_pulse(on, COLOR_PLAYABLE)

## Animasi bingkai pinggiran kartu berdenyut (hijau untuk siap main/sintesis, kuning/amber untuk 1/2 bahan).
func set_border_pulse(on: bool, col: Color = COLOR_PLAYABLE) -> void:
	_playable = on
	_pulse_color = col
	if _play_tween != null and _play_tween.is_valid():
		_play_tween.kill()
	_play_tween = null
	_update_glow_visual()

func _update_glow_visual() -> void:
	if _hovered and (interactive or previewable):
		if _play_tween != null and _play_tween.is_valid():
			_play_tween.kill()
		_glow_mesh.visible = true
		_glow_mat.albedo_color = Color(COLOR_HOVER.r, COLOR_HOVER.g, COLOR_HOVER.b, 0.88)
		return
	if _playable:
		_glow_mesh.visible = true
		_glow_mat.albedo_color = Color(_pulse_color.r, _pulse_color.g, _pulse_color.b, 0.92)
		if _play_tween == null or not _play_tween.is_valid():
			_play_tween = create_tween().set_loops()
			_play_tween.tween_property(_glow_mat, "albedo_color:a", 0.35, 0.65).set_trans(Tween.TRANS_SINE)
			_play_tween.tween_property(_glow_mat, "albedo_color:a", 0.95, 0.65).set_trans(Tween.TRANS_SINE)
	else:
		_glow_mesh.visible = false

func is_hovered_3d() -> bool:
	return _hovered

func _on_mouse_entered() -> void:
	if not (interactive or previewable):
		return
	_hovered = true
	_animate_hover(true)
	_update_glow_visual()
	if previewable:
		preview_hover.emit(_data, self)

func _on_mouse_exited() -> void:
	if not _hovered:
		return
	_hovered = false
	_animate_hover(false)
	_update_glow_visual()
	if previewable:
		preview_exit.emit(self)

func _animate_hover(on: bool) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true)
	var target_y := 0.24 if on else 0.0
	var target_tilt := 14.0 if on else 0.0
	var target_scale := Vector3(1.06, 1.0, 1.06) if on else Vector3.ONE
	_hover_tween.tween_property(_visual, "position:y", target_y, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_visual, "rotation_degrees:x", target_tilt, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_visual, "scale", target_scale, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and interactive:
		clicked.emit(uid)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and previewable:
		preview_pin.emit(_data, self)
