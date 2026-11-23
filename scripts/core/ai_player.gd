extends RefCounted

## AI taktis cerdas untuk mode VS. AI di Elementa (4 tingkat kesulitan):
## - "easy"    : Santai, kadang memasang unsur acak & jarang memakai spell ofensif.
## - "normal"  : Cerdas & seimbang, menjaga slot Zona Dasar, memakai Spektrometer lebih dulu.
## - "hard"    : Taktis & agresif, menghemat unsur kunci (O/H/Cl), memakai Katalis & gangguan tepat sasaran.
## - "extreme" : Optimal tanpa ampun — optimasi pasangan sintesis ganda, baca ancaman lawan,
##               disiplin slot Zona Dasar, dan manajemen sumber daya unsur/spell penuh.

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
			# Di Elementa, giliran kedua menarik 2 kartu lebih dulu (keunggulan kartu),
			# sedangkan giliran pertama memasang papan lebih dulu (tempo).
			var prefer_first := 0.50 if diff == "easy" else (0.65 if diff == "normal" else 0.78)
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

	# 3) URUTAN 1 — Kemenangan instan / Sintesis optimal (termasuk perencanaan sintesis ganda!)
	if state.synth_left > 0 and pl.special.size() < CardDB.rules.special_max:
		var synth_plan := _choose_best_synthesis(state, p, diff, has_katalis)
		if not synth_plan.is_empty():
			if diff != "easy" or randf() < 0.78:
				return {"type": "synth", "a": int(synth_plan.a), "b": int(synth_plan.b)}

	# 4) URUTAN 2 — Katalis: jika jatah sintesis habis tapi masih ada pasangan siap sintesis
	if diff != "easy" and state.synth_left == 0 and pl.special.size() < CardDB.rules.special_max:
		var extra_plan := _choose_best_synthesis(state, p, diff, false)
		if not extra_plan.is_empty():
			var kat_uid := _find_hand_spell(pl.hand, "katalis")
			if kat_uid != -1:
				return {"type": "spell", "uid": kat_uid, "args": {}}

	# 5) URUTAN 3 — Gangguan darurat (Hard/Extreme): jika lawan punya >= 6 senyawa, segera pecah!
	if diff in ["hard", "extreme"] and state.spell_left > 0 and not bool(opp.shield):
		if opp.special.size() >= 6:
			var ep_urgent := _find_hand_spell(pl.hand, "elektrolisis_paksa")
			if ep_urgent != -1:
				var tgt := _pick_spell_target(state, p, "opp_special", diff)
				if tgt != -1:
					return {"type": "spell", "uid": ep_urgent, "args": {"target_uid": tgt}}

	# 6) URUTAN 4 — Spektrometer SEBELUM memasang kartu (agar kartu hasil intip bisa langsung dipasang!)
	if diff != "easy" and state.spell_left > 0 and pl.deck.size() >= 3:
		var sp_uid := _find_hand_spell(pl.hand, "spektrometer")
		if sp_uid != -1 and _should_cast_spektrometer_now(state, p, pl, opp, diff):
			return {"type": "spell", "uid": sp_uid, "args": {}}

	# 7) URUTAN 5 — Bilas SEBELUM memasang kartu bila Zona Dasar penuh kartu mati (bebaskan slot + tarik kartu!)
	if diff != "easy" and state.spell_left > 0 and pl.deck.size() >= 4:
		var bil_uid := _find_hand_spell(pl.hand, "bilas")
		if bil_uid != -1 and _should_cast_bilas(state, p, pl, diff):
			var tgt := _pick_spell_target(state, p, "my_base", diff)
			if tgt != -1:
				return {"type": "spell", "uid": bil_uid, "args": {"target_uid": tgt}}

	# 8) URUTAN 6 — Pasang kartu dasar dengan disiplin slot & sinergi resep
	if pl.base.size() < CardDB.rules.base_max:
		var placed_this_turn := 0
		for bc in pl.base:
			if int(bc.placed_turn) == state.turn_no:
				placed_this_turn += 1
		var max_per_turn := 1 if diff == "easy" else (3 if diff == "normal" else 6)
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
# SINTESIS OPTIMAL (termasuk perencanaan pasangan ganda & konservasi unsur O/H/Cl)
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
	if diff == "easy":
		return cands[randi() % cands.size()]

	# Jika sintesis ini langsung memenangkan pertandingan (senyawa ke-8), langsung ambil!
	if pl.special.size() + 1 >= CardDB.rules.special_win_threshold:
		cands.sort_custom(func(x, y): return int(x.stack_pts) > int(y.stack_pts))
		return cands[0]

	# Jika bisa melakukan >= 2 sintesis giliran ini (synth_left >= 2 atau punya Katalis),
	# cari kombinasi 2 sintesis yang TIDAK saling memakan unsur yang sama agar total poin maksimal!
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

	# Skor tiap kandidat sintesis (mempertimbangkan total skor tumpukan + kelangkaan + penghematan O/H/Cl)
	var best := {}
	var best_val := -9999
	for c in cands:
		var val := int(c.stack_pts) * 2
		if state.compound_pile.count(String(c.res)) == 1:
			val += 5 if diff == "extreme" else 3

		# Konservasi unsur kunci (Hard/Extreme): jangan buru-buru korbankan satu-satunya 'O'
		# untuk H2O (8 poin) bila 'Fe' atau 'Cu' (16-17 poin) sudah ada di Zona Dasar atau Tangan!
		if diff in ["hard", "extreme"] and int(c.comp_pts) <= 6 and pl.base.size() < 5:
			if _should_hold_for_better_recipe(state, p, c):
				val -= 40

		if val > best_val:
			best_val = val
			best = c

	# Jika satu-satunya sintesis adalah senyawa murah yang lebih baik ditahan 1 giliran
	if diff == "extreme" and best_val < 0:
		return {}
	return best

