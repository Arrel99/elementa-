extends CanvasLayer

## Embedded Tutorial interaktif di dalam arena 2.5D Elementa.
## Memandu pemain langkah demi langkah secara langsung sambil bermain:
## 1) Pasang 2 kartu unsur (H & O) ke Zona Dasar
## 2) Akhiri giliran (memahami cooldown 1 giliran)
## 3) Sintesis H + O menjadi Air (H2O)
## 4) Mainkan Spell Korosi untuk menghancurkan kartu lawan
## 5) Klik kanan kartu untuk memperbesar & melihat unsur menempel
## 6) Selesai — lanjut bermain atau kembali ke Menu Utama

signal back_to_menu_requested

const STEPS := [
	{
		"title": "Pasang 2 Unsur",
		"body": "Seret atau klik kartu H dan O dari tangan ke slot Zona Dasar.",
		"show_next": false,
	},
	{
		"title": "Cooldown 1 Giliran",
		"body": "Kartu yang baru dipasang butuh 1 giliran cooldown. Klik END TURN di kanan.",
		"show_next": false,
	},
	{
		"title": "Sintesis Senyawa",
		"body": "Klik kartu H lalu kartu O yang berdenyut hijau di Zona Dasar untuk membuat H2O.",
		"show_next": false,
	},
	{
		"title": "Mainkan Kartu Spell",
		"body": "Klik Spell Korosi di tangan (masuk Zona Spell), lalu klik kartu lawan untuk menghancurkannya.",
		"show_next": false,
	},
	{
		"title": "Perbesar Kartu",
		"body": "Klik kanan kartu senyawa di kiri untuk melihat detail & 2 unsur di belakangnya.",
		"show_next": true,
	},
	{
		"title": "Tutorial Selesai!",
		"body": "Kumpulkan 8 senyawa untuk langsung menang, atau unggul poin saat permainan selesai.",
		"show_next": true,
		"is_final": true,
	},
]

@onready var _banner: PanelContainer = $Banner
@onready var _badge: Label = $Banner/V/TopRow/Badge
@onready var _title: Label = $Banner/V/TopRow/Title
@onready var _skip_btn: Button = $Banner/V/TopRow/SkipBtn
@onready var _body: Label = $Banner/V/Body
@onready var _actions: HBoxContainer = $Banner/V/Actions
@onready var _menu_btn: Button = $Banner/V/Actions/MenuBtn
@onready var _next_btn: Button = $Banner/V/Actions/NextBtn

var _active := false
var _step := 0
var _turn_at_step1 := 1

func _ready() -> void:
	_banner.hide()
	_skip_btn.pressed.connect(stop)
	_next_btn.pressed.connect(_on_next_pressed)
	_menu_btn.pressed.connect(func():
		stop()
		back_to_menu_requested.emit())

func start() -> void:
	_active = true
	_step = 0
	_turn_at_step1 = 1
	_banner.show()
	_apply_step(false)

func stop() -> void:
	_active = false
	_banner.hide()

func is_active() -> bool:
	return _active

## Dipanggil setiap kali state papan diperbarui dari game.gd
func on_view_updated(v: Dictionary) -> void:
	if not _active or v.is_empty():
		return
	if int(v.get("winner", -2)) != -2:
		stop()
		return

	match _step:
		0:
			# Selesai langkah 1 saat pemain sudah memasang >= 2 kartu dasar
			if v.me.base.size() >= 2:
				_turn_at_step1 = int(v.get("turn_no", 1))
				_advance()
		1:
			# Selesai langkah 2 saat sudah kembali ke giliran pemain setelah AI selesai
			if bool(v.get("my_turn", false)) and int(v.get("turn_no", 1)) > _turn_at_step1:
				_advance()
		2:
			# Selesai langkah 3 saat pemain sudah menyintesis >= 1 senyawa
			if v.me.special.size() >= 1:
				_advance()
		3:
			# Selesai langkah 4 saat pemain sudah memainkan minimal 1 spell (dan tidak lagi pending)
			if v.pending.is_empty() and (int(v.get("spell_left", 1)) == 0 or not v.me.discard.is_empty()):
				_advance()

## Dipanggil saat pemain klik kanan untuk memperbesar kartu
func on_preview_pinned() -> void:
	if _active and _step == 4:
		_advance()

func _on_next_pressed() -> void:
	if not _active:
		return
	if _step >= STEPS.size() - 1:
		stop()
	else:
		_advance()

func _advance() -> void:
	if _step < STEPS.size() - 1:
		_step += 1
		Audio.play_sfx("turn_start", -4.0)
		_apply_step(true)

func _apply_step(animate: bool) -> void:
	var info: Dictionary = STEPS[_step]
	var is_final: bool = bool(info.get("is_final", false))
	_badge.text = "TUTORIAL %d / %d" % [_step + 1, STEPS.size()]
	_title.text = String(info.title)
	_body.text = String(info.body)
	_skip_btn.visible = not is_final
	_actions.visible = bool(info.get("show_next", false)) or is_final
	_menu_btn.visible = is_final
	_next_btn.text = "Lanjut Main" if is_final else "Lanjut"

	if animate:
		_banner.pivot_offset = _banner.size * 0.5
		_banner.scale = Vector2(0.96, 0.96)
		var tw := _banner.create_tween()
		tw.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
