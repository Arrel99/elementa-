extends Node

## Autoload Net (bab 6.1 dan 6.4). Host-authoritative ENet.
## Semua sinyal siap dipindahkan ke autoload ini supaya selalu bisa
## dijangkau sebelum scene game dimuat.
##
## Koneksi memakai kode room (§6.4): host membuat kode 4 angka, tamu memilih
## room dari daftar `Lan` (penemuan di WiFi yang sama), lalu `hello` memeriksa
## kode itu. IP hanya dipakai sebagai jalur cadangan.

const PORT := 24567
const GAME_VERSION := "0.3.0"

signal opponent_joined
signal opponent_left
signal client_ready
signal version_rejected(msg: String)

var client_loaded := false
var local_test := false
var room_code := ""            # kode yang dipakai host untuk menyaring tamu

func _ready() -> void:
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(_id: int) -> void:
    opponent_joined.emit()

func _on_peer_disconnected(_id: int) -> void:
    opponent_left.emit()

func host(code: String = "") -> Error:
    multiplayer.multiplayer_peer = null
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(PORT, 1)   # maksimal 1 klien
    if err == OK:
        multiplayer.multiplayer_peer = peer
        room_code = code
    return err

func join(ip: String, code: String = "") -> Error:
    multiplayer.multiplayer_peer = null
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(ip, PORT)
    if err == OK:
        multiplayer.multiplayer_peer = peer
        room_code = code
    return err

func reset() -> void:
    client_loaded = false
    local_test = false
    room_code = ""

func send_hello() -> void:
    hello.rpc_id(1, GAME_VERSION, CardDB.cards_hash(), room_code)

@rpc("any_peer", "call_remote", "reliable")
func hello(version: String, cards_hash: int, code: String) -> void:
    if not multiplayer.is_server():
        return
    var id := multiplayer.get_remote_sender_id()
    if version != GAME_VERSION or cards_hash != CardDB.cards_hash():
        rejected.rpc_id(id, "Versi game berbeda. Perbarui game kamu.")
        multiplayer.multiplayer_peer.disconnect_peer(id)
        return
    # Kode kosong = tamu memakai jalur cadangan IP manual.
    if not room_code.is_empty() and not code.is_empty() and code != room_code:
        rejected.rpc_id(id, "Kode room salah. Minta ulang kode dari host.")
        multiplayer.multiplayer_peer.disconnect_peer(id)
        return
    start_game.rpc()

@rpc("authority", "call_remote", "reliable")
func rejected(msg: String) -> void:
    version_rejected.emit(msg)

@rpc("authority", "call_local", "reliable")
func start_game() -> void:
    get_tree().change_scene_to_file("res://scenes/screens/game.tscn")

@rpc("any_peer", "call_remote", "reliable")
func game_loaded() -> void:
    if not multiplayer.is_server():
        return
    client_loaded = true
    client_ready.emit()