## Mengecek apakah unsur pada kandidat sintesis murah (seperti H2O / HCl) sebaiknya disimpan
## 1 giliran karena pasangan bernilai jauh lebih tinggi (Fe2O3 / CuO / NaCl) sudah ada di papan/tangan.
static func _should_hold_for_better_recipe(state: GameState, p: int, cand: Dictionary) -> bool:
	var pl: Dictionary = state.players[p]
	var a_id := String(cand.a_id)
	var b_id := String(cand.b_id)
	var cand_pts := int(cand.stack_pts)

	for key_id in [a_id, b_id]:
		# Jika kita punya >= 2 salinan unsur kunci ini di papan, tidak perlu menahan
		var count_on_board := 0
		for bc in pl.base:
			if String(bc.id) == key_id:
				count_on_board += 1
		if count_on_board >= 2:
			continue
		# Cek apakah ada unsur lain di papan (baru dipasang / cooldown) atau di tangan yang menghasilkan +5 poin lebih tinggi
		for pool in [pl.base, pl.hand]:
			for other in pool:
				var oid := String(other.id)
				if oid == a_id or oid == b_id:
					continue
				var better_res := CardDB.find_recipe(key_id, oid)
				if better_res != "" and state.compound_pile.has(better_res):
					var rd := CardDB.get_card(better_res)
					var kd := CardDB.get_card(key_id)
					var od := CardDB.get_card(oid)
					var better_pts := (rd.points if rd else 0) + (kd.points if kd else 0) + (od.points if od else 0)
					if better_pts >= cand_pts + 6:
						return true
	return false

