extends Control

## Alat sementara: mengukur selisih antara posisi kursor yang DIANGGAP Godot
## dengan posisi kursor yang sebenarnya di layar.
##
## Cara pakai:
##   1. Jalankan scene ini (dari editor: buka scenes/tools/mouse_offset.tscn,
##      tekan F6; atau lewat terminal).
##   2. Gerakkan kursor ke tengah layar.
##   3. Garis silang merah digambar di posisi yang dianggap Godot.
##      Kalau garis silang TIDAK tepat di bawah panah kursor, itu bugnya.
##      Perhatikan arah dan perkiraan jaraknya (dalam piksel).
##   4. Konsol juga mencetak angka mentahnya -- kirimkan beberapa baris terakhir.
##
## Jalankan: godot --path . res://scenes/tools/mouse_offset.tscn

var _t := 0.0

func _ready() -> void:
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_IGNORE
    print("[offset] jendela %s  posisi %s  skala jendela %.4f" % [
        DisplayServer.window_get_size(),
        DisplayServer.window_get_position(),
        DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())])
    print("[offset] jumlah layar %d  primary %d  current %d" % [
        DisplayServer.get_screen_count(),
        DisplayServer.get_primary_screen(),
        DisplayServer.window_get_current_screen()])
    for i in DisplayServer.get_screen_count():
        print("[offset]   layar %d: ukuran %s  usable %s  skala %.4f  dpi %.1f" % [
            i, DisplayServer.screen_get_size(i), DisplayServer.screen_get_usable_rect(i),
            DisplayServer.screen_get_scale(i), DisplayServer.screen_get_dpi(i)])

func _process(delta: float) -> void:
    _t += delta
    queue_redraw()
    if _t < 0.4:
        return
    _t = 0.0
    var screen_mouse := Vector2(DisplayServer.mouse_get_position())
    var win_pos := Vector2(DisplayServer.window_get_position())
    var logical := get_viewport().get_mouse_position()
    var window_rel := screen_mouse - win_pos
    print("[offset] kursor layar %s  posisi jendela %s  relatif %s  logis Godot %s" % [
        screen_mouse, win_pos, window_rel, logical])

func _draw() -> void:
    var m := get_viewport().get_mouse_position()
    var col := Color(1, 0.25, 0.25, 1)
    draw_line(m - Vector2(30, 0), m + Vector2(30, 0), col, 2.0)
    draw_line(m - Vector2(0, 30), m + Vector2(0, 30), col, 2.0)
    draw_circle(m, 4.0, col)
    draw_arc(m, 16.0, 0.0, TAU, 32, col, 2.0)
