extends RefCounted

## Database 5 skenario Puzzle Kimia (Mode Tantangan) yang melatih taktik Elementa.
## Semua puzzle dapat diselesaikan dalam 1 giliran menggunakan aturan resmi Elementa.

const PUZZLES := [
	{
		"id": "p1",
		"num": "01",
		"title": "Reaksi Penentu",
		"goal": "Sintesis 1 senyawa (Fe + O) untuk mencapai 8 senyawa dan langsung menang.",
		"me_special": ["H2O", "CO2", "NH3", "CH4", "HCl", "CaO", "CuO"],
		"me_base": ["Fe", "O", "N"],
		"me_hand": ["C", "H"],
		"opp_special": ["H2O", "CO2", "NH3", "CH4", "HCl"],
		"opp_base": ["Na", "Cl"],
		"compound_pile": ["Fe2O3", "NaCl", "H2O", "CO2", "CaO", "CuO", "NH3", "CH4"],
	},
	{
		"id": "p2",
		"num": "02",
		"title": "Efek Katalis",
		"goal": "Gunakan Katalis untuk melakukan 2 sintesis dalam 1 giliran (6 → 8 senyawa).",
		"me_special": ["H2O", "CO2", "NH3", "CH4", "HCl", "Fe2O3"],
		"me_base": ["Na", "Cl", "Ca", "O"],
		"me_hand": ["katalis"],
		"opp_special": ["H2O", "CO2", "NH3", "CH4", "HCl", "Fe2O3"],
		"opp_base": ["Cu", "O"],
		"compound_pile": ["NaCl", "CaO", "CuO", "H2O", "CO2", "NH3", "CH4", "HCl"],
	},
	{
		"id": "p3",
		"num": "03",
		"title": "Jangan Salah Pilih O",
		"goal": "Gunakan Katalis untuk 2 sintesis! Hati-hati: jangan habiskan O pada H2O.",
		"me_special": ["CO2", "NH3", "HCl", "CaO", "NaCl", "CuO"],
		"me_base": ["H", "O", "Fe", "C"],
		"me_hand": ["katalis"],
		"opp_special": ["CO2", "NH3", "HCl", "CaO", "NaCl", "CuO"],
		"opp_base": ["Na", "Cl"],
		"compound_pile": ["H2O", "Fe2O3", "CH4", "CO2", "NH3", "HCl", "CaO", "NaCl"],
	},
	{
		"id": "p4",
		"num": "04",
		"title": "Triple Katalis",
		"goal": "Katalis tidak memakai jatah Spell! Lakukan 3 sintesis sekaligus (5 → 8 senyawa).",
		"me_special": ["H2O", "CO2", "NH3", "HCl", "CaO"],
		"me_base": ["Na", "Cl", "Cu", "O", "C", "H"],
		"me_hand": ["katalis", "katalis"],
		"opp_special": ["H2O", "CO2", "NH3", "HCl", "CaO", "Fe2O3"],
		"opp_base": ["Fe", "O"],
		"compound_pile": ["NaCl", "CuO", "CH4", "Fe2O3", "H2O", "CO2", "NH3", "HCl"],
	},
	{
		"id": "p5",
		"num": "05",
		"title": "Master Reaksi",
		"goal": "Stok terbatas! Pilih 2 pasangan yang tidak saling memakan unsur bersama Katalis.",
		"me_special": ["H2O", "CO2", "NH3", "CaO", "CuO", "H2O"],
		"me_base": ["H", "Cl", "Na", "O", "Fe"],
		"me_hand": ["katalis", "perisai_inert"],
		"opp_special": ["CO2", "NH3", "CaO", "CuO", "CH4", "Fe2O3", "HCl"],
		"opp_base": ["C", "H"],
		"compound_pile": ["HCl", "NaCl", "Fe2O3", "CH4", "CaO", "CuO", "NH3", "CO2"],
	},
]

static func get_puzzle(pid: String) -> Dictionary:
	for p in PUZZLES:
		if String(p.id) == pid:
			return p
	return {}

static func apply_puzzle(state: GameState, pid: String) -> Dictionary:
	var p := get_puzzle(pid)
	if p.is_empty():
		state.setup(randi(), false)
		return {}

	state.setup(7000 + pid.hash(), false)
	state.current = 0
	state.turn_no = 2
	state.synth_left = 1
	state.spell_left = 1
	state.coin_phase = {}
	state.pending = {}
	state.history = []

	for i in 2:
		state.players[i].hand.clear()
		state.players[i].base.clear()
		state.players[i].special.clear()
		state.players[i].active_spells.clear()
		state.players[i].discard.clear()

	state.compound_pile = []
	for cid in p.compound_pile:
		state.compound_pile.append(String(cid))

	for cid in p.me_hand:
		state.players[0].hand.append(state._new_card(String(cid)))
	for i in p.me_base.size():
		var c := state._new_card(String(p.me_base[i]))
		c.placed_turn = 1   # sudah bebas cooldown (siap sintesis di giliran 2!)
		c["slot"] = i
		state.players[0].base.append(c)
	for cid in p.me_special:
		var sc := state._new_card(String(cid))
		var d := CardDB.get_card(String(cid))
		if d != null and d.recipe.size() == 2:
			sc["parts"] = [String(d.recipe[0]), String(d.recipe[1])]
			sc["attached"] = [state._new_card(String(d.recipe[0])), state._new_card(String(d.recipe[1]))]
		state.players[0].special.append(sc)

	for i in p.opp_base.size():
		var c := state._new_card(String(p.opp_base[i]))
		c.placed_turn = 1
		c["slot"] = i
		state.players[1].base.append(c)
	for cid in p.opp_special:
		var sc := state._new_card(String(cid))
		var d := CardDB.get_card(String(cid))
		if d != null and d.recipe.size() == 2:
			sc["parts"] = [String(d.recipe[0]), String(d.recipe[1])]
			sc["attached"] = [state._new_card(String(d.recipe[0])), state._new_card(String(d.recipe[1]))]
		state.players[1].special.append(sc)

	state._recalc_points(0)
	state._recalc_points(1)
	return p
