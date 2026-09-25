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

@onready var _buttons: BoxContainer = %Buttons


func _ready() -> void:
	for room in ROOMS:
		var button := Button.new()
		button.text = ROOMS[room].name
		button.icon = ROOMS[room].preview
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(Rooms.go_to.bind(room))
		_buttons.add_child(button)
