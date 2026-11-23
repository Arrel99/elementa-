extends RefCounted

## AI taktis kompetitif untuk mode VS. AI di Elementa (100% adil tanpa deck rigged).
## Ke-4 level selalu aktif membangun senyawa dan menantang:
## - "easy"    : Aktif & menantang untuk pemula — selalu menyintesis, pasang hingga 2 kartu/giliran, pakai spell dasar.
## - "normal"  : Solid & seimbang — pakai Spektrometer di awal giliran, Katalis ganda, dan gangguan tepat sasaran.
## - "hard"    : Agresif & disiplin — optimasi sintesis ganda, aktif mematahkan kombo lawan, disiplin slot.
## - "extreme" : Tanpa ampun — denial stok senyawa lawan, perencanaan pasangan ganda penuh, dan tekanan spell maksimal.

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
			var prefer_first := 0.55 if diff == "easy" else (0.70 if diff == "normal" else 0.85)
			return {"type": "coin_order", "first": randf() < prefer_first}
		return {}

	# 2) Selesaikan efek pending terlebih dahulu (Spektrometer / target Spell)
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
	var has_katalis := _find_hand_spell(pl.hand, "katalis") != -1

	# 3) URUTAN 1 — SELALU sintesis jika ada pasangan sah (mempercepat 8 senyawa + membuka 2 slot dasar!)
	if state.synth_left > 0 and pl.special.size() < CardDB.rules.special_max:
		var synth_plan := _choose_best_synthesis(state, p, diff, has_katalis)
		if not synth_plan.is_empty():
			return {"type": "synth", "a": int(synth_plan.a), "b": int(synth_plan.b)}

	# 4) URUTAN 2 — Katalis: jika jatah sintesis habis tapi masih ada pasangan siap sintesis
	if state.synth_left == 0 and pl.special.size() < CardDB.rules.special_max:
		var extra_plan := _choose_best_synthesis(state, p, diff, false)
		if not extra_plan.is_empty():
			var kat_uid := _find_hand_spell(pl.hand, "katalis")
			if kat_uid != -1 and (diff != "easy" or randf() < 0.75):
				return {"type": "spell", "uid": kat_uid, "args": {}}

	# 5) URUTAN 3 — Gangguan darurat (Hard/Extreme): jika lawan punya >= 5 senyawa, segera pecah!
	if diff in ["hard", "extreme"] and state.spell_left > 0 and not bool(opp.shield):
		if opp.special.size() >= 5:
			var ep_urgent := _find_hand_spell(pl.hand, "elektrolisis_paksa")
			if ep_urgent != -1:
				var tgt := _pick_spell_target(state, p, "opp_special", diff)
				if tgt != -1:
					return {"type": "spell", "uid": ep_urgent, "args": {"target_uid": tgt}}

	# 6) URUTAN 4 — Spektrometer SEBELUM pasang kartu agar kartu hasil intip bisa langsung dipasang!
	if state.spell_left > 0 and pl.deck.size() >= 3:
		var sp_uid := _find_hand_spell(pl.hand, "spektrometer")
		if sp_uid != -1 and _should_cast_spektrometer_now(state, pl, opp, diff):
			return {"type": "spell", "uid": sp_uid, "args": {}}

	# 7) URUTAN 5 — Bilas SEBELUM pasang kartu bila papan penuh kartu mati (bebaskan slot + tarik 1 kartu!)
	if state.spell_left > 0 and pl.deck.size() >= 4:
		var bil_uid := _find_hand_spell(pl.hand, "bilas")
		if bil_uid != -1 and _should_cast_bilas(state, pl, diff):
			var tgt := _pick_spell_target(state, p, "my_base", diff)
			if tgt != -1:
				return {"type": "spell", "uid": bil_uid, "args": {"target_uid": tgt}}

	# 8) URUTAN 6 — Aktif memasang kartu dasar pembentuk resep & poin ke Zona Dasar
	if pl.base.size() < CardDB.rules.base_max:
		var placed_this_turn := 0
		for bc in pl.base:
			if int(bc.placed_turn) == state.turn_no:
				placed_this_turn += 1
		var max_per_turn := 2 if diff == "easy" else (3 if diff == "normal" else 6)
		if placed_this_turn < max_per_turn:
			var best_basic := _best_basic_to_place(state, p, diff)
			if best_basic != -1:
				var slot := _first_free_slot(pl.base, CardDB.rules.base_max)
				return {"type": "place", "uid": best_basic, "slot": slot}

	# 9) URUTAN 7 — Mainkan Spell taktis terbaik (Elektrolisis Paksa, Korosi, Perisai Inert, Spektrometer)
	if state.spell_left > 0:
		var spell_act := _best_spell_action(state, p, pl, opp, diff)
		if not spell_act.is_empty():
			return spell_act

	# 10) Akhiri giliran
	return {"type": "end"}

