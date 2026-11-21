extends CanvasLayer

## Tutorial interaktif bertahap (6 langkah) untuk Main Menu & akses cepat.
## Responsif mengikuti ukuran jendela dan bertema sains/kimia.

signal start_practice_requested

const STEPS := [
	{
		"badge": "LANGKAH 1 / 6  •  ARENA & TUJUAN",
		"title": "Selamat Datang di Laboratorium Elementa",
		"summary": "Elementa adalah duel kartu reaksi kimia untuk 2 pemain. Kumpulkan poin tertinggi dengan merangkai unsur menjadi senyawa!",
		"bullets": [
			"Wilayah BIRU (bawah) adalah areamu; wilayah MERAH (atas) adalah area lawan.",
			"Garis HIJAU di tengah adalah Tabel Reaksi Senyawa yang menunjukkan resep senyawa tersedia.",
			"Cara Menang: (1) Isi 8 senyawa untuk langsung menang, (2) Lawan kehabisan deck (Deck Out) saat menarik kartu, (3) Waktu 15 menit lawan habis, atau (4) Lawan menyerah."
		],
		"tip": "Tips: Kamu bisa memainkan berapa pun kartu di tangan tanpa batas maksimal kartu tangan."
	},
	{
		"badge": "LANGKAH 2 / 6  •  JENIS KARTU",
		"title": "Mengenal 3 Jenis Kartu Kimia",
		"summary": "Setiap deck berisi 60 kartu yang terdiri dari Unsur Dasar dan Spell, sedangkan Senyawa berada di Deck Senyawa bersama.",
		"bullets": [
			"KARTU DASAR (Unsur): H, O, C, N, Na, Cl, Ca, Cu, Fe, Ne. Dipasang ke Zona Dasar (maks. 6 slot) sebagai bahan reaksi.",
			"KARTU SPESIAL (Senyawa): H2O, CO2, CH4, NH3, NaCl, HCl, CaO, CuO, Fe2O3. Terbentuk dari 2 unsur di Zona Dasar -> poin jauh lebih besar!",
			"KARTU SPELL: Efek taktis (Katalis, Bilas, Korosi, Elektrolisis, Spektrometer, Perisai Inert). Jatah 1 spell per giliran (Katalis gratis)."
		],
		"tip": "Tips: Unsur Neon (Ne) adalah gas mulia — tidak bisa disintesis, tetapi bernilai 6 poin langsung saat terpasang!"
	},
	{
		"badge": "LANGKAH 3 / 6  •  PASANG UNSUR",
		"title": "Memasang Unsur & Aturan Cooldown",
		"summary": "Di giliranmu, mulailah dengan memasang kartu unsur dari tangan ke Zona Dasar.",
		"bullets": [
			"Kartu di tangan yang dapat dimainkan memiliki BINGKAI HIJAU BERDENYUT.",
			"Klik kartu unsur di tangan untuk langsung memasangnya ke Zona Dasar (maksimal 6 slot).",
			"Kartu unsur yang baru dipasang pada giliran ini tampil agak REDUP (cooldown) — unsur tersebut baru bisa disintesis pada giliran berikutnya."
		],
		"tip": "Tips: Kamu boleh memasang lebih dari satu kartu unsur di giliran yang sama selama slot Zona Dasar masih tersedia."
	},
	{
		"badge": "LANGKAH 4 / 6  •  SINTESIS SENYAWA",
		"title": "Menyintesis Senyawa di Tabel Reaksi",
		"summary": "Sintesis menggabungkan 2 unsur yang sudah siap (tidak cooldown) di Zona Dasarmu menjadi 1 kartu Senyawa bernilai tinggi.",
		"bullets": [
			"Pantau warna kartu di Tabel Reaksi tengah: HIJAU = 2 bahannya sudah lengkap di Zona Dasarmu, KUNING = baru 1 bahan.",
			"Klik unsur PERTAMA di Zona Dasarmu (zona akan menyala berkedip), lalu klik unsur PASANGANNYA.",
			"Kedua unsur masuk ke tumpukan buang, dan Senyawa baru otomatis masuk ke Zona Senyawamu + menambah poin! (Standar 1 sintesis/giliran; pakai Katalis untuk +1 sintesis)."
		],
		"tip": "Tips: Setiap senyawa di Tabel Reaksi punya 2 salinan. Jika habis, senyawa tersebut tidak bisa disintesis lagi!"
	},
	{
		"badge": "LANGKAH 5 / 6  •  SPELL & AKHIR GILIRAN",
		"title": "Memainkan Spell & Mengakhiri Giliran",
		"summary": "Gunakan kartu Spell di saat tepat untuk mempercepat reaksimu atau membongkar strategi lawan.",
		"bullets": [
			"Klik kartu Spell di tangan. Jika tanpa target (Katalis, Perisai Inert, Spektrometer), efek langsung aktif.",
			"Jika butuh target (Bilas, Korosi, Elektrolisis, Elektrolisis Paksa), zona target akan MENYALA BERKEDIP — klik kartu yang diinginkan di zona itu.",
			"Setelah selesai beraksi, klik tombol segi delapan END TURN di kanan. Di awal giliran berikutnya, kamu otomatis menarik 2 kartu."
		],
		"tip": "Tips: Perisai Inert melindungimu dari 1 serangan Korosi atau Elektrolisis Paksa lawan sampai awal giliranmu berikutnya."
	},
	{
		"badge": "LANGKAH 6 / 6  •  KONTROL & PEMANDU ADAPTIF",
		"title": "Kontrol Cepat & Panduan Saat Bermain",
		"summary": "Di dalam arena permainan, Pemandu Adaptif di sudut kiri atas akan otomatis membaca kondisi papan dan memberi tahu langkah terbaik berikutnya.",
		"bullets": [
			"HOVER (arahkan kursor) ke kartu mana pun di tangan atau papan 3D untuk melihat pratinjau besar.",
			"KLIK KANAN pada kartu untuk menahan (pin) pratinjau agar mudah dibaca; klik di luar atau tekan ESC untuk menutup.",
			"Tekan ESC kapan saja untuk membatalkan pilihan sintesis / target spell atau menutup panel pengaturan."
		],
		"tip": "Siap mencoba langsung? Klik tombol 'Latihan di Arena' di bawah untuk bermain dengan Pemandu Adaptif!"
	}
]

