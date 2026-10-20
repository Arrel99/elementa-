extends Node

## Simulasi keseimbangan dengan bot acak (bab 11.4).
## Jalankan: godot --headless res://scenes/tools/simulate.tscn

func _ready() -> void:
    var p0 := 0
    var p1 := 0
    var draws := 0
    var total_turns := 0
    for i in 2000:
        var g := GameState.new()
        g.setup(i)
        var guard := 0
        while g.winner == -2 and guard < 500:
            _bot_turn(g)
            guard += 1
        total_turns += g.turn_no
        match g.winner:
            0: p0 += 1
            1: p1 += 1
            _: draws += 1
    print("P0 %d | P1 %d | seri %d | rata-rata giliran %.1f" % [p0, p1, draws, total_turns / 2000.0])
    get_tree().quit()

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
