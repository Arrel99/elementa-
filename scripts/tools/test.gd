extends Node

## Uji aturan tanpa UI, jalankan lewat F6 (bab 3.4).
## Semua harapan di sini mengikuti Buku Peraturan Elementa: Kartu Reaksi.

var _ok := 0
var _fail := 0

func _ready() -> void:
	# --- Data (Lampiran A, B, C) ---
	_check(CardDB.cards.size() == 26, "CardDB memuat 26 kartu")
	var basic := 0
	var spell := 0
	for c in CardDB.cards.values():
		if c.type == CardData.Type.BASIC:
			basic += c.deck_copies
		elif c.type == CardData.Type.SPELL:
			spell += c.deck_copies
	_check(basic == 46 and spell == 14, "Komposisi deck 46 dasar + 14 spell (Lampiran A & C)")
	_check(basic + spell == CardDB.rules.deck_size, "Total deck = %d kartu" % CardDB.rules.deck_size)
	_check(CardDB.get_card("H2O").points == 6, "Poin H2O = 6")
	_check(CardDB.get_card("Fe2O3").points == 11, "Poin Fe2O3 = 11")
	_check(CardDB.get_card("Ne").points == 6, "Poin Ne = 6")
	_check(CardDB.get_card("Na").points == 3, "Poin Na = 3")
	_check(CardDB.find_recipe("H", "O") == "H2O", "find_recipe(H,O) = H2O")
	_check(CardDB.find_recipe("O", "H") == "H2O", "find_recipe simetris")
	_check(CardDB.find_recipe("Ne", "H") == "", "Neon tidak punya resep")

	# --- Setup (bagian 5) ---
	var g := GameState.new()
	g.setup(12345)
	_check(g.players[0].hand.size() == 5 and g.players[1].hand.size() == 5, "Tangan awal 5 : 5")
	_check(g.players[0].deck.size() == 55, "Deck tersisa 55 setelah tarik awal")
	_check(_composition(g, 0) == _composition(g, 1), "Isi deck kedua pemain identik (bagian 3)")
	_check(g.current == 0 or g.current == 1, "Pemain pertama ditentukan acak")
	_check(g.turn_no == 1, "Mulai dari giliran 1")

	# --- Turn pertama tanpa tarik; fase tarik = 2 kartu ---
	g.current = 0
	_end(g)
	_check(g.players[1].hand.size() == 7, "Fase tarik menarik 2 kartu (5 -> 7)")
	_check(g.players[0].hand.size() == 5, "Pemain pertama tidak menarik di giliran pertama")

	# --- Cooldown (bagian 7) ---
	var g2 := GameState.new()
	g2.setup(999)
	g2.current = 0
	var b := _first_basic_in_hand(g2, 0)
	_check(g2.place_base(0, b.uid) == "", "Pasang kartu dasar sukses")
	_check(g2.synthesize(0, b.uid, b.uid) != "", "Sintesis kartu sama ditolak")
	var c1 := _force_base(g2, 0, "H", true)
	var c2 := _force_base(g2, 0, "O", true)
	_check(g2.synthesize(0, c1.uid, c2.uid) != "", "Cooldown memblokir sintesis kartu baru")

	# --- Sintesis (bagian 7) ---
	var g3 := GameState.new()
	g3.setup(999)
	g3.current = 0
	var a := _force_base(g3, 0, "H")
	var bb := _force_base(g3, 0, "O")
	_check(g3.synthesize(0, a.uid, bb.uid) == "", "Sintesis H + O sukses")
	_check(g3.players[0].special.size() == 1, "Senyawa masuk zona spesial")
	_check(g3.players[0].points == 6, "Poin bertambah 6 (H2O)")
	_check(not g3.compound_pile.has("H2O"), "Senyawa diambil dari Tabel Senyawa")

	# senyawa habis
	var g4 := GameState.new()
	g4.setup(7)
	g4.current = 0
	g4.compound_pile.erase("H2O")
	var d1 := _force_base(g4, 0, "H")
	var d2 := _force_base(g4, 0, "O")
	_check(g4.synthesize(0, d1.uid, d2.uid) != "", "Senyawa habis ditolak")

	# Neon tak bisa disintesis
	var g5 := GameState.new()
	g5.setup(5)
	g5.current = 0
	var n1 := _force_base(g5, 0, "Ne")
	var n2 := _force_base(g5, 0, "H")
	_check(g5.synthesize(0, n1.uid, n2.uid) != "", "Neon tidak dapat disintesis")

	# --- Batas zona dasar (bagian 4) ---
	var g6 := GameState.new()
	g6.setup(11)
	g6.current = 0
	for i in 6:
		_force_base(g6, 0, "H")
	var extra := _new_basic(g6, "O")
	g6.players[0].hand.append(extra)
	_check(g6.place_base(0, extra.uid) != "", "Zona dasar penuh menolak kartu baru")

	# --- Batas tangan di akhir giliran (bagian 4 & 6) ---
	var g7 := GameState.new()
	g7.setup(3)
	g7.current = 0
	while g7.players[0].hand.size() < 9:
		g7.players[0].hand.append(_new_basic(g7, "H"))
	_check(g7.end_turn(0) != "", "Akhir giliran ditolak saat tangan > 8")
	var over: Dictionary = g7.players[0].hand[0]
	_check(g7.discard_from_hand(0, over.uid) == "", "Buang kelebihan kartu sukses")
	_check(g7.players[0].hand.size() == 8, "Tangan kembali ke batas 8")

	# --- Batas spell per giliran (bagian 8) ---
	var g8 := GameState.new()
	g8.setup(21)
	g8.current = 0
	_force_base(g8, 1, "H")
	var sp1 := _force_hand(g8, 0, "korosi")
	var sp2 := _force_hand(g8, 0, "korosi")
	_check(g8.play_spell(0, sp1.uid, {"target_uid": g8.players[1].base[0].uid}) == "", "Spell pertama dimainkan")
	_check(g8.play_spell(0, sp2.uid, {}) != "", "Spell kedua dalam giliran yang sama ditolak")

	# Katalis tidak memakai jatah spell
	var g9 := GameState.new()
	g9.setup(22)
	g9.current = 0
	_force_base(g9, 1, "H")
	var kat := _force_hand(g9, 0, "katalis")
	var kor := _force_hand(g9, 0, "korosi")
	_check(g9.play_spell(0, kat.uid, {}) == "", "Katalis dimainkan")
	_check(g9.synth_left == 2, "Katalis menambah 1 aksi sintesis")
	_check(g9.play_spell(0, kor.uid, {"target_uid": g9.players[1].base[0].uid}) == "", "Spell lain tetap bisa setelah Katalis")

	# --- Perisai Inert (bagian 8) ---
	var g10 := GameState.new()
	g10.setup(23)
	g10.current = 0
	_force_base(g10, 1, "H")
	g10.players[1].shield = true
	var kor2 := _force_hand(g10, 0, "korosi")
	_check(g10.play_spell(0, kor2.uid, {"target_uid": g10.players[1].base[0].uid}) == "", "Korosi terhadap perisai tetap dimainkan")
	_check(g10.players[1].base.size() == 1, "Perisai Inert menangkal Korosi")

	# --- Elektrolisis (bagian 8) ---
	var g11 := GameState.new()
	g11.setup(31)
	g11.current = 0
	var sp := _force_special(g11, 0, "H2O", ["H", "O"])
	g11.players[0].points = 6
	var hand_before: int = g11.players[0].hand.size()
	var el := _force_hand(g11, 0, "elektrolisis")
	_check(g11.play_spell(0, el.uid, {"target_uid": sp.uid}) == "", "Elektrolisis sukses")
	_check(g11.players[0].hand.size() == hand_before + 2, "2 unsur kembali ke tangan")
	_check(g11.compound_pile.has("H2O"), "Senyawa kembali ke Tabel Senyawa")
	_check(g11.players[0].points == 0, "Poin senyawa dikurangi")

	# --- Elektrolisis Paksa (bagian 8) ---
	var g12 := GameState.new()
	g12.setup(32)
	g12.current = 0
	var osp := _force_special(g12, 1, "H2O", ["H", "O"])
	var ohand: int = g12.players[1].hand.size()
	var ep := _force_hand(g12, 0, "elektrolisis_paksa")
	_check(g12.play_spell(0, ep.uid, {"target_uid": osp.uid}) == "", "Elektrolisis Paksa sukses")
	_check(g12.players[1].hand.size() == ohand + 2, "2 unsur kembali ke tangan lawan")
	_check(g12.compound_pile.has("H2O"), "Senyawa lawan kembali ke Tabel Senyawa")

	# --- Spektrometer (bagian 8) ---
	var g13 := GameState.new()
	g13.setup(41)
	g13.current = 0
	var deck_before: int = g13.players[0].deck.size()
	var hand_before2: int = g13.players[0].hand.size()
	var spec := _force_hand(g13, 0, "spektrometer")
	_check(g13.play_spell(0, spec.uid, {}) == "", "Spektrometer dimainkan")
	_check(not g13.pending.is_empty(), "Muncul efek Spektrometer yang menunggu")
	_check(g13.pending.cards.size() == 3, "Menampilkan 3 kartu teratas")
	var take: int = g13.pending.cards[0].uid
	_check(g13.resolve_spektrometer(0, take) == "", "Spektrometer diselesaikan")
	_check(g13.players[0].hand.size() == hand_before2 + 1, "1 kartu diambil ke tangan")
	_check(g13.players[0].deck.size() == deck_before - 1, "Sisa 2 kartu kembali ke deck")
	_check(g13.pending.is_empty(), "Efek Spektrometer selesai")

	# --- Bilas (bagian 8) ---
	var g14 := GameState.new()
	g14.setup(51)
	g14.current = 0
	_force_base(g14, 0, "H")
	var bil := _force_hand(g14, 0, "bilas")
	var hand_before3: int = g14.players[0].hand.size()
	var deck_before2: int = g14.players[0].deck.size()
	_check(g14.play_spell(0, bil.uid, {"target_uid": g14.players[0].base[0].uid}) == "", "Bilas dimainkan")
	_check(g14.players[0].base.is_empty(), "Bilas membuang kartu zona dasar")
	# buang bilas (-1) lalu tarik 1 (+1) => tangan tetap
	_check(g14.players[0].hand.size() == hand_before3, "Bilas menambah 1 kartu setelah dibuang")
	_check(g14.players[0].deck.size() == deck_before2 - 1, "Bilas menarik 1 kartu dari deck")

	# --- Menyerah (bagian 9.1) ---
	var g15 := GameState.new()
	g15.setup(1)
	g15.surrender(0)
	_check(g15.winner == 1 and g15.win_reason == "surrender", "Menyerah menentukan pemenang")

	# --- Deck habis (bagian 9.2) ---
	var g16 := GameState.new()
	g16.setup(61)
	g16.current = 0
	while g16.players[0].deck.size() > 1:
		g16.players[0].deck.pop_back()
	g16._draw_phase(0)
	_check(g16.win_reason == "deck_out" and g16.winner != -2, "Deck kurang dari 2 mengakhiri permainan")

	# --- Hitungan mundur zona spesial (bagian 9.3) ---
	var g17 := GameState.new()
	g17.setup(71)
	g17.current = 0
	for i in 8:
		_force_special(g17, 0, "H2O", ["H", "O"])
	g17._check_special_trigger(0)
	_check(g17.countdown == 3, "Menyentuh 8 slot memicu hitungan mundur 3")
	_end(g17)
	_end(g17)
	_check(g17.winner == -2, "Permainan belum selesai di tengah hitungan mundur")
	_end(g17)
	_check(g17.win_reason == "special_full" and g17.winner != -2, "Hitungan mundur selesai mengakhiri permainan")

	# --- Seri ditentukan oleh jumlah kartu spesial (bagian 9) ---
	var g18 := GameState.new()
	g18.setup(81)
	g18.players[0].points = 5
	g18.players[1].points = 5
	_force_special(g18, 0, "H2O", ["H", "O"])
	_force_special(g18, 0, "CO2", ["C", "O"])
	_force_special(g18, 1, "H2O", ["H", "O"])
	g18._finish_by_points()
	_check(g18.winner == 0, "Poin seri -> kartu spesial terbanyak menang")

	# --- Bot acak menamatkan game ---
	var g19 := GameState.new()
	g19.setup(42)
	var guard := 0
	while g19.winner == -2 and guard < 500:
		_bot_turn(g19)
		guard += 1
	_check(guard < 500, "Bot acak menamatkan game")
	_check(g19.winner != -2, "Ada pemenang atau seri")

	print("== Hasil: %d lulus, %d gagal ==" % [_ok, _fail])
	get_tree().quit()

