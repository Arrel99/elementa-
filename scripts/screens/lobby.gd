extends Control

## Lobby (bab 6.4): host membagikan kode room, tamu memilih room di WiFi yang
## sama. Pemain tidak perlu mengetik IP; IP hanya dipakai jalur cadangan.

const CONNECT_TIMEOUT := 8.0

@onready var _btn_host: Button = $V/Panels/HostBox/Margin/HostV/BtnHost
@onready var _code: Label = $V/Panels/HostBox/Margin/HostV/Code
@onready var _code_hint: Label = $V/Panels/HostBox/Margin/HostV/CodeHint
@onready var _ip_label: Label = $V/Panels/HostBox/Margin/HostV/IpLabel
@onready var _rooms: ItemList = $V/Panels/JoinBox/Margin/JoinV/Rooms
@onready var _code_edit: LineEdit = $V/Panels/JoinBox/Margin/JoinV/Row/CodeEdit
@onready var _btn_code: Button = $V/Panels/JoinBox/Margin/JoinV/Row/BtnCode
@onready var _btn_refresh: Button = $V/Panels/JoinBox/Margin/JoinV/BtnRefresh
@onready var _status: Label = $V/Status
@onready var _btn_manual: Button = $V/BtnManual
@onready var _manual_row: HBoxContainer = $V/ManualRow
@onready var _ip_edit: LineEdit = $V/ManualRow/IpEdit
@onready var _btn_ip: Button = $V/ManualRow/BtnIp
@onready var _btn_back: Button = $V/BtnBack

var _timeout := Timer.new()
var _hosting := false
var _joining := false
var _last_count := -1          # jumlah room yang terakhir ditampilkan
var _reject_msg := ""          # pesan terakhir dari host, agar tidak tertimpa
var _status_stamp := 0         # kapan status terakhir ditulis (ms)

func _ready() -> void:
    _btn_host.pressed.connect(_on_host)
    _btn_code.pressed.connect(_on_join_code)
    _code_edit.text_submitted.connect(func(_t: String): _on_join_code())
    _btn_refresh.pressed.connect(_on_refresh)
    _rooms.item_activated.connect(_on_room_pick)
    _btn_manual.toggled.connect(func(on: bool): _manual_row.visible = on)
    _btn_ip.pressed.connect(_on_join_ip)
    _ip_edit.text_submitted.connect(func(_t: String): _on_join_ip())
    _btn_back.pressed.connect(_on_back)

    Lan.rooms_changed.connect(_refresh_rooms)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(_on_failed)
    multiplayer.server_disconnected.connect(_on_server_gone)
    Net.opponent_joined.connect(_on_opponent_joined)
    Net.version_rejected.connect(_on_rejected)

    _timeout.one_shot = true
    _timeout.wait_time = CONNECT_TIMEOUT
    _timeout.timeout.connect(_on_timeout)
    add_child(_timeout)

    Lan.start_scan()
    _refresh_rooms()

func _exit_tree() -> void:
    _timeout.stop()
    Lan.stop_scan()
    Lan.stop_room()

func _status_text(t: String) -> void:
    _status.text = t
    _status_stamp = Time.get_ticks_msec()

## Beri waktu pesan penting (mis. "room tidak ditemukan") terbaca sebelum
## daftar room menimpanya dengan info jumlah room.
func _status_quiet(ms: int) -> bool:
    return Time.get_ticks_msec() - _status_stamp < ms

# --- Host -------------------------------------------------------------------

func _on_host() -> void:
    if _hosting:
        return
    var code := "%04d" % randi_range(1000, 9999)
    if Net.host(code) != OK:
        _status_text("Gagal membuat room. Port 24567 mungkin dipakai aplikasi lain.")
        return

    _hosting = true
    Lan.stop_scan()                  # jangan melihat room sendiri
    _code.text = code
    _btn_host.disabled = true
    _btn_code.disabled = true
    _btn_refresh.disabled = true

    var broadcast := Lan.start_room(code)
    if broadcast:
        _code_hint.text = "Bagikan kode %s. Pemain kedua cukup memilih room ini di daftar." % code
        _ip_label.text = "IP host %s (cadangan bila pencarian gagal)" % _local_ip()
        _status_text("Menunggu lawan...")
    else:
        _code_hint.text = "Kode %s tidak bisa disiarkan (port 24568 dipakai proses lain)." % code
        _ip_label.text = "Pakai \"Koneksi manual\" di komputer lawan dengan IP %s" % _local_ip()
        _status_text("Menunggu lawan (mode IP manual)...")

func _on_opponent_joined() -> void:
    if _hosting:
        _status_text("Lawan masuk. Mengecek kode & versi...")

# --- Tamu -------------------------------------------------------------------

func _on_refresh() -> void:
    Lan.rescan()
    _status_text("Mencari room di WiFi ini...")

