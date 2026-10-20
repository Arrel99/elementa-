extends Control

## Lobby Host/Join (bab 6.4).

func _ready() -> void:
    $V/HostBtn.pressed.connect(_on_host)
    $V/JoinBtn.pressed.connect(_on_join)
    $V/Back.pressed.connect(_on_back)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): _status("Gagal terhubung. Cek IP dan jaringan."))
    Net.opponent_joined.connect(func(): _status("Lawan masuk. Mengecek versi..."))
    Net.version_rejected.connect(_on_rejected)

func _status(t: String) -> void:
    $V/Status.text = t

func _on_host() -> void:
    if Net.host() != OK:
        _status("Gagal membuat room (port 24567 sedang dipakai?).")
        return
    _status("Menunggu lawan... IP kamu: %s" % _local_ip())
    $V/HostBtn.disabled = true
    $V/JoinBtn.disabled = true

func _on_join() -> void:
    var ip: String = $V/IpEdit.text.strip_edges()
    if ip.is_empty():
        _status("Isi IP host dulu.")
        return
    if Net.join(ip) != OK:
        _status("IP tidak valid.")
        return
    _status("Menghubungkan...")

func _on_connected() -> void:      # hanya terpicu di klien
    _status("Terhubung. Mengecek versi...")
    Net.send_hello()

func _on_rejected(msg: String) -> void:
    _status(msg)
    multiplayer.multiplayer_peer = null

func _on_back() -> void:
    multiplayer.multiplayer_peer = null
    Net.reset()
    get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _local_ip() -> String:
    for ip in IP.get_local_addresses():
        if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("100."):
            return ip              # 100.x = Tailscale
    return "127.0.0.1"