# --- Bantuan ----------------------------------------------------------------

func _check(cond: bool, name: String) -> void:
	if cond:
		_ok += 1
		print("  OK    ", name)
	else:
		_fail += 1
		print("  GAGAL ", name)

func _end(g: GameState) -> void:
	g.auto_discard_excess(g.current)
	g.end_turn(g.current)

func _new_basic(g: GameState, id: String) -> Dictionary:
	return g._new_card(id)

## Multiset id kartu (deck + tangan) untuk membandingkan komposisi kedua pemain.
func _composition(g: GameState, p: int) -> Array:
	var ids: Array = []
	for c in g.players[p].deck:
		ids.append(String(c.id))
	for c in g.players[p].hand:
		ids.append(String(c.id))
	ids.sort()
	return ids

func _force_base(g: GameState, p: int, id: String, cooldown := false) -> Dictionary:
	var c: Dictionary = g._new_card(id)
	c.placed_turn = g.turn_no if cooldown else g.turn_no - 5
	g.players[p].base.append(c)
	return c

func _force_special(g: GameState, p: int, id: String, parts: Array) -> Dictionary:
	var c: Dictionary = g._new_card(id)
	c["parts"] = parts
	g.players[p].special.append(c)
	return c

func _force_hand(g: GameState, p: int, id: String) -> Dictionary:
	var c: Dictionary = g._new_card(id)
	g.players[p].hand.append(c)
	return c

func _first_basic_in_hand(g: GameState, p: int) -> Dictionary:
	for c in g.players[p].hand:
		var d = CardDB.get_card(c.id)
		if d != null and d.type == CardData.Type.BASIC:
			return c
	return {}

func _bot_turn(g: GameState) -> void:
	var p := g.current
	var pl = g.players[p]
	if not g.pending.is_empty():
		var cs: Array = g.pending.cards
		g.resolve_spektrometer(p, int(cs[0].uid) if not cs.is_empty() else -1)
	for c in pl.hand.duplicate():
		var d = CardDB.get_card(c.id)
		if d != null and d.type == CardData.Type.BASIC:
			g.place_base(p, c.uid)
	for a in pl.base.duplicate():
		for b in pl.base.duplicate():
			if a.uid < b.uid and g.synthesize(p, a.uid, b.uid) == "":
				break
	_end(g)
