extends Control

const ROOMS := {
	"thermes": {
		"name": "Thermes",
		"preview": preload("res://scenes/navigation/room_choice/previews/thermes.jpg"),
	},
	"gros_pilier": {
		"name": "Salle du gros pilier",
		"preview": preload("res://scenes/navigation/room_choice/previews/gros_pilier.jpg"),
	},
}

const MODE_FONT_SIZE := 34

@onready var _title: Label = %Title
@onready var _buttons: BoxContainer = %Buttons


func _ready() -> void:
	_show_modes()


func _show_modes() -> void:
	_clear()
	_title.text = "Choisissez un mode"
	_add_mode(AppMode.Mode.VR, "Réalité virtuelle",
			"Visiter les scans 3D, où que vous soyez.")
	_add_mode(AppMode.Mode.AR, "Réalité augmentée",
			"Sur le site : le scan se cale sur les vraies thermes grâce au QR code.")


func _add_mode(mode: AppMode.Mode, title: String, description: String) -> void:
	var button := Button.new()
	button.text = "%s\n\n%s" % [title, description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", MODE_FONT_SIZE)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_mode_chosen.bind(mode))
	_buttons.add_child(button)


func _on_mode_chosen(mode: AppMode.Mode) -> void:
	AppMode.mode = mode
	var rooms: Array = ROOMS.keys()
	if AppMode.is_ar():
		rooms = rooms.filter(func(room: String) -> bool: return room in Rooms.AR_ROOMS)
	if not Interactions.room_choice:
		Rooms.go_to(Rooms.DEFAULT_ROOM if Rooms.DEFAULT_ROOM in rooms else rooms[0])
	elif rooms.size() == 1:
		Rooms.go_to(rooms[0])
	else:
		_show_rooms(rooms)


func _show_rooms(rooms: Array) -> void:
	_clear()
	_title.text = "Choisissez une salle"
	for room: String in rooms:
		var button := Button.new()
		button.text = ROOMS[room].name
		button.icon = ROOMS[room].preview
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(Rooms.go_to.bind(room))
		_buttons.add_child(button)


func _clear() -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
