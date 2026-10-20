extends Node

## Autoload Net (bab 6.1 dan 6.4). Host-authoritative ENet.
## Semua sinyal siap dipindahkan ke autoload ini supaya selalu bisa
## dijangkau sebelum scene game dimuat.

const PORT := 24567
const GAME_VERSION := "0.2.0"

signal opponent_joined
signal opponent_left
signal client_ready
signal version_rejected(msg: String)

var client_loaded := false
var local_test := false

func host() -> Error:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(PORT, 1)   # maksimal 1 klien
    if err == OK:
        multiplayer.multiplayer_peer = peer
        multiplayer.peer_connected.connect(func(_id): opponent_joined.emit())
        multiplayer.peer_disconnected.connect(func(_id): opponent_left.emit())
    return err

func join(ip: String) -> Error:
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(ip, PORT)
    if err == OK:
        multiplayer.multiplayer_peer = peer
    return err

func reset() -> void:
    client_loaded = false
    local_test = false

func send_hello() -> void:
    hello.rpc_id(1, GAME_VERSION, CardDB.cards_hash())

@rpc("any_peer", "call_remote", "reliable")
func hello(version: String, cards_hash: int) -> void:
    if not multiplayer.is_server():
        return
    var id := multiplayer.get_remote_sender_id()
    if version != GAME_VERSION or cards_hash != CardDB.cards_hash():
        rejected.rpc_id(id, "Versi game berbeda. Perbarui game kamu.")
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
