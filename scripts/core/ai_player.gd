extends RefCounted

## AI taktis untuk mode VS. AI di Elementa dengan 4 tingkat kesulitan:
## - "easy"    : Santai, sering memasang unsur acak, jarang memakai spell ofensif.
## - "normal"  : Seimbang, menyintesis resep terbaik & memakai spell seperlunya.
## - "hard"    : Agresif, memanfaatkan Katalis, Korosi, Elektrolisis Paksa & Perisai.
## - "extreme" : Optimal tanpa ampun, membaca ancaman lawan & memaksimalkan total skor tumpukan.

static func choose_action(state: GameState, p: int, difficulty := "normal") -> Dictionary:
	if state == null or state.winner != -2:
		return {}

	var diff := difficulty.to_lower()

	# 1) Fase lempar koin awal
	if not state.coin_phase.is_empty():
		var stage := String(state.coin_phase.get("stage", ""))
		if stage == "pick_call" and int(state.coin_phase.get("caller", -1)) == p:
			return {"type": "coin_call", "side": "heads" if (randi() % 2 == 0) else "tails"}
		if stage == "pick_order" and int(state.coin_phase.get("winner", -1)) == p:
			var prefer_first := 0.50 if diff == "easy" else (0.75 if diff == "normal" else 0.90)
			return {"type": "coin_order", "first": randf() < prefer_first}
		return {}

	# 2) Efek pending yang harus diselesaikan AI terlebih dahulu
	if not state.pending.is_empty():
		if int(state.pending.get("to", -1)) != p:
			return {}
		var ptype := String(state.pending.get("type", ""))
		if ptype == "spektrometer":
			var take_uid := _pick_spektrometer_card(state, p, state.pending.get("cards", []), diff)
			return {"type": "spektro", "take": take_uid}
		if ptype == "spell_target":
			var tgt := _pick_spell_target(state, p, String(state.pending.get("zone", "")), diff)
			return {"type": "spell_target", "target_uid": tgt}
		return {}

	if state.current != p:
		return {}

	var pl: Dictionary = state.players[p]
	var opp: Dictionary = state.players[1 - p]

	# 3) Extreme: prioritaskan gangguan kritis bila lawan hampir menang (>= 6 senyawa)
	if diff == "extreme" and state.spell_left > 0 and not bool(opp.shield):
		if opp.special.size() >= 6:
			var ep_uid := _find_hand_spell(pl.hand, "elektrolisis_paksa")
			if ep_uid != -1:
				var tgt := _pick_spell_target(state, p, "opp_special", diff)
				if tgt != -1:
					return {"type": "spell", "uid": ep_uid, "args": {"target_uid": tgt}}

	# 4) Sintesis senyawa
	if state.synth_left > 0 and pl.special.size() < CardDB.rules.special_max:
		var best_pair := _best_synth_pair(state, p, diff)
		if not best_pair.is_empty():
			if diff != "easy" or randf() < 0.72:
				return {"type": "synth", "a": int(best_pair.a), "b": int(best_pair.b)}

	# 5) Katalis (tidak dipakai di Easy; dipakai agresif di Normal/Hard/Extreme)
	if diff != "easy" and state.synth_left == 0 and pl.special.size() < CardDB.rules.special_max:
		var extra_pair := _best_synth_pair(state, p, diff)
		if not extra_pair.is_empty():
			var kat_uid := _find_hand_spell(pl.hand, "katalis")
			if kat_uid != -1:
				return {"type": "spell", "uid": kat_uid, "args": {}}

	# 6) Pasang kartu dasar ke Zona Dasar
	if pl.base.size() < CardDB.rules.base_max:
		# Di Easy, batasi maks 1 kartu dasar baru per giliran agar lebih santai
		var placed_this_turn := 0
		for bc in pl.base:
			if int(bc.placed_turn) == state.turn_no:
				placed_this_turn += 1
		var max_per_turn := 1 if diff == "easy" else (2 if diff == "normal" else 6)
		if placed_this_turn < max_per_turn:
			var best_basic := _best_basic_to_place(state, p, diff)
			if best_basic != -1:
				var slot := _first_free_slot(pl.base, CardDB.rules.base_max)
				return {"type": "place", "uid": best_basic, "slot": slot}

	# 7) Mainkan Spell taktis
	if state.spell_left > 0:
		var spell_act := _best_spell_action(state, p, pl, opp, diff)
		if not spell_act.is_empty():
			return spell_act

	# 8) Akhiri giliran
	return {"type": "end"}

# --- Evaluasi Sintesis -------------------------------------------------------