# =============================================================================
# PENEMPATAN KARTU DASAR (Sinergi Resep + Disiplin Slot Zona Dasar)
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

	if diff == "easy" and randf() < 0.50:
		return int(basics[randi() % basics.size()].uid)

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

		# 1) Cek apakah langsung melengkapi resep tersedia dengan kartu yang SUDAH di Zona Dasar
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
			score += 45 + matches_base_pts * 3

		# 2) Cek apakah membentuk pasangan resep dengan kartu lain di TANGAN (bisa dipasang berpasangan!)
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
			score += 22 + matches_hand_pts * 2

		# 3) Nilai fleksibilitas unsur (O, H, Cl punya banyak resep yang masih tersedia di deck senyawa)
		var open_recipes := _count_open_recipes(state, cid)
		score += open_recipes * 4

		# 4) Penalti duplikat & disiplin slot agar Zona Dasar TIDAK pernah macet!
		var dup_count := int(base_counts.get(cid, 0))
		if dup_count > 0:
			# Duplikat hanya layak bila masih banyak slot kosong dan unsur itu fleksibel (mis. O)
			if matches_base_pts == 0:
				score -= 32 if free_slots <= 2 else (20 if open_recipes <= 1 else 10)
			else:
				score -= 8

		# Neon (Ne) bernilai 6 poin murni tetapi tidak bisa disintesis:
		# Bagus bila masih ada ruang (>= 3 slot kosong), tapi jangan sampai menyumbat slot terakhir!
		if cid == "Ne":
			if free_slots <= 2:
				score -= 35
			elif free_slots == 3:
				score -= 10
			else:
				score += 8

		# Disiplin slot terakhir: jika tinggal 1 slot kosong, JANGAN isi dengan kartu yatim tanpa resep!
		if diff != "easy" and free_slots == 1 and matches_base_pts == 0:
			score -= 60

		# Jika tinggal 2 slot kosong dan tidak cocok dengan papan maupun tangan, tahan dulu!
		if diff in ["hard", "extreme"] and free_slots <= 2 and matches_base_pts == 0 and matches_hand_pts == 0:
			score -= 28

		if score > best_score:
			best_score = score
			best_uid = int(c.uid)

	# Jangan memasang kartu yang skornya negatif (mencegah menyumbat Zona Dasar!)
	if diff != "easy" and best_score < 6:
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

static func _should_cast_spektrometer_now(state: GameState, p: int, pl: Dictionary, opp: Dictionary, diff: String) -> bool:
	# Jangan pakai Spektrometer dulu jika kita punya serangan jauh lebih penting (Elektrolisis Paksa pada lawan kuat)
	if not bool(opp.shield) and not opp.special.is_empty():
		if _find_hand_spell(pl.hand, "elektrolisis_paksa") != -1:
			var max_opp_sp := 0
			for sc in opp.special:
				max_opp_sp = maxi(max_opp_sp, state._special_stack_points(sc))
			if max_opp_sp >= 12 or opp.special.size() >= 4:
				return false
	# Jika tidak ada pasangan siap pasang di tangan, Spektrometer di awal giliran sangat kuat!
	return pl.base.size() < CardDB.rules.base_max