@onready var _root: Control = $Root
@onready var _card: PanelContainer = $Root/Center/Card
@onready var _badge: Label = $Root/Center/Card/V/TopBar/Badge
@onready var _title: Label = $Root/Center/Card/V/Title
@onready var _summary: Label = $Root/Center/Card/V/Summary
@onready var _bullets_box: VBoxContainer = $Root/Center/Card/V/BulletsPanel/Bullets
@onready var _tip: Label = $Root/Center/Card/V/TipPanel/Tip
@onready var _dots_box: HBoxContainer = $Root/Center/Card/V/Dots
@onready var _prev_btn: Button = $Root/Center/Card/V/Footer/Prev
@onready var _next_btn: Button = $Root/Center/Card/V/Footer/Next
@onready var _practice_btn: Button = $Root/Center/Card/V/Footer/Practice
@onready var _close_btn: Button = $Root/Center/Card/V/TopBar/Close

var _step := 0
var _dot_buttons: Array[Button] = []

func _ready() -> void:
	_root.hide()
	_prev_btn.pressed.connect(_on_prev)
	_next_btn.pressed.connect(_on_next)
	_practice_btn.pressed.connect(_on_practice)
	_close_btn.pressed.connect(close)
	$Root/Dim.gui_input.connect(_on_dim_input)
	get_viewport().size_changed.connect(_resize_card)
	_build_dots()
	_resize_card()

func open(start_step := 0) -> void:
	_step = clampi(start_step, 0, STEPS.size() - 1)
	_resize_card()
	_render_step()
	_root.show()

func close() -> void:
	_root.hide()

func is_open() -> bool:
	return _root.visible

func _unhandled_input(e: InputEvent) -> void:
	if not _root.visible:
		return
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_right"):
		if _step < STEPS.size() - 1:
			_on_next()
			get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_left"):
		if _step > 0:
			_on_prev()
			get_viewport().set_input_as_handled()

func _resize_card() -> void:
	if not is_instance_valid(_card):
		return
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(vp.x * 0.68, 560.0, 920.0)
	var h := clampf(vp.y * 0.78, 440.0, 680.0)
	_card.custom_minimum_size = Vector2(w, h)

func _build_dots() -> void:
	for ch in _dots_box.get_children():
		ch.queue_free()
	_dot_buttons.clear()
	for i in STEPS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 12)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_go_step.bind(i))
		_dots_box.add_child(b)
		_dot_buttons.append(b)

func _go_step(idx: int) -> void:
	_step = clampi(idx, 0, STEPS.size() - 1)
	_render_step()

func _on_prev() -> void:
	if _step > 0:
		_step -= 1
		_render_step()

func _on_next() -> void:
	if _step < STEPS.size() - 1:
		_step += 1
		_render_step()
	else:
		close()

func _on_practice() -> void:
	close()
	start_practice_requested.emit()

func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()

func _render_step() -> void:
	var s: Dictionary = STEPS[_step]
	_badge.text = String(s.badge)
	_title.text = String(s.title)
	_summary.text = String(s.summary)
	_tip.text = String(s.tip)

	for ch in _bullets_box.get_children():
		_bullets_box.remove_child(ch)
		ch.queue_free()
	var bullets: Array = s.bullets
	for i in bullets.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var num := Label.new()
		num.text = "%d." % (i + 1)
		num.add_theme_color_override("font_color", Color(0.28, 0.94, 0.74, 1.0))
		num.add_theme_font_size_override("font_size", 20)
		num.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(num)

		var lbl := Label.new()
		lbl.text = String(bullets[i])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 1.0))
		lbl.add_theme_font_size_override("font_size", 19)
		row.add_child(lbl)
		_bullets_box.add_child(row)

	# Perbarui indikator titik langkah
	for i in _dot_buttons.size():
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_right = 6
		sb.corner_radius_bottom_left = 6
		if i == _step:
			sb.bg_color = Color(0.26, 0.94, 0.74, 1.0)
		elif i < _step:
			sb.bg_color = Color(0.20, 0.62, 0.85, 0.85)
		else:
			sb.bg_color = Color(0.16, 0.24, 0.34, 0.75)
		_dot_buttons[i].add_theme_stylebox_override("normal", sb)
		_dot_buttons[i].add_theme_stylebox_override("hover", sb)
		_dot_buttons[i].add_theme_stylebox_override("pressed", sb)

	_prev_btn.disabled = (_step == 0)
	var is_last := (_step == STEPS.size() - 1)
	_next_btn.text = "Selesai" if is_last else "Lanjut  >"
	_practice_btn.visible = is_last
