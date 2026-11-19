extends CanvasLayer

## Pemandu Tutorial Adaptif di dalam arena permainan.
## Membaca kondisi papan & giliran secara real-time, lalu menampilkan langkah
## paling relevan (termasuk resep senyawa yang siap disintesis sekarang).

signal open_full_guide_requested

@onready var _panel: PanelContainer = $Root/Panel
@onready var _toggle_btn: Button = $Root/CollapsedBtn
@onready var _badge: Label = $Root/Panel/V/Top/Badge
@onready var _body: Label = $Root/Panel/V/Body
@onready var _step1: Label = $Root/Panel/V/Steps/S1
@onready var _step2: Label = $Root/Panel/V/Steps/S2
@onready var _step3: Label = $Root/Panel/V/Steps/S3

var _expanded := true

func _ready() -> void:
	_expanded = bool(Settings.get_value("ui", "show_coach", true))
	$Root/Panel/V/Top/HideBtn.pressed.connect(_set_expanded.bind(false))
	$Root/Panel/V/Top/GuideBtn.pressed.connect(func(): open_full_guide_requested.emit())
	_toggle_btn.pressed.connect(_set_expanded.bind(true))
	_apply_visibility()

func _set_expanded(on: bool) -> void:
	_expanded = on
	Settings.set_value("ui", "show_coach", on)
	_apply_visibility()

func _apply_visibility() -> void:
	_panel.visible = _expanded
	_toggle_btn.visible = not _expanded

## Dipanggil setiap kali papan dirender atau mode klik berubah (IDLE / PICK_SYNTH / PICK_TARGET).
## mode_id: 0 = IDLE, 1 = PICK_SYNTH, 2 = PICK_TARGET
func update_state(v: Dictionary, mode_id: int, synth_first: int = -1, pending_zone: String = "") -> void:
	if v.is_empty():
		return

	if int(v.winner) != -2:
		_set_msg("PERTANDINGAN SELESAI",
			"Pertandingan telah berakhir. Lihat ringkasan skor di layar atau kembali ke Menu Utama.",
			Color(0.32, 0.94, 0.74), 0)
		return

	if not v.my_turn:
		_set_msg("GILIRAN LAWAN",
			"Tunggu lawan menyelesaikan gilirannya. Kamu bisa arahkan kursor (hover) ke kartu di papan untuk membaca efeknya.",
			Color(1.0, 0.48, 0.54), 0)
		return

	# 1) Efek Spektrometer sedang menunggu pilihan
	if not v.pending.is_empty():
		_set_msg("EFEK SPEKTROMETER",
			"Pilih 1 dari 3 kartu teratas deck pada jendela Spektrometer untuk diambil ke tanganmu.",
			Color(0.35, 0.92, 1.0), 3)
		return

	# 2) Sedang memilih kartu kedua untuk sintesis
	if mode_id == 1:
		var first_sym := _symbol_of_base_uid(v.me.base, synth_first)
		var hint := "Klik unsur pasangan yang cocok di Zona Dasarmu untuk membentuk senyawa! (Tekan Esc untuk batal)"
		if first_sym != "":
			hint = "Unsur pertama terpilih: %s. Klik unsur pasangan yang cocok di Zona Dasarmu untuk sintesis! (Esc = batal)" % first_sym
		_set_msg("SINTESIS (LANGKAH 2/2)", hint, Color(0.28, 0.96, 0.72), 2)
		return

	# 3) Sedang memilih target spell
	if mode_id == 2:
		var zone_name := _zone_label(pending_zone)
		_set_msg("PILIH TARGET SPELL",
			"Klik 1 kartu di %s (yang sedang menyala berkedip) untuk mengaktifkan efek spell! (Esc = batal)" % zone_name,
			Color(1.0, 0.84, 0.36), 3)
		return

	# Analisis kondisi papan saat Mode.IDLE di giliran sendiri
	var playable: Dictionary = v.get("playable", {})
	var play_base: Array = playable.get("base", [])
	var play_hand: Array = playable.get("hand", [])
	var has_basic_playable := false
	var has_spell_playable := false
	for c in v.me.hand:
		if not play_hand.has(int(c.get("uid", -1))):
			continue
		var d: CardData = CardDB.get_card(String(c.get("id", "")))
		if d == null:
			continue
		if d.type == CardData.Type.BASIC:
			has_basic_playable = true
		elif d.type == CardData.Type.SPELL:
			has_spell_playable = true

	var cd_prefix := ""
	if int(v.countdown) > 0:
		cd_prefix = "[Hitung Mundur: %d giliran!] " % int(v.countdown)

	# 4) Ada pasangan senyawa siap disintesis sekarang!
	if not play_base.is_empty() and int(v.synth_left) > 0:
		var ready_recipe := _find_ready_recipe_text(v)
		var text := "%sAda unsur di Zona Dasarmu yang siap disintesis (%s). Klik salah satu unsur yang menyala hijau, lalu klik pasangannya!" % [
			cd_prefix, ready_recipe if ready_recipe != "" else "lihat kartu hijau di Tabel Senyawa"]
		_set_msg("SIAP SINTESIS SENYAWA!", text, Color(0.28, 0.96, 0.72), 2)
		return

	# 5) Bisa pasang kartu unsur dari tangan ke Zona Dasar
	if has_basic_playable:
		var text := "%sKlik kartu unsur yang menyala hijau di tanganmu untuk memasangnya ke Zona Dasar. Unsur baru butuh 1 giliran cooldown sebelum bisa disintesis." % cd_prefix
		_set_msg("LANGKAH 1: PASANG UNSUR", text, Color(0.28, 0.82, 1.0), 1)
		return

	# 6) Bisa mainkan spell dari tangan
	if has_spell_playable:
		var text := "%sKamu bisa klik kartu Spell di tangan untuk bantuan/gangguan, atau klik END TURN di sisi kanan untuk mengakhiri giliran." % cd_prefix
		_set_msg("LANGKAH 3: SPELL / END TURN", text, Color(0.95, 0.82, 0.42), 3)
		return

	# 7) Tidak ada aksi lagi -> akhiri giliran
	_set_msg("AKHIRI GILIRAN",
		"%sTidak ada aksi tersisa (unsur yang redup masih cooldown). Klik tombol END TURN di kanan untuk lanjut dan menarik 2 kartu di giliran berikutnya." % cd_prefix,
		Color(0.55, 0.84, 1.0), 3)