static func _best_synth_pair(state: GameState, p: int, diff: String) -> Dictionary:
	var pl: Dictionary = state.players[p]
	var candidates: Array[Dictionary] = []
	for i in pl.base.size():
		var a: Dictionary = pl.base[i]
		if int(a.placed_turn) == state.turn_no:
			continue
		for j in range(i + 1, pl.base.size()):
			var b: Dictionary = pl.base[j]
			if int(b.placed_turn) == state.turn_no or String(a.id) == String(b.id):
				continue
			var res := CardDB.find_recipe(String(a.id), String(b.id))
			if res != "" and state.compound_pile.has(res):
				var d := CardDB.get_card(res)
				var pts := d.points if d != null else 0
				if diff == "extreme":
					# Extreme juga menghitung total skor tumpukan (senyawa + 2 unsur) + kelangkaan stok (sisa 1)
					var da := CardDB.get_card(String(a.id))
					var db := CardDB.get_card(String(b.id))
					pts += (da.points if da != null else 0) + (db.points if db != null else 0)
					if state.compound_pile.count(res) == 1:
						pts += 3
				candidates.append({"a": int(a.uid), "b": int(b.uid), "pts": pts})
	if candidates.is_empty():
		return {}
	if diff == "easy":
		return candidates[randi() % candidates.size()]
	candidates.sort_custom(func(x, y): return int(x.pts) > int(y.pts))
	return candidates[0]

# --- Evaluasi Kartu Dasar ----------------------------------------------------

static func _best_basic_to_place(state: GameState, p: int, diff: String) -> int:
	var pl: Dictionary = state.players[p]
	var basics: Array[Dictionary] = []
	for c in pl.hand:
		var d := CardDB.get_card(String(c.id))
		if d != null and d.type == CardData.Type.BASIC:
			basics.append(c)
	if basics.is_empty():
		return -1
	if diff == "easy" and randf() < 0.55:
		return int(basics[randi() % basics.size()].uid)

	var base_ids := {}
	for bc in pl.base:
		base_ids[String(bc.id)] = int(base_ids.get(String(bc.id), 0)) + 1

	var best_uid := -1
	var best_score := -9999
	for i in pl.hand.size():
		var c: Dictionary = pl.hand[i]
		var d := CardDB.get_card(String(c.id))
		if d == null or d.type != CardData.Type.BASIC:
			continue
		var score := d.points * (3 if diff == "extreme" else 2)

		var best_base_recipe := 0
		for bc in pl.base:
			if String(bc.id) == String(c.id):
				continue
			var res := CardDB.find_recipe(String(c.id), String(bc.id))
			if res != "" and state.compound_pile.has(res):
				var rd := CardDB.get_card(res)
				if rd != null:
					best_base_recipe = maxi(best_base_recipe, rd.points)
		if best_base_recipe > 0:
			var mult := 3 if diff == "extreme" else 2
			score += 24 + best_base_recipe * mult

		for j in pl.hand.size():
			if i == j:
				continue
			var oc: Dictionary = pl.hand[j]
			if String(oc.id) == String(c.id):
				continue
			var res2 := CardDB.find_recipe(String(c.id), String(oc.id))
			if res2 != "" and state.compound_pile.has(res2):
				score += 14 if diff in ["hard", "extreme"] else 10
				break

		if base_ids.has(String(c.id)):
			score -= 18 if pl.base.size() >= 4 else 8

		if score > best_score:
			best_score = score
			best_uid = int(c.uid)
	return best_uid

static func _first_free_slot(base: Array, max_slots: int) -> int:
	var used := {}
	for i in base.size():
		used[int(base[i].get("slot", i))] = true
	for s in max_slots:
		if not used.has(s):
			return s
	return 0

# --- Evaluasi Spell ----------------------------------------------------------

