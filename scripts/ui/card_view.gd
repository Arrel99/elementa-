extends PanelContainer

## Kartu di papan dan di Library (bab 4.1 / 7.2).
## UI hanya membaca data dan mengirim sinyal klik.
##
## Efek hover sengaja dipusatkan di sini supaya semua layar yang memakai kartu
## bereaksi sama: papan, tangan, dan grid Library. Hover hanya mengubah warna
## gaya (bukan ukuran) karena kotak kartu memakai clip_contents, sehingga
## animasi skala akan terpotong oleh zona di sekelilingnya.

signal clicked(uid: int)

const HOVER_BORDER := Color(0.462745, 0.827451, 0.6, 1)     # hijau aksen poin
const HOVER_BG := Color(0.219608, 0.278431, 0.360784, 1)    # dasar kartu lebih terang

var uid := -1
var interactive := false

var _style: StyleBoxFlat
var _base_border := Color.WHITE
var _base_bg := Color.BLACK
var _hovered := false

func _ready() -> void:
    var sb := get_theme_stylebox("panel")
    if sb is StyleBoxFlat:
        _style = (sb as StyleBoxFlat).duplicate()
        add_theme_stylebox_override("panel", _style)
        _base_border = _style.border_color
        _base_bg = _style.bg_color
    mouse_entered.connect(_set_hovered.bind(true))
    mouse_exited.connect(_set_hovered.bind(false))
    # Setelah kartu lama dibuang dan diganti kartu baru (mis. tiap aksi), kursor
    # bisa berada tepat di atas kartu baru tanpa ada gerakan mouse. Tanpa
    # penyegaran ini, hover baru menyala setelah mouse digerakkan.
    resized.connect(refresh_hover)

## face_up = tampilkan isi; can_click = kartu boleh diklik (dan ikut bereaksi hover).
func setup(card: Dictionary, face_up := true, can_click := true) -> void:
    uid = int(card.get("uid", -1))
    interactive = can_click
    mouse_filter = MOUSE_FILTER_STOP if can_click else MOUSE_FILTER_IGNORE
    mouse_default_cursor_shape = (
        CURSOR_POINTING_HAND if can_click else CURSOR_ARROW)
    tooltip_text = ""

    var id := String(card.get("id", ""))
    var show_face := face_up and id != "back" and CardDB.cards.has(id)
    if not show_face:
        $V/Name.text = "?" if id == "back" else id
        $V/Info.text = ""
        $V/Desc.text = ""
        $V/Art.texture = null
        refresh_hover()
        return
    var data: CardData = CardDB.get_card(id)
    $V/Name.text = data.display_name
    $V/Info.text = "%s  (%d poin)" % [data.symbol, data.points]
    $V/Desc.text = data.description
    $V/Art.texture = data.art
    # Keterangan panjang bisa terpotong di kartu kecil; tooltip menutup celah itu.
    tooltip_text = "%s — %s" % [data.display_name, data.description]
    refresh_hover()

func _gui_input(e: InputEvent) -> void:
    if not interactive:
        return
    if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
        clicked.emit(uid)

## Menyalakan/mematikan tampilan hover. Aman dipanggil kapan saja.
func refresh_hover() -> void:
    if not interactive or not is_inside_tree():
        return
    _set_hovered(get_global_rect().has_point(get_global_mouse_position()))

func _set_hovered(on: bool) -> void:
    if _style == null or on == _hovered:
        return
    _hovered = on
    _style.border_color = HOVER_BORDER if on else _base_border
    _style.bg_color = HOVER_BG if on else _base_bg
    queue_redraw()