static func _should_cast_bilas(state: GameState, p: int, pl: Dictionary, diff: String) -> bool:
	var min_base := 4 if diff == "extreme" else 5
	if pl.base.size() < min_base:
		return false
	# Hanya pakai Bilas jika benar-benar ada kartu mati (tidak cocok resep dengan kartu lain di papan)
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

	# 1) Elektrolisis Paksa: selalu hancurkan senyawa lawan bernilai tinggi (jika tidak berperisai)
	if not bool(opp.shield) and not opp.special.is_empty():
		var ep_uid := _find_hand_spell(pl.hand, "elektrolisis_paksa")
		if ep_uid != -1:
			var tgt := _pick_spell_target(state, p, "opp_special", diff)
			if tgt != -1:
				return {"type": "spell", "uid": ep_uid, "args": {"target_uid": tgt}}

	# 2) Korosi: hancurkan unsur kunci/berbahaya lawan (prioritas mematahkan resep siap sintesis lawan!)
	if not bool(opp.shield) and not opp.base.is_empty():
		var kor_uid := _find_hand_spell(pl.hand, "korosi")
		if kor_uid != -1:
			var best_threat := _highest_opp_base_threat(state, opp)
			# Di Hard/Extreme, jangan buang Korosi pada kartu 1 poin yatim kalau masih ada opsi lain
			var min_threat := 6 if diff in ["hard", "extreme"] else 2
			if best_threat.score >= min_threat and best_threat.uid != -1:
				return {"type": "spell", "uid": kor_uid, "args": {"target_uid": best_threat.uid}}

	# 3) Perisai Inert: lindungi papan ketika AI punya pasangan siap sintesis giliran depan ATAU senyawa berharga
	if not bool(pl.shield):
		var sh_uid := _find_hand_spell(pl.hand, "perisai_inert")
		if sh_uid != -1:
			var worth_protecting: bool = (not pl.special.is_empty()) or _has_board_recipe_pair(state, pl) or pl.base.size() >= 3
			if worth_protecting:
				return {"type": "spell", "uid": sh_uid, "args": {}}

	# 4) Spektrometer cadangan bila belum dipakai di awal giliran
	if pl.deck.size() >= 3:
		var sp_uid := _find_hand_spell(pl.hand, "spektrometer")
		if sp_uid != -1:
			return {"type": "spell", "uid": sp_uid, "args": {}}

	# 5) Bilas bila Zona Dasar penuh kartu mati
	if pl.deck.size() >= 4 and _should_cast_bilas(state, p, pl, diff):
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

## Mengukur ancaman tiap kartu di Zona Dasar lawan (kartu yang menjadi poros resep lawan diberi skor tertinggi).
static func _highest_opp_base_threat(state: GameState, opp: Dictionary) -> Dictionary:
	var best_uid := -1
	var best_s := -999
	for c in opp.base:
		var cid := String(c.id)
		var d := CardDB.get_card(cid)
		var s := (d.points * 2) if d != null else 0
		# Hitung berapa banyak resep tersedia yang bisa dibuat kartu ini bersama kartu lawan lainnya!
		var pair_bonus := 0
		for oc in opp.base:
			if int(oc.uid) == int(c.uid) or String(oc.id) == cid:
				continue
			var res := CardDB.find_recipe(cid, String(oc.id))
			if res != "" and state.compound_pile.has(res):
				var rd := CardDB.get_card(res)
				pair_bonus += 10 + (rd.points if rd != null else 0)
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
	if diff == "easy":
		return int(cards[randi() % cards.size()].uid)
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
				score = d.points * 2 + _count_open_recipes(state, cid) * 3
				# Bonus terbesar: langsung melengkapi resep dengan kartu di Zona Dasar AI!
				for bc in pl.base:
					if String(bc.id) != cid:
						var res := CardDB.find_recipe(cid, String(bc.id))
						if res != "" and state.compound_pile.has(res):
							var rd := CardDB.get_card(res)
							score += 28 + (rd.points * 2 if rd != null else 0)
							break
				# Bonus sedang: cocok dengan kartu di tangan AI
				for hc in pl.hand:
					if String(hc.id) != cid:
						var res2 := CardDB.find_recipe(cid, String(hc.id))
						if res2 != "" and state.compound_pile.has(res2):
							score += 12
							break
			elif d.type == CardData.Type.SPELL:
				match String(d.spell_effect):
					"elektrolisis_paksa":
						score = 34 if (not opp.special.is_empty() and not bool(opp.shield)) else 14
					"katalis":
						score = 30 if _has_board_recipe_pair(state, pl) else 16
					"korosi":
						score = 26 if (not opp.base.is_empty() and not bool(opp.shield)) else 12
					"perisai_inert":
						score = 20 if (not pl.special.is_empty() or _has_board_recipe_pair(state, pl)) else 10
					_:
						score = 9
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