static func _best_spell_action(state: GameState, p: int, pl: Dictionary, opp: Dictionary, diff: String) -> Dictionary:
	if diff == "easy":
		if randf() > 0.30:
			return {}
		if not bool(pl.shield) and pl.base.size() >= 2:
			var sh_e := _find_hand_spell(pl.hand, "perisai_inert")
			if sh_e != -1:
				return {"type": "spell", "uid": sh_e, "args": {}}
		if not bool(opp.shield) and not opp.base.is_empty():
			var kor_e := _find_hand_spell(pl.hand, "korosi")
			if kor_e != -1:
				var tgt := _pick_spell_target(state, p, "opp_base", diff)
				if tgt != -1:
					return {"type": "spell", "uid": kor_e, "args": {"target_uid": tgt}}
		return {}

	# 1) Elektrolisis Paksa
	if not bool(opp.shield) and not opp.special.is_empty():
		var ep_uid := _find_hand_spell(pl.hand, "elektrolisis_paksa")
		if ep_uid != -1:
			var tgt := _pick_spell_target(state, p, "opp_special", diff)
			if tgt != -1:
				return {"type": "spell", "uid": ep_uid, "args": {"target_uid": tgt}}

	# 2) Korosi
	if not bool(opp.shield) and not opp.base.is_empty():
		var kor_uid := _find_hand_spell(pl.hand, "korosi")
		if kor_uid != -1:
			var tgt := _pick_spell_target(state, p, "opp_base", diff)
			if tgt != -1:
				return {"type": "spell", "uid": kor_uid, "args": {"target_uid": tgt}}

	# 3) Spektrometer
	if pl.deck.size() >= 3:
		var sp_uid := _find_hand_spell(pl.hand, "spektrometer")
		if sp_uid != -1:
			return {"type": "spell", "uid": sp_uid, "args": {}}

	# 4) Perisai Inert
	var min_base_for_shield := 1 if diff == "extreme" else 2
	if not bool(pl.shield) and (not pl.special.is_empty() or pl.base.size() >= min_base_for_shield):
		var sh_uid := _find_hand_spell(pl.hand, "perisai_inert")
		if sh_uid != -1:
			return {"type": "spell", "uid": sh_uid, "args": {}}

	# 5) Bilas (Extreme lebih agresif membuang kartu mati untuk menggali deck)
	var min_base_for_bilas := 4 if diff == "extreme" else 5
	if pl.base.size() >= min_base_for_bilas and pl.deck.size() >= 4:
		var bil_uid := _find_hand_spell(pl.hand, "bilas")
		if bil_uid != -1:
			var tgt := _pick_spell_target(state, p, "my_base", diff)
			if tgt != -1:
				return {"type": "spell", "uid": bil_uid, "args": {"target_uid": tgt}}

	return {}

static func _find_hand_spell(hand: Array, effect_name: String) -> int:
	for c in hand:
		var d := CardDB.get_card(String(c.id))
		if d != null and d.type == CardData.Type.SPELL and String(d.spell_effect) == effect_name:
			return int(c.uid)
	return -1

# --- Pilihan Pending (Spektrometer & Target Spell) ---------------------------

static func _pick_spektrometer_card(state: GameState, p: int, cards: Array, diff: String) -> int:
	if cards.is_empty():
		return -1
	if diff == "easy":
		return int(cards[randi() % cards.size()].uid)
	var pl: Dictionary = state.players[p]
	var best_uid := int(cards[0].uid)
	var best_score := -9999
	for c in cards:
		var d := CardDB.get_card(String(c.id))
		var score := 0
		if d != null:
			if d.type == CardData.Type.BASIC:
				score = d.points * 2
				for bc in pl.base:
					if String(bc.id) != String(c.id):
						var res := CardDB.find_recipe(String(c.id), String(bc.id))
						if res != "" and state.compound_pile.has(res):
							var rd := CardDB.get_card(res)
							score += 22 + (rd.points if (diff == "extreme" and rd != null) else 0)
							break
			elif d.type == CardData.Type.SPELL:
				score = 18 if (diff == "extreme" and d.spell_effect in ["elektrolisis_paksa", "katalis", "korosi"]) else (
					14 if d.spell_effect in ["elektrolisis_paksa", "korosi", "katalis"] else 10)
		if score > best_score:
			best_score = score
			best_uid = int(c.uid)
	return best_uid

static func _pick_spell_target(state: GameState, p: int, zone: String, diff: String) -> int:
	var pl: Dictionary = state.players[p]
	var opp: Dictionary = state.players[1 - p]
	match zone:
		"opp_base":
			if diff == "easy" and not opp.base.is_empty():
				return int(opp.base[randi() % opp.base.size()].uid)
			var best_uid := -1
			var best_s := -999
			for c in opp.base:
				var d := CardDB.get_card(String(c.id))
				var s := (d.points * 2) if d != null else 0
				for oc in opp.base:
					if int(oc.uid) != int(c.uid):
						var res := CardDB.find_recipe(String(c.id), String(oc.id))
						if res != "" and state.compound_pile.has(res):
							var rd := CardDB.get_card(res)
							s += (14 + (rd.points if rd != null else 0)) if diff == "extreme" else 10
							break
				if s > best_s:
					best_s = s
					best_uid = int(c.uid)
			return best_uid
		"opp_special":
			var best_uid := -1
			var best_s := -999
			for c in opp.special:
				var s := state._special_stack_points(c) if diff in ["hard", "extreme"] else (
					CardDB.get_card(String(c.id)).points if CardDB.get_card(String(c.id)) != null else 0)
				if s > best_s:
					best_s = s
					best_uid = int(c.uid)
			return best_uid
		"my_base":
			var best_uid := -1
			var worst_s := 9999
			for c in pl.base:
				var d := CardDB.get_card(String(c.id))
				var s := (d.points * 2) if d != null else 0
				for oc in pl.base:
					if int(oc.uid) != int(c.uid) and CardDB.find_recipe(String(c.id), String(oc.id)) != "":
						s += 16
						break
				if s < worst_s:
					worst_s = s
					best_uid = int(c.uid)
			return best_uid
		"my_special":
			return int(pl.special[0].uid) if not pl.special.is_empty() else -1
	return -1