# =============================================================================
# SINTESIS OPTIMAL (Disjoint Multi-Synth + Denial Stok Senyawa Lawan)
# =============================================================================

static func _all_valid_synths(state: GameState, p: int) -> Array[Dictionary]:
	var pl: Dictionary = state.players[p]
	var out: Array[Dictionary] = []
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
				var rd := CardDB.get_card(res)
				var da := CardDB.get_card(String(a.id))
				var db := CardDB.get_card(String(b.id))
				var comp_pts := rd.points if rd != null else 0
				var stack_pts := comp_pts + (da.points if da != null else 0) + (db.points if db != null else 0)
				out.append({
					"a": int(a.uid), "b": int(b.uid),
					"a_id": String(a.id), "b_id": String(b.id),
					"res": res, "comp_pts": comp_pts, "stack_pts": stack_pts,
				})
	return out

static func _choose_best_synthesis(state: GameState, p: int, diff: String, has_katalis: bool) -> Dictionary:
	var cands := _all_valid_synths(state, p)
	if cands.is_empty():
		return {}

	var pl: Dictionary = state.players[p]
	var opp: Dictionary = state.players[1 - p]

	# Easy: pilih 1 dari 2 kandidat teratas agar tetap kuat namun sedikit bervariasi
	if diff == "easy":
		cands.sort_custom(func(x, y): return int(x.stack_pts) > int(y.stack_pts))
		if cands.size() >= 2 and randf() < 0.30:
			return cands[1]
		return cands[0]

	# Jika sintesis ini langsung memenangkan pertandingan (senyawa ke-8), langsung ambil!
	if pl.special.size() + 1 >= CardDB.rules.special_win_threshold:
		cands.sort_custom(func(x, y): return int(x.stack_pts) > int(y.stack_pts))
		return cands[0]

	# Hard/Extreme: optimasi 2 sintesis sekaligus (Katalis / synth_left >= 2) tanpa saling memakan unsur
	if diff in ["hard", "extreme"] and (state.synth_left >= 2 or has_katalis) and pl.special.size() + 2 <= CardDB.rules.special_max:
		var best_combo_val := -1
		var best_first := {}
		for i in cands.size():
			var c1: Dictionary = cands[i]
			for j in range(i + 1, cands.size()):
				var c2: Dictionary = cands[j]
				if int(c1.a) == int(c2.a) or int(c1.a) == int(c2.b) or int(c1.b) == int(c2.a) or int(c1.b) == int(c2.b):
					continue
				if String(c1.res) == String(c2.res) and state.compound_pile.count(String(c1.res)) < 2:
					continue
				var val := int(c1.stack_pts) + int(c2.stack_pts)
				if val > best_combo_val:
					best_combo_val = val
					best_first = c1 if int(c1.stack_pts) >= int(c2.stack_pts) else c2
		if not best_first.is_empty():
			return best_first

	var best := {}
	var best_val := -9999
	for c in cands:
		var val := int(c.stack_pts) * 3
		if state.compound_pile.count(String(c.res)) == 1:
			val += 8 if diff == "extreme" else 4
			# Extreme denial: bonus besar bila mengambil salinan terakhir senyawa yang bahannya sedang dikumpulkan lawan!
			if diff == "extreme" and _opp_wants_compound(opp, String(c.res)):
				val += 14
		if val > best_val:
			best_val = val
			best = c
	return best

static func _opp_wants_compound(opp: Dictionary, comp_id: String) -> bool:
	var cd := CardDB.get_card(comp_id)
	if cd == null or cd.recipe.size() != 2:
		return false
	var has0 := false
	var has1 := false
	for bc in opp.base:
		if String(bc.id) == String(cd.recipe[0]):
			has0 = true
		elif String(bc.id) == String(cd.recipe[1]):
			has1 = true
	return has0 and has1

