extends Node

## Uji E2E dua proses untuk lobby kode room (bukan bagian game).
## Proses A: godot --headless res://scenes/tools/net_e2e.tscn -- --role=host --code=1234
## Proses B: godot --headless res://scenes/tools/net_e2e.tscn -- --role=guest --code=1234
## Lulus bila kedua proses mencetak "MASUK GAME".

var role := "host"
var code := "1234"
var _lobby: Control

func _ready() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--role="):
            role = a.get_slice("=", 1)
        elif a.begins_with("--code="):
            code = a.get_slice("=", 1)
    print("[e2e] mulai role=%s code=%s" % [role, code])

    # Pengawas hidup di root supaya tetap ada setelah scene game dimuat.
    var mon: Node = load("res://scripts/tools/net_e2e_monitor.gd").new()
    mon.set("role", role)
    get_tree().root.add_child.call_deferred(mon)

    # Lobby ditaruh di root (bukan current_scene) supaya tidak ikut dibebaskan
    # saat Net.start_game mengganti scene ke game.tscn.
    _lobby = load("res://scenes/screens/lobby.tscn").instantiate()
    get_tree().root.add_child.call_deferred(_lobby)
    await get_tree().process_frame

    if role == "host":
        _lobby.get_node("V/Panels/HostBox/Margin/HostV/BtnHost").pressed.emit()
    else:
        _guest()

func _guest() -> void:
    var deadline := Time.get_ticks_msec() + 15000
    while Time.get_ticks_msec() < deadline:
        await get_tree().create_timer(0.5).timeout
        if Lan.rooms.is_empty():
            continue
        var room: Dictionary = Lan.rooms[0]
        print("[e2e] room terdeteksi: kode=%s ip=%s nama=%s" % [
            room["code"], room["ip"], room.get("name", "")])
        code = String(room["code"])          # tamu mengetik kode yang terlihat
        _lobby.get_node("V/Panels/JoinBox/Margin/JoinV/Row/CodeEdit").text = code
        _lobby.get_node("V/Panels/JoinBox/Margin/JoinV/Row/BtnCode").pressed.emit()
        return
    print("[e2e] GAGAL: tidak ada room terdeteksi")
    get_tree().quit(2)
