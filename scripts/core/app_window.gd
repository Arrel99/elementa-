extends Node

## Autoload GameWindow: memastikan jendela game selalu muat di layar.
##
## Kenapa perlu: papan dirancang pada kanvas 1920x1080. Pada layar kecil, atau
## Windows dengan skala tampilan 125% (desktop logis 1536x864), jendela
## 1920x1080 lebih besar daripada layar. Tepi kanan papan (HUD, Senyawa lawan)
## jadi berada di luar layar, sehingga kursor tidak bisa menjangkau tombol yang
## terlihat. Gejalanya: hover terasa "tidak pas" dengan tombol.
##
## Skrip ini hanya mengecilkan jendela bila memang tidak muat; ukuran yang sudah
## pas dibiarkan apa adanya. Skala viewport diurus oleh stretch "canvas_items",
## jadi posisi gambar dan posisi hover tetap sejalan.

const DESIGN := Vector2i(1920, 1080)
const MIN_SCALE := 0.5          # jendela tidak pernah lebih kecil dari ini
const MARGIN := 16              # sisa ruang di tepi layar
const TITLE_BAR := 40           # perkiraan title bar + border jendela Windows

func _ready() -> void:
    _fit_window()

func _fit_window() -> void:
    if DisplayServer.get_name() == "headless":
        return
    if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
        return

    var screen := DisplayServer.window_get_current_screen()
    if screen < 0 or screen >= DisplayServer.get_screen_count():
        screen = DisplayServer.get_primary_screen()
    var usable := DisplayServer.screen_get_usable_rect(screen)
    var win := DisplayServer.window_get_size()

    var avail := Vector2i(
        maxi(usable.size.x - MARGIN * 2, 320),
        maxi(usable.size.y - MARGIN - TITLE_BAR, 240)
    )
    if win.x <= usable.size.x and win.y + TITLE_BAR <= usable.size.y:
        return   # sudah muat (termasuk title bar), jangan diubah

    var factor := minf(float(avail.x) / DESIGN.x, float(avail.y) / DESIGN.y)
    factor = clampf(factor, MIN_SCALE, 1.0)
    var target := Vector2i(int(DESIGN.x * factor), int(DESIGN.y * factor))

    DisplayServer.window_set_size(target)
    var offset := Vector2i(target.x, target.y + TITLE_BAR)
    var pos := usable.position + (usable.size - offset) / 2
    DisplayServer.window_set_position(Vector2i(
        maxi(pos.x, usable.position.x),
        maxi(pos.y, usable.position.y)
    ))

    print("[GameWindow] layar %s, jendela %s -> %s (skala %.3f)" % [
        usable.size, win, target, factor])
