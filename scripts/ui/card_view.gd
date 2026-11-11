extends PanelContainer

## Kartu di papan dan di Library (bab 4.1 / 7.2).
## UI hanya membaca data dan mengirim sinyal klik.
##
## Efek hover sengaja dipusatkan di sini supaya semua layar yang memakai kartu
## bereaksi sama: papan, tangan, dan grid Library. Di papan, hover juga
## memancarkan sinyal pratinjau (kartu besar di tengah layar) supaya tulisan
## yang kecil di kartu papan tetap terbaca; yang menggambar pratinjau adalah
## CardPreview di layar papan, bukan kartu ini.

signal clicked(uid: int)
signal preview_hover(data: Dictionary, source: Node)
signal preview_exit(source: Node)
signal preview_pin(data: Dictionary, source: Node)

const HOVER_BORDER := Color(0.462745, 0.827451, 0.6, 1)     # hijau aksen poin
const HOVER_BG := Color(0.219608, 0.278431, 0.360784, 1)    # dasar kartu lebih terang

var uid := -1
var interactive := false
var previewable := false        # boleh memicu pratinjau besar (hover / klik kanan)

var _style: StyleBoxFlat
var _base_border := Color.WHITE
var _base_bg := Color.BLACK
var _hovered := false
var _data := {}
var _play_tween: Tween            # denyut cincin "bisa dimainkan"

func _ready() -> void:
    var sb := get_theme_stylebox("panel")
    if sb is StyleBoxFlat:
        _style = (sb as StyleBoxFlat).duplicate()
        add_theme_stylebox_override("panel", _style)
        _base_border = _style.border_color
        _base_bg = _style.bg_color
    mouse_entered.connect(_set_hovered.bind(true))
    mouse_exited.connect(_set_hovered.bind(false))
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    # Setelah kartu lama dibuang dan diganti kartu baru (mis. tiap aksi), kursor
    # bisa berada tepat di atas kartu baru tanpa ada gerakan mouse. Tanpa
    # penyegaran ini, hover baru menyala setelah mouse digerakkan.
    resized.connect(refresh_hover)

## face_up = tampilkan isi; can_click = kartu boleh diklik (dan ikut bereaksi
## hover). can_preview = hover / klik kanan boleh membuka pratinjau besar.
## Kartu tertutup ("back") tidak pernah dipratinjau karena isinya rahasia.
func setup(card: Dictionary, face_up := true, can_click := true,
        can_preview := true) -> void:
    uid = int(card.get("uid", -1))
    interactive = can_click
    var id := String(card.get("id", ""))
    var show_face := face_up and id != "back" and CardDB.cards.has(id)
    previewable = can_preview and show_face
    _data = card.duplicate()
    mouse_filter = (
        MOUSE_FILTER_STOP if can_click or previewable else MOUSE_FILTER_IGNORE)
    mouse_default_cursor_shape = (
        CURSOR_POINTING_HAND if can_click else CURSOR_ARROW)
    tooltip_text = ""

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
    if not (e is InputEventMouseButton) or not e.pressed:
        return
    var mb := e as InputEventMouseButton
    if mb.button_index == MOUSE_BUTTON_LEFT and interactive:
        clicked.emit(uid)
        return
    if mb.button_index == MOUSE_BUTTON_RIGHT and previewable:
        preview_pin.emit(_data, self)
        accept_event()

func _on_mouse_entered() -> void:
    if previewable:
        preview_hover.emit(_data, self)

func _on_mouse_exited() -> void:
    if previewable:
        preview_exit.emit(self)

## Menyalakan/mematikan tampilan hover. Aman dipanggil kapan saja.
func refresh_hover() -> void:
    if not (interactive or previewable) or not is_inside_tree():
        return
    var on := get_global_rect().has_point(get_global_mouse_position())
    var changed := on != _hovered
    _set_hovered(on)
    # Kartu baru sudah berada di bawah kursor tanpa mouse bergerak: picu
    # pratinjau supaya isinya tetap terbaca setelah papan dirender ulang.
    if changed and on and previewable:
        preview_hover.emit(_data, self)

func _set_hovered(on: bool) -> void:
    if _style == null or on == _hovered:
        return
    _hovered = on
    _style.border_color = HOVER_BORDER if on else _base_border
    _style.bg_color = HOVER_BG if on else _base_bg
    queue_redraw()

## Menyesuaikan isi kartu dengan ukuran apa pun: dipakai papan (kartu kecil)
## maupun pratinjau besar. Ukuran font dibatasi agar deskripsi kartu besar
## tidak meluber ke luar kotak.
func fit(size: Vector2) -> void:
    custom_minimum_size = size
    clip_contents = true
    var name_label: Label = $V/Name
    var info: Label = $V/Info
    var desc: Label = $V/Desc
    var art: TextureRect = $V/Art
    name_label.add_theme_font_size_override("font_size", clampi(int(size.y * 0.085), 9, 28))
    info.add_theme_font_size_override("font_size", clampi(int(size.y * 0.07), 8, 20))
    desc.add_theme_font_size_override("font_size", clampi(int(size.y * 0.055), 8, 17))
    desc.visible = size.y >= 140
    art.custom_minimum_size = Vector2(0, int(size.y * 0.36))

## Menandai kartu ini sedang bisa dimainkan: cincin hijau yang berdenyut di
## dalam kartu. Dipakai papan untuk kartu dasar di tangan dan kartu dasar yang
## bisa disintesis. Kartu yang tidak bisa dimainkan dibiarkan normal.
func set_playable(on: bool) -> void:
    var glow: Control = get_node_or_null("Glow")
    if glow == null:
        return
    if _play_tween != null and _play_tween.is_valid():
        _play_tween.kill()
    _play_tween = null
    if not on:
        glow.visible = false
        glow.modulate.a = 0.0
        return
    glow.visible = true
    glow.modulate.a = 0.9
    _play_tween = create_tween().set_loops()
    _play_tween.tween_property(glow, "modulate:a", 0.3, 0.7).set_trans(Tween.TRANS_SINE)
    _play_tween.tween_property(glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