func _on_room_pick(index: int) -> void:
    var room: Dictionary = _rooms.get_item_metadata(index)
    _code_edit.text = String(room.get("code", ""))
    _connect_to(String(room.get("ip", "")), String(room.get("code", "")))

func _on_join_code() -> void:
    if _joining or _hosting:
        return
    var code := _code_edit.text.strip_edges()
    if code.is_empty():
        var sel := _rooms.get_selected_items()
        if sel.is_empty():
            _status_text("Pilih room di daftar, atau ketik kodenya.")
            return
        code = String(_rooms.get_item_metadata(sel[0]).get("code", ""))
    var room := Lan.find_room(code)
    if room.is_empty():
        _status_text("Room %s belum ditemukan di WiFi ini. Pastikan host sudah menekan \"Buat Room\" dan kalian satu jaringan." % code)
        Lan.rescan()
        return
    _connect_to(String(room["ip"]), String(room["code"]))

func _on_join_ip() -> void:
    if _joining or _hosting:
        return
    var ip := _ip_edit.text.strip_edges()
    if ip.is_empty():
        _status_text("Isi IP host dulu.")
        return
    _connect_to(ip, "")

func _connect_to(ip: String, code: String) -> void:
    if ip.is_empty():
        _status_text("Alamat room tidak valid. Coba \"Cari ulang room\".")
        return
    if Net.join(ip, code) != OK:
        _status_text("Tidak bisa membuka koneksi ke %s." % ip)
        return
    _joining = true
    _btn_host.disabled = true
    _btn_code.disabled = true
    _btn_refresh.disabled = true
    if code.is_empty():
        _status_text("Menghubungkan ke %s..." % ip)
    else:
        _status_text("Menghubungkan ke room %s (%s)..." % [code, ip])
    _timeout.start()

func _on_connected() -> void:
    if not _joining:
        return
    _timeout.stop()
    _status_text("Terhubung. Mengecek kode & versi game...")
    Net.send_hello()

func _on_failed() -> void:
    if not _joining:
        return                       # sudah direset jalur lain (timeout/reject)
    _timeout.stop()
    _reset_connection()
    _status_text("Gagal terhubung. Kemungkinan firewall Windows memblokir port 24567 — izinkan Godot untuk jaringan Private di komputer host, lalu coba lagi.")

func _on_timeout() -> void:
    if not _joining:
        return
    _reset_connection()
    _status_text("Host tidak menjawab. Periksa firewall Windows di komputer host, atau pastikan kalian satu WiFi.")

func _on_server_gone() -> void:
    if not _joining:
        return
    _reset_connection()
    if _reject_msg.is_empty():
        _status_text("Host keluar. Coba gabung lagi.")
    else:
        _status_text(_reject_msg)
        _reject_msg = ""

func _on_rejected(msg: String) -> void:
    _timeout.stop()
    _reject_msg = msg
    _reset_connection()
    _status_text(msg)

func _reset_connection() -> void:
    _joining = false
    _btn_host.disabled = _hosting
    _btn_code.disabled = false
    _btn_refresh.disabled = false
    multiplayer.multiplayer_peer = null
    Net.reset()
    if not _hosting:
        Lan.start_scan()

# --- Lain-lain --------------------------------------------------------------

func _refresh_rooms() -> void:
    if _hosting:
        return
    var selected := _rooms.get_selected_items()
    var keep_code := ""
    if not selected.is_empty():
        keep_code = String(_rooms.get_item_metadata(selected[0]).get("code", ""))

    var list := Lan.rooms.duplicate()
    list.sort_custom(_by_code)

    _rooms.clear()
    var keep := -1
    for r in list:
        var label := "%s    %s" % [r["code"], r.get("name", r["ip"])]
        var idx := _rooms.add_item(label)
        _rooms.set_item_metadata(idx, r)
        if keep_code != "" and String(r["code"]) == keep_code:
            keep = idx
    if keep >= 0:
        _rooms.select(keep)

    if _joining:
        return
    # Jangan menimpa pesan error setiap kali daftar diperbarui.
    if _status_quiet(2500):
        return
    if list.size() == _last_count:
        return
    _last_count = list.size()
    if list.is_empty():
        _status_text("Belum ada room. Minta temanmu menekan \"Buat Room\".")
    else:
        _status_text("Ada %d room di WiFi ini. Klik dua kali untuk gabung." % list.size())

func _by_code(a: Dictionary, b: Dictionary) -> bool:
    return String(a["code"]) < String(b["code"])


func _on_back() -> void:
    Lan.stop_scan()
    Lan.stop_room()
    multiplayer.multiplayer_peer = null
    Net.reset()
    get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _local_ip() -> String:
    var fallback := "127.0.0.1"
    for ip in IP.get_local_addresses():
        if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
            continue
        if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("100."):
            return ip              # 100.x = Tailscale
        if ip.begins_with("172."):
            fallback = ip
    return fallback