func _set_msg(badge: String, body: String, accent: Color, active_step: int) -> void:
	_badge.text = badge
	_badge.add_theme_color_override("font_color", accent)
	_body.text = body

	var labels := [_step1, _step2, _step3]
	for i in labels.size():
		var idx := i + 1
		var lbl: Label = labels[i]
		if idx == active_step:
			lbl.add_theme_color_override("font_color", Color(0.32, 0.96, 0.78, 1.0))
		else:
			lbl.add_theme_color_override("font_color", Color(0.52, 0.64, 0.76, 0.85))

func _symbol_of_base_uid(base_cards: Array, uid: int) -> String:
	for c in base_cards:
		if int(c.get("uid", -1)) == uid:
			var d: CardData = CardDB.get_card(String(c.get("id", "")))
			return d.symbol if d != null else String(c.get("id", ""))
	return ""

func _find_ready_recipe_text(v: Dictionary) -> String:
	var ready_ids: Array[String] = []
	for c in v.me.base:
		if int(c.get("placed_turn", -1)) != int(v.turn_no):
			ready_ids.append(String(c.get("id", "")))
	for i in ready_ids.size():
		for j in range(i + 1, ready_ids.size()):
			var res_id: String = CardDB.find_recipe(ready_ids[i], ready_ids[j])
			if res_id != "" and v.compound_pile.has(res_id):
				var a: CardData = CardDB.get_card(ready_ids[i])
				var b: CardData = CardDB.get_card(ready_ids[j])
				var res: CardData = CardDB.get_card(res_id)
				if a != null and b != null and res != null:
					return "%s + %s -> %s" % [a.symbol, b.symbol, res.display_name]
	return ""

func _zone_label(z: String) -> String:
	match z:
		"my_base": return "Zona Dasar Kamu"
		"opp_base": return "Zona Dasar Lawan"
		"my_special": return "Zona Senyawa Kamu"
		"opp_special": return "Zona Senyawa Lawan"
		_: return "zona yang disorot"
