extends Node

## Uji aturan tanpa UI, jalankan lewat F6 (bab 3.4).

var _ok := 0
var _fail := 0

func _ready() -> void:
    # 1. Ukuran data
    _check(CardDB.cards.size() == 26, "CardDB memuat 26 kartu")
    _check(CardDB.find_recipe("H", "O") == "H2O", "find_recipe(H,O)=H2O")
    _check(CardDB.find_recipe("O", "H") == "H2O", "find_recipe simetris")

    # 2. Setup awal
    var g := GameState.new()
    g.setup(12345)
    _check(g.players[0].hand.size() == CardDB.rules.start_hand + 1, "Tangan P0 = start_hand + 1")
    _check(g.players[1].hand.size() == CardDB.rules.start_hand, "Tangan P1 = start_hand")

    # 3. Bukan giliran
    _check(g.end_turn(1) != "", "P1 tidak bisa mengakhiri giliran P0")

    # 4. Cooldown
    var basic := _first_basic_in_hand(g, 0)
    if not basic.is_empty():
        _check(g.place_base(0, basic.uid) == "", "Pasang kartu dasar sukses")
        _check(g.synthesize(0, basic.uid, basic.uid) != "", "Sintesis kartu sama ditolak")
        _check(g.end_turn(0) == "", "Akhiri giliran P0 sukses")
        _check(g.end_turn(1) == "", "Akhiri giliran P1 sukses")

    # 5. Sintesis sebenarnya (cooldown dilewati dengan placed_turn lama)
    var g2 := GameState.new()
    g2.setup(999)
    var a := _force_base(g2, 0, "H")
    var b := _force_base(g2, 0, "O")
    var err := g2.synthesize(0, a.uid, b.uid)
    _check(err == "", "Sintesis H+O sukses")
    _check(g2.players[0].special.size() == 1, "Senyawa masuk slot special")
    _check(g2.players[0].points == CardDB.get_card("H2O").points, "Poin bertambah")

    # 6. Cooldown memblokir sintesis
    var g2b := GameState.new()
    g2b.setup(1001)
    var ca := _force_base(g2b, 0, "H", true)
    var cb := _force_base(g2b, 0, "O", true)
    _check(g2b.synthesize(0, ca.uid, cb.uid) != "", "Cooldown memblokir sintesis")

    # 7. Senyawa habis
    var g3 := GameState.new()
    g3.setup(7)
    g3.compound_pile.erase("H2O")
    var c1 := _force_base(g3, 0, "H")
    var c2 := _force_base(g3, 0, "O")
    _check(g3.synthesize(0, c1.uid, c2.uid) != "", "Senyawa habis ditolak")

    # 8. Menyerah
    var g4 := GameState.new()
    g4.setup(1)
    g4.surrender(0)
    _check(g4.winner == 1 and g4.win_reason == "surrender", "Menyerah menentukan pemenang")

    # 9. Batas tangan
    var g5 := GameState.new()
    g5.setup(2)
    for i in 20:
        g5.draw(0)
    _check(g5.players[0].hand.size() == CardDB.rules.hand_max, "Batas tangan ditegakkan")

    # 10. Bot acak menamatkan game
    var g6 := GameState.new()
    g6.setup(42)
    var guard := 0
    while g6.winner == -2 and guard < 500:
        _bot_turn(g6)
        guard += 1
    _check(guard < 500, "Bot acak menamatkan game")
    _check(g6.winner != -2, "Ada pemenang atau seri")

    print("== Hasil: %d lulus, %d gagal ==" % [_ok, _fail])
    get_tree().quit()

func _check(cond: bool, name: String) -> void:
    if cond:
        _ok += 1
        print("  OK    ", name)
    else:
        _fail += 1
        print("  GAGAL ", name)

func _first_basic_in_hand(g: GameState, p: int) -> Dictionary:
    for c in g.players[p].hand:
        if CardDB.get_card(c.id).type == CardData.Type.BASIC:
            return c
    return {}

func _force_base(g: GameState, p: int, id: String, cooldown := false) -> Dictionary:
    var c: Dictionary = g._new_card(id)
    c.placed_turn = g.turn_no if cooldown else g.turn_no - 5
    g.players[p].base.append(c)
    return c

func _bot_turn(g: GameState) -> void:
    var p := g.current
    var pl = g.players[p]
    for c in pl.hand.duplicate():
        if CardDB.get_card(c.id).type == CardData.Type.BASIC:
            g.place_base(p, c.uid)
    for a in pl.base.duplicate():
        for b in pl.base.duplicate():
            if a.uid < b.uid and g.synthesize(p, a.uid, b.uid) == "":
                break
    g.end_turn(p)