# =============================================================================
# PENEMPATAN KARTU DASAR (Aktif Membangun Resep, Jaga Hanya Slot ke-6 dari Kartu Mati)
# =============================================================================

static func _best_basic_to_place(state: GameState, p: int, diff: String) -> int:
	var pl: Dictionary = state.players[p]
	var basics: Array[Dictionary] = []
	for c in pl.hand:
		var d := CardDB.get_card(String(c.id))
		if d != null and d.type == CardData.Type.BASIC:
			basics.append(c)
	if basics.is_empty():
		return -1

	var base_counts := {}
	for bc in pl.base:
		var bid := String(bc.id)
		base_counts[bid] = int(base_counts.get(bid, 0)) + 1

	var free_slots: int = CardDB.rules.base_max - pl.base.size()
	var best_uid := -1
	var best_score := -9999

	for i in basics.size():
		var c: Dictionary = basics[i]
		var cid := String(c.id)
		var d := CardDB.get_card(cid)
		var score := d.points * 3

		# 1) Melengkapi resep tersedia bersama kartu yang SUDAH ada di Zona Dasar -> PRIORITAS TERTINGGI!
		var matches_base_pts := 0
		for bc in pl.base:
			var bid := String(bc.id)
			if bid == cid:
				continue
			var res := CardDB.find_recipe(cid, bid)
			if res != "" and state.compound_pile.has(res):
				var rd := CardDB.get_card(res)
				var bd := CardDB.get_card(bid)
				var tot := (rd.points if rd else 0) + d.points + (bd.points if bd else 0)
				matches_base_pts = maxi(matches_base_pts, tot)
		if matches_base_pts > 0:
			score += 60 + matches_base_pts * 3

		# 2) Membentuk pasangan resep bersama kartu lain di TANGAN (siap dipasang berpasangan giliran ini!)
		var matches_hand_pts := 0
		if free_slots >= 2 or matches_base_pts > 0:
			for j in basics.size():
				if i == j:
					continue
				var oid := String(basics[j].id)
				if oid == cid:
					continue
				var res2 := CardDB.find_recipe(cid, oid)
				if res2 != "" and state.compound_pile.has(res2):
					var rd2 := CardDB.get_card(res2)
					var od2 := CardDB.get_card(oid)
					var tot2 := (rd2.points if rd2 else 0) + d.points + (od2.points if od2 else 0)
					matches_hand_pts = maxi(matches_hand_pts, tot2)
		if matches_hand_pts > 0:
			score += 34 + matches_hand_pts * 2

		# 3) Fleksibilitas unsur (O punya 5 resep, H punya 4 resep, Cl punya 2 resep)
		var open_recipes := _count_open_recipes(state, cid)
		score += open_recipes * 5

		# 4) Penalti duplikat ringan (hanya hindari menumpuk duplikat saat slot tinggal sedikit)
		var dup_count := int(base_counts.get(cid, 0))
		if dup_count > 0 and matches_base_pts == 0:
			score -= 22 if free_slots <= 2 else 10

		# 5) Neon (6 poin murni): sangat bagus jika masih ada >= 3 slot kosong
		if cid == "Ne":
			if free_slots <= 1:
				score -= 24
			elif free_slots >= 3:
				score += 12

		# 6) Disiplin slot ke-6 saja: jika tinggal 1 slot terakhir & tidak cocok resep sama sekali,
		# simpan slot terakhir itu untuk pasangan resep giliran depan (kecuali kartu poin >= 5)
		if free_slots == 1 and matches_base_pts == 0:
			if d.points < 5:
				score -= 50

		if score > best_score:
			best_score = score
			best_uid = int(c.uid)

	# Hanya tahan pemasangan jika slot tinggal 1 dan skornya negatif (jangan pernah pasif saat papan masih lega!)
	if free_slots == 1 and best_score < 0:
		return -1
	return best_uid

static func _count_open_recipes(state: GameState, elem_id: String) -> int:
	var n := 0
	var seen := {}
	for comp_id in state.compound_pile:
		if seen.has(comp_id):
			continue
		seen[comp_id] = true
		var cd := CardDB.get_card(String(comp_id))
		if cd != null and cd.recipe.has(elem_id):
			n += 1
	return n

