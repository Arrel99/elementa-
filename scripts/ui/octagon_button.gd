extends Control

## Tombol segi delapan ("END TURN") seperti pada referensi PTCG Live.
##
## Dibuat sebagai Control biasa, bukan Button, supaya bentuk oktagonnya bisa
## digambar sendiri tanpa bertabrakan dengan gambar bawaan theme Button.
## Perilakunya tetap seperti tombol: hover, tekan, dan sinyal `pressed`.

signal pressed

@export var text := "END TURN"
@export var font_size := 20
@export var fill := Color(0.93, 0.945, 0.96)
@export var fill_hover := Color(1, 1, 1)
@export var fill_press := Color(0.72, 0.77, 0.82)
@export var fill_disabled := Color(0.35, 0.4, 0.46)
@export var edge_color := Color(0.09, 0.13, 0.17)
@export var text_color := Color(0.06, 0.09, 0.13)

var _disabled := false
var _hover := false
var _down := false

var disabled: bool:
    get:
        return _disabled
    set(value):
        _disabled = value
        mouse_default_cursor_shape = (
            Control.CURSOR_ARROW if value else Control.CURSOR_POINTING_HAND)
        queue_redraw()

func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    mouse_entered.connect(func() -> void:
        _hover = true
        queue_redraw())
    mouse_exited.connect(func() -> void:
        _hover = false
        _down = false
        queue_redraw())

func _gui_input(e: InputEvent) -> void:
    if _disabled:
        return
    if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
        if e.pressed:
            _down = true
            queue_redraw()
        elif _down:
            _down = false
            queue_redraw()
            pressed.emit()

func _draw() -> void:
    if size.x <= 0.0 or size.y <= 0.0:
        return
    var cut := minf(size.x, size.y) * 0.30
    var pts := PackedVector2Array([
        Vector2(cut, 0.0), Vector2(size.x - cut, 0.0),
        Vector2(size.x, cut), Vector2(size.x, size.y - cut),
        Vector2(size.x - cut, size.y), Vector2(cut, size.y),
        Vector2(0.0, size.y - cut), Vector2(0.0, cut),
    ])
    var c := fill
    if _disabled:
        c = fill_disabled
    elif _down:
        c = fill_press
    elif _hover:
        c = fill_hover
    draw_colored_polygon(pts, c)
    var outline := pts.duplicate()
    outline.append(pts[0])
    draw_polyline(outline, edge_color, 2.0, true)

    var font := get_theme_default_font()
    if font == null:
        return
    var lines := text.split("\n")
    var line_h := font.get_height(font_size)
    var y := (size.y - line_h * lines.size()) * 0.5 + font.get_ascent(font_size)
    for line in lines:
        var w := font.get_string_size(
            line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        draw_string(font, Vector2((size.x - w) * 0.5, y), line,
            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
        y += line_h
