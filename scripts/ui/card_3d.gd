class_name Card3D
extends Node3D

## Kartu 3D di atas arena 2.5D.
## Memakai scenes/ui/card.tscn di dalam SubViewport (dibekukan setelah 2 frame)
## agar teks, simbol, poin, dan ilustrasi kartu tetap tajam dengan biaya render 0/frame.

signal clicked(uid: int)
signal preview_hover(data: Dictionary, source: Node)
signal preview_exit(source: Node)
signal preview_pin(data: Dictionary, source: Node)

const CARD_UI_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_THICKNESS := 0.035
const TEX_SIZE := Vector2i(240, 320)

const COLOR_EDGE := Color(0.14, 0.18, 0.24, 1.0)
const COLOR_BACK := Color(0.09, 0.14, 0.22, 1.0)
const COLOR_PLAYABLE := Color(0.35, 0.92, 0.58, 1.0)
const COLOR_HOVER := Color(0.45, 0.85, 1.0, 1.0)

var uid := -1
var interactive := false
var previewable := false
var card_size := Vector2(1.12, 1.50)

var _data := {}
var _hovered := false
var _playable := false
var _cooldown := false
var _tint := Color.WHITE

var _visual: Node3D
var _body_mesh: MeshInstance3D
var _front_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _front_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _viewport: SubViewport
var _card_ui: Node
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
	body_mat.metallic = 0.2
	_body_mesh.material_override = body_mat
	_visual.add_child(_body_mesh)

	# Muka kartu (tekstur dari SubViewport 2D)
	_front_mesh = MeshInstance3D.new()
	_front_mesh.name = "Front"
	_front_mesh.rotation_degrees.x = -90.0
	_front_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front_mat = StandardMaterial3D.new()
	_front_mat.roughness = 0.42
	_front_mat.metallic = 0.05
	_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_front_mesh.material_override = _front_mat
	_visual.add_child(_front_mesh)

	# Bingkai cahaya (untuk status playable & hover)
	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = "GlowRim"
	_glow_mesh.rotation_degrees.x = -90.0
	_glow_mesh.visible = false
	_glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.35, 0.92, 0.58, 0.85)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = COLOR_PLAYABLE
	_glow_mat.emission_energy_multiplier = 1.6
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mesh.material_override = _glow_mat
	_visual.add_child(_glow_mesh)

	# SubViewport off-screen untuk merender tampilan kartu 2D
	_viewport = SubViewport.new()
	_viewport.name = "CardViewport"
	_viewport.size = TEX_SIZE
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_card_ui = CARD_UI_SCENE.instantiate()
	_viewport.add_child(_card_ui)

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
		can_preview := true, recipe_text := "", tint := Color.WHITE,
		is_cooldown := false, is_playable := false) -> void:
	uid = int(card.get("uid", -1))
	card_size = size_3d
	interactive = can_click
	_data = card.duplicate()
	_tint = tint
	_cooldown = is_cooldown
	var id := String(card.get("id", ""))
	var show_face := face_up and id != "back" and CardDB.cards.has(id)
	previewable = can_preview and show_face

	_apply_geometry()

	_card_ui.setup(card, face_up, false, false)
	_card_ui.fit(Vector2(TEX_SIZE))
	_card_ui.position = Vector2.ZERO
	_card_ui.size = Vector2(TEX_SIZE)
	if recipe_text != "":
		var desc: Label = _card_ui.get_node("V/Desc")
		desc.text = recipe_text
		desc.visible = true
		desc.add_theme_font_size_override("font_size", 22)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tint != Color.WHITE:
		_card_ui.modulate = tint

	_front_mat.albedo_texture = _viewport.get_texture()
	_front_mat.albedo_color = Color(0.55, 0.55, 0.62, 1.0) if is_cooldown else Color.WHITE
	if not show_face:
		_front_mat.albedo_color = COLOR_BACK

	_area.input_ray_pickable = interactive or previewable
	set_playable(is_playable)

	# Render 2 frame supaya layout Control di SubViewport beres, lalu bekukan (0 biaya/frame)
	_freeze_viewport_soon()

func _apply_geometry() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(card_size.x, CARD_THICKNESS, card_size.y)
	_body_mesh.mesh = box
	_body_mesh.position.y = CARD_THICKNESS * 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2(card_size.x * 0.96, card_size.y * 0.96)
	_front_mesh.mesh = quad
	_front_mesh.position.y = CARD_THICKNESS + 0.003

	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(card_size.x + 0.12, card_size.y + 0.12)
	_glow_mesh.mesh = glow_quad
	_glow_mesh.position.y = 0.008

	var col: CollisionShape3D = _area.get_node("Shape")
	var shape := col.shape as BoxShape3D
	shape.size = Vector3(card_size.x, 0.18, card_size.y)
	col.position.y = 0.09

func _freeze_viewport_soon() -> void:
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func set_playable(on: bool) -> void:
	_playable = on
	if _play_tween != null and _play_tween.is_valid():
		_play_tween.kill()
	_play_tween = null
	_update_glow_visual()

func _update_glow_visual() -> void:
	if _hovered and (interactive or previewable):
		if _play_tween != null and _play_tween.is_valid():
			_play_tween.kill()
		_glow_mesh.visible = true
		_glow_mat.albedo_color = Color(COLOR_HOVER.r, COLOR_HOVER.g, COLOR_HOVER.b, 0.85)
		_glow_mat.emission = COLOR_HOVER
		_glow_mat.emission_energy_multiplier = 2.0
		return
	if _playable:
		_glow_mesh.visible = true
		_glow_mat.albedo_color = Color(COLOR_PLAYABLE.r, COLOR_PLAYABLE.g, COLOR_PLAYABLE.b, 0.78)
		_glow_mat.emission = COLOR_PLAYABLE
		_glow_mat.emission_energy_multiplier = 1.5
		if _play_tween == null or not _play_tween.is_valid():
			_play_tween = create_tween().set_loops()
			_play_tween.tween_property(_glow_mat, "emission_energy_multiplier", 0.55, 0.65).set_trans(Tween.TRANS_SINE)
			_play_tween.tween_property(_glow_mat, "emission_energy_multiplier", 1.75, 0.65).set_trans(Tween.TRANS_SINE)
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