static func _first_free_slot(base: Array, max_slots: int) -> int:
	var used := {}
	for i in base.size():
		used[int(base[i].get("slot", i))] = true
	for s in max_slots:
		if not used.has(s):
			return s
	return 0

# =============================================================================
# EVALUASI SPELL TAKTIS
# =============================================================================

static func _should_cast_spektrometer_now(state: GameState, pl: Dictionary, opp: Dictionary, diff: String) -> bool:
	if not bool(opp.shield) and not opp.special.is_empty():
		if _find_hand_spell(pl.hand, "elektrolisis_paksa") != -1:
			if diff != "easy" or opp.special.size() >= 2:
				return false
	return pl.base.size() < CardDB.rules.base_max

static func _should_cast_bilas(state: GameState, pl: Dictionary, diff: String) -> bool:
	var min_base := 4 if diff in ["hard", "extreme"] else 5
	if pl.base.size() < min_base:
		return false
	for bc in pl.base:
		var bid := String(bc.id)
		var has_partner := false
		for oc in pl.base:
			if int(oc.uid) != int(bc.uid) and String(oc.id) != bid:
				var res := CardDB.find_recipe(bid, String(oc.id))
				if res != "" and state.compound_pile.has(res):
					has_partner = true
					break
		if not has_partner:
			var bd := CardDB.get_card(bid)
			if bd != null and bd.points <= 3:
				return true
	return false

static func _best_spell_action(state: GameState, p: int, pl: Dictionary, opp: Dictionary, diff: String) -> Dictionary:
	# 1) Elektrolisis Paksa: pecah senyawa lawan bernilai tertinggi (Easy mulai aktif bila lawan punya >= 2 senyawa)
	if not bool(opp.shield) and not opp.special.is_empty():
		if diff != "easy" or opp.special.size() >= 2:
			var ep_uid := _find_hand_spell(pl.hand, "elektrolisis_paksa")
			if ep_uid != -1:
				var tgt := _pick_spell_target(state, p, "opp_special", diff)
				if tgt != -1:
					return {"type": "spell", "uid": ep_uid, "args": {"target_uid": tgt}}

	# 2) Korosi: patahkan pasangan resep lawan atau hancurkan kartu bernilai tinggi
	if not bool(opp.shield) and not opp.base.is_empty():
		var kor_uid := _find_hand_spell(pl.hand, "korosi")
		if kor_uid != -1:
			var best_threat := _highest_opp_base_threat(state, opp)
			var min_threat := 6 if diff in ["hard", "extreme"] else 4
			if best_threat.score >= min_threat and best_threat.uid != -1:
				return {"type": "spell", "uid": kor_uid, "args": {"target_uid": best_threat.uid}}

	# 3) Perisai Inert: lindungi papan saat punya senyawa atau pasangan siap sintesis
	if not bool(pl.shield):
		var sh_uid := _find_hand_spell(pl.hand, "perisai_inert")
		if sh_uid != -1:
			var worth_protecting: bool = (not pl.special.is_empty()) or _has_board_recipe_pair(state, pl) or pl.base.size() >= 3
			if worth_protecting:
				return {"type": "spell", "uid": sh_uid, "args": {}}

	# 4) Spektrometer cadangan
	if pl.deck.size() >= 3:
		var sp_uid := _find_hand_spell(pl.hand, "spektrometer")
		if sp_uid != -1:
			return {"type": "spell", "uid": sp_uid, "args": {}}

	# 5) Bilas bila Zona Dasar penuh kartu mati
	if pl.deck.size() >= 4 and _should_cast_bilas(state, pl, diff):
		var bil_uid := _find_hand_spell(pl.hand, "bilas")
		if bil_uid != -1:
			var tgt := _pick_spell_target(state, p, "my_base", diff)
			if tgt != -1:
				return {"type": "spell", "uid": bil_uid, "args": {"target_uid": tgt}}

	return {}

static func _has_board_recipe_pair(state: GameState, pl: Dictionary) -> bool:
	for i in pl.base.size():
		for j in range(i + 1, pl.base.size()):
			var a := String(pl.base[i].id)
			var b := String(pl.base[j].id)
			if a != b:
				var res := CardDB.find_recipe(a, b)
				if res != "" and state.compound_pile.has(res):
					return true
	return false

