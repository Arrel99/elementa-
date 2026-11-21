extends Node

## Autoload GameWindow: memastikan jendela game muat di layar.
##
## Kenapa perlu: papan dirancang pada kanvas 1920x1080. Pada layar kecil, atau
## Windows dengan skala tampilan 125%, jendela 1920x1080 lebih besar daripada
## layar, sehingga tepi kanan papan (HUD) berada di luar layar.
##
## PENTING -- kenapa skrip ini TIDAK lagi mengubah ukuran atau memindahkan
## jendela sendiri:
##
##   Godot menghitung posisi kursor sebagai "posisi kursor di layar" dikurangi
##   "posisi jendela", lalu dibagi skala stretch. Kalau ukuran/posisi jendela
##   diubah dari kode, asumsi Godot tentang jendela bisa berbeda dari jendela
##   yang sebenarnya digambar Windows. Akibatnya hover terasa bergeser --
##   kursor harus sedikit ke bawah agar tombol di atasnya tersorot.
##
##   Karena itu ukuran awal jendela diatur lewat project.godot
##   (window/size/window_width_override + window_height_override, 1600x900) dan
##   dipusatkan oleh Windows (initial_position_type = 1). Kalau layarnya tetap
##   tidak muat, jendela dimaksimalkan -- dan memaksimalkan jendela diurus
##   sepenuhnya oleh Windows, jadi tidak ada hitungan posisi manual.

## Batas bawah ukuran jendela. Papan sudah responsif (lihat game.gd::_layout),
## tetapi di bawah ukuran ini teks HUD dan kartu menjadi tidak terbaca.
const MIN_WINDOW := Vector2i(960, 600)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(MIN_WINDOW)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if is_fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
