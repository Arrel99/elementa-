extends Node

## Pengawas E2E: hidup di root (tidak ikut dibebaskan saat scene berganti),
## mencetak hasil lalu menutup proses.

var role := "host"
var _start := 0

func _ready() -> void:
    _start = Time.get_ticks_msec()
    _loop()

func _loop() -> void:
    while true:
        await get_tree().create_timer(1.0).timeout
        var path := ""
        if get_tree().current_scene:
            path = get_tree().current_scene.scene_file_path
        if path.ends_with("game.tscn"):
            print("[e2e] %s MASUK GAME" % role)
            # Kedua proses memeriksa pada jadwal yang sama, sebelum ada yang
            # keluar (keluarnya host membuat tamu kembali ke menu).
            await get_tree().create_timer(1.5).timeout
            var gs := get_tree().current_scene
            if gs and gs.scene_file_path.ends_with("game.tscn"):
                if gs.get("state") != null:
                    print("[e2e] %s state siap, giliran=%d" % [role, gs.state.turn_no])
                elif not gs.view.is_empty():
                    print("[e2e] %s view diterima, giliran=%d" % [role, gs.view.turn_no])
                else:
                    print("[e2e] %s PERINGATAN: belum ada state/view" % role)
            await get_tree().create_timer(1.5).timeout
            print("[e2e] %s SELESAI" % role)
            get_tree().quit(0)
            return
        if Time.get_ticks_msec() - _start > 25000:
            print("[e2e] %s GAGAL: tidak sampai ke game" % role)
            get_tree().quit(1)
            return
        var lobby := get_tree().root.get_node_or_null("Lobby")
        if lobby and lobby.has_node("V/Status"):
            print("[e2e] %s status: %s" % [role, lobby.get_node("V/Status").text])