static func _highest_opp_base_threat(state: GameState, opp: Dictionary) -> Dictionary:
	var best_uid := -1
	var best_s := -999
	for c in opp.base:
		var cid := String(c.id)
		var d := CardDB.get_card(cid)
		var s := (d.points * 2) if d != null else 0
		var pair_bonus := 0
		for oc in opp.base:
			if int(oc.uid) == int(c.uid) or String(oc.id) == cid:
				continue
			var res := CardDB.find_recipe(cid, String(oc.id))
			if res != "" and state.compound_pile.has(res):
				var rd := CardDB.get_card(res)
				pair_bonus += 12 + (rd.points if rd != null else 0)
		s += pair_bonus
		if s > best_s:
			best_s = s
			best_uid = int(c.uid)
	return {"uid": best_uid, "score": best_s}

static func _find_hand_spell(hand: Array, effect_name: String) -> int:
	for c in hand:
		var d := CardDB.get_card(String(c.id))
		if d != null and d.type == CardData.Type.SPELL and String(d.spell_effect) == effect_name:
			return int(c.uid)
	return -1

# =============================================================================
# PILIHAN PENDING (Spektrometer & Target Spell)
# =============================================================================

static func _pick_spektrometer_card(state: GameState, p: int, cards: Array, diff: String) -> int:
	if cards.is_empty():
		return -1
	var pl: Dictionary = state.players[p]
	var opp: Dictionary = state.players[1 - p]
	var best_uid := int(cards[0].uid)
	var best_score := -9999

	for c in cards:
		var cid := String(c.id)
		var d := CardDB.get_card(cid)
		var score := 0
		if d != null:
			if d.type == CardData.Type.BASIC:
				score = d.points * 2 + _count_open_recipes(state, cid) * 4
				for bc in pl.base:
					if String(bc.id) != cid:
						var res := CardDB.find_recipe(cid, String(bc.id))
						if res != "" and state.compound_pile.has(res):
							var rd := CardDB.get_card(res)
							score += 34 + (rd.points * 2 if rd != null else 0)
							break
				for hc in pl.hand:
					if String(hc.id) != cid:
						var res2 := CardDB.find_recipe(cid, String(hc.id))
						if res2 != "" and state.compound_pile.has(res2):
							score += 16
							break
			elif d.type == CardData.Type.SPELL:
				match String(d.spell_effect):
					"elektrolisis_paksa":
						score = 38 if (not opp.special.is_empty() and not bool(opp.shield)) else 15
					"katalis":
						score = 32 if _has_board_recipe_pair(state, pl) else 18
					"korosi":
						score = 28 if (not opp.base.is_empty() and not bool(opp.shield)) else 14
					"perisai_inert":
						score = 22 if (not pl.special.is_empty() or _has_board_recipe_pair(state, pl)) else 11
					_:
						score = 10
		if diff == "easy":
			score += randi_range(-6, 6)
		if score > best_score:
			best_score = score
			best_uid = int(c.uid)
	return best_uid

static func _pick_spell_target(state: GameState, p: int, zone: String, diff: String) -> int:
	var pl: Dictionary = state.players[p]
	var opp: Dictionary = state.players[1 - p]
	match zone:
		"opp_base":
			return int(_highest_opp_base_threat(state, opp).uid)
		"opp_special":
			var best_uid := -1
			var best_s := -999
			for c in opp.special:
				var s := state._special_stack_points(c)
				if s > best_s:
					best_s = s
					best_uid = int(c.uid)
			return best_uid
		"my_base":
			var best_uid := -1
			var worst_s := 9999
			for c in pl.base:
				var cid := String(c.id)
				var d := CardDB.get_card(cid)
				var s := (d.points * 3) if d != null else 0
				for oc in pl.base:
					if int(oc.uid) != int(c.uid) and String(oc.id) != cid:
						var res := CardDB.find_recipe(cid, String(oc.id))
						if res != "" and state.compound_pile.has(res):
							s += 24
							break
				if s < worst_s:
					worst_s = s
					best_uid = int(c.uid)
			return best_uid
		"my_special":
			return int(pl.special[0].uid) if not pl.special.is_empty() else -1
	return -1
