extends Node

## Autoload Lan: menemukan room di WiFi yang sama tanpa mengetik IP.
##
## Alur:
##  * Host menekan "Buat Room" -> `Net.host(code)` lalu `Lan.start_room(code)`.
##    Socket UDP 24568 menjawab setiap permintaan "DISCOVER" dengan kode room.
##  * Tamu membuka lobby -> `start_scan()` menyiarkan "DISCOVER" tiap detik.
##    IP host diambil dari paket jawaban itu sendiri, jadi pemain tidak pernah
##    melihat atau mengetik IP.
##
## Batasan: kode room hanya berlaku di jaringan lokal (WiFi/hotspot yang sama).
## Untuk beda jaringan diperlukan relay internet, yang belum ada.

signal rooms_changed

const MAGIC := "ELEMENTA"
const DISCOVER_PORT := 24568
const SCAN_INTERVAL := 1.0     # detik antar siaran DISCOVER
const ROOM_TTL := 5.0          # room hilang dari daftar bila 5 detik senyap

var rooms: Array = []          # [{code, ip, port, name, seen}]

var _scan := PacketPeerUDP.new()    # socket tamu (port acak)
var _serve := PacketPeerUDP.new()   # socket host (24568)
var _scanning := false
var _serving := false
var _code := ""
var _timer := 0.0

# --- Dipanggil lobby ---------------------------------------------------------

## Mulai mencari room. Aman dipanggil berulang.
func start_scan() -> void:
    if _scanning:
        return
    if _scan.bind(0) != OK:
        push_warning("[Lan] gagal membuka socket pencarian")
        return
    _scan.set_broadcast_enabled(true)
    _scanning = true
    _timer = 0.0
    _send_discover()

func stop_scan() -> void:
    if not _scanning:
        return
    _scanning = false
    if _scan.is_bound():
        _scan.close()
    if not rooms.is_empty():
        rooms.clear()
        rooms_changed.emit()

## Bersihkan daftar lalu siarkan lagi segera (tombol "Cari ulang").
func rescan() -> void:
    if not _scanning:
        start_scan()
        return
    if not rooms.is_empty():
        rooms.clear()
        rooms_changed.emit()
    _timer = 0.0
    _send_discover()

## Jadikan node ini host discovery. `false` = port 24568 dipakai proses lain,
## room tetap bisa dimainkan lewat koneksi manual (IP).
func start_room(code: String) -> bool:
    stop_room()
    if _serve.bind(DISCOVER_PORT) != OK:
        return false
    _serve.set_broadcast_enabled(true)
    _code = code
    _serving = true
    return true

func stop_room() -> void:
    _serving = false
    _code = ""
    if _serve.is_bound():
        _serve.close()

## Cari room berdasarkan kode. Kosong bila belum ditemukan.
func find_room(code: String) -> Dictionary:
    code = code.strip_edges()
    for r in rooms:
        if String(r["code"]) == code:
            return r
    return {}

# --- Jaringan ---------------------------------------------------------------

func _process(delta: float) -> void:
    if _serving:
        _drain_serve()
    if not _scanning:
        return
    _timer -= delta
    if _timer <= 0.0:
        _timer = SCAN_INTERVAL
        _send_discover()
    _drain_scan()
    _prune()

func _send_discover() -> void:
    var pkt := (MAGIC + "|DISCOVER").to_utf8_buffer()
    for target in _broadcast_targets():
        if _scan.set_dest_address(target, DISCOVER_PORT) != OK:
            continue
        _scan.put_packet(pkt)

## Broadcast umum + broadcast per subnet (/24). Dua-duanya dikirim karena
## Windows kadang hanya meneruskan salah satunya.
func _broadcast_targets() -> PackedStringArray:
    var out := PackedStringArray(["255.255.255.255"])
    for ip in IP.get_local_addresses():
        if ip.contains(":"):
            continue                     # IPv6 dilewati
        if ip.begins_with("127.") or ip.begins_with("169.254."):
            continue
        var parts := ip.split(".")
        if parts.size() != 4:
            continue
        var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
        if not out.has(b):
            out.append(b)
    return out

func _drain_scan() -> void:
    while _scan.get_available_packet_count() > 0:
        var raw := _scan.get_packet().get_string_from_utf8()
        var ip := _scan.get_packet_ip()
        var f := raw.split("|")
        if f.size() < 4 or f[0] != MAGIC or f[1] != "ROOM":
            continue
        var name := f[4] if f.size() > 4 else "Host"
        _upsert(String(f[2]), ip, int(f[3]), name)

func _drain_serve() -> void:
    while _serve.get_available_packet_count() > 0:
        var raw := _serve.get_packet().get_string_from_utf8()
        var ip := _serve.get_packet_ip()
        var port := _serve.get_packet_port()
        if raw != MAGIC + "|DISCOVER":
            continue
        _serve.set_dest_address(ip, port)
        var reply := "%s|ROOM|%s|%d|%s" % [MAGIC, _code, Net.PORT, _local_name()]
        _serve.put_packet(reply.to_utf8_buffer())

# --- Daftar room ------------------------------------------------------------

func _upsert(code: String, ip: String, port: int, name: String) -> void:
    if code.is_empty():
        return
    var now := Time.get_ticks_msec() / 1000.0
    for r in rooms:
        if String(r["code"]) == code:
            var changed := String(r["ip"]) != ip or int(r["port"]) != port or String(r["name"]) != name
            r["ip"] = ip
            r["port"] = port
            r["name"] = name
            r["seen"] = now
            if changed:
                rooms_changed.emit()
            return
    rooms.append({"code": code, "ip": ip, "port": port, "name": name, "seen": now})
    rooms_changed.emit()

func _prune() -> void:
    var now := Time.get_ticks_msec() / 1000.0
    var alive: Array = []
    for r in rooms:
        if now - float(r["seen"]) <= ROOM_TTL:
            alive.append(r)
    if alive.size() != rooms.size():
        rooms = alive
        rooms_changed.emit()

func _local_name() -> String:
    var n := OS.get_environment("COMPUTERNAME")
    if n.is_empty():
        n = OS.get_environment("USER")
    if n.is_empty():
        n = "Host"
    return n.substr(0, 18)
