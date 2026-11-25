extends CanvasLayer

## Control panel for the point cloud demo: toggles each of [ScanPointCloud]'s
## animations and tunes their speed, strength and the point size, from the
## panel or the keyboard.
##
## Keys: the effect initials (R, O, D, S, G, E) toggle them, Space starts or
## stops the tour (one effect after the other), M swaps the cloud for the
## scanned meshes to check how they line up, and 0 turns everything off. The
## number keys 1 to 9 are left to the camera's views.

@export var cloud: ScanPointCloud

## Seconds each effect plays during the tour.
@export var tour_step := 6.0

const EFFECTS: Array[Dictionary] = [
	{"property": &"breathing", "key": KEY_R, "name": "Respiration",
			"hint": "le nuage gonfle et se rétracte"},
	{"property": &"wave", "key": KEY_O, "name": "Onde",
			"hint": "une vague verticale court le long du site"},
	{"property": &"dispersion", "key": KEY_D, "name": "Dispersion",
			"hint": "chaque point s'éloigne et revient à son rythme"},
	{"property": &"spiral", "key": KEY_S, "name": "Spirale",
			"hint": "les points tournent autour de l'axe vertical"},
	{"property": &"glitch", "key": KEY_G, "name": "Glitch",
			"hint": "quelques points sautent de côté"},
	{"property": &"erosion", "key": KEY_E, "name": "Érosion",
			"hint": "des bandes de points disparaissent en balayant le site"},
]

var _toggles: Array[CheckButton] = []
var _tour_button: Button
var _status: Label
var _touring := false
var _tour_index := -1
var _tour_time := 0.0
var _showing_meshes := false


func _ready() -> void:
	_build_panel()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	for i in EFFECTS.size():
		if key.keycode == EFFECTS[i].key:
			_stop_tour()
			_set_effect(i, not cloud.get(EFFECTS[i].property))
			get_viewport().set_input_as_handled()
			return
	match key.keycode:
		KEY_SPACE:
			_toggle_tour()
		KEY_M:
			_toggle_meshes()
		KEY_0:
			_stop_tour()
			_all_off()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _touring:
		return
	_tour_time -= delta
	if _tour_time <= 0.0:
		_tour_index = (_tour_index + 1) % EFFECTS.size()
		_tour_time = tour_step
		_all_off()
		_set_effect(_tour_index, true)


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	# Fixed width, so the panel doesn't jump as the status text changes.
	panel.custom_minimum_size.x = 330.0
	panel.offset_left = -346.0
	panel.offset_top = 16.0
	panel.offset_right = -16.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Nuage de points des thermes"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	for i in EFFECTS.size():
		var toggle := CheckButton.new()
		toggle.text = "%s  (%s)" % [EFFECTS[i].name, OS.get_keycode_string(EFFECTS[i].key)]
		toggle.tooltip_text = EFFECTS[i].hint
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.toggled.connect(func(on: bool) -> void:
			_stop_tour()
			_set_effect(i, on))
		box.add_child(toggle)
		_toggles.append(toggle)

	box.add_child(HSeparator.new())
	_add_slider(box, "Vitesse", &"animation_speed", 0.0, 5.0, 0.1, "%.1f×")
	_add_slider(box, "Intensité", &"animation_strength", 0.0, 5.0, 0.1, "%.1f×")
	_add_slider(box, "Taille des points", &"point_size", 0.002, 0.1, 0.001, "%.3f m")
	box.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_tour_button = Button.new()
	_tour_button.focus_mode = Control.FOCUS_NONE
	_tour_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tour_button.pressed.connect(_toggle_tour)
	buttons.add_child(_tour_button)
	var off := Button.new()
	off.text = "Tout couper (0)"
	off.focus_mode = Control.FOCUS_NONE
	off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off.pressed.connect(func() -> void:
		_stop_tour()
		_all_off())
	buttons.add_child(off)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 260.0
	box.add_child(_status)


func _add_slider(box: VBoxContainer, label_text: String, property: StringName,
		min_value: float, max_value: float, step: float, format: String) -> void:
	var label := Label.new()
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = cloud.get(property)
	slider.focus_mode = Control.FOCUS_NONE
	var show_value := func(value: float) -> void:
		label.text = "%s : %s" % [label_text, format % value]
	slider.value_changed.connect(func(value: float) -> void:
		cloud.set(property, value)
		show_value.call(value))
	show_value.call(slider.value)
	box.add_child(slider)


func _set_effect(index: int, on: bool) -> void:
	cloud.set(EFFECTS[index].property, on)
	_refresh()


func _all_off() -> void:
	for effect in EFFECTS:
		cloud.set(effect.property, false)
	_refresh()


func _toggle_tour() -> void:
	if _touring:
		_stop_tour()
		_all_off()
	else:
		_touring = true
		_tour_index = -1
		_tour_time = 0.0
		_refresh()


func _stop_tour() -> void:
	if _touring:
		_touring = false
		_refresh()


## Swaps the cloud for the scanned meshes, as ScanPointCloud does in AR. Its
## _process only acts when HandDissolve's mask mode changes, so this sticks.
func _toggle_meshes() -> void:
	_showing_meshes = not _showing_meshes
	cloud.get_node("Cloud").visible = not _showing_meshes
	var scan := cloud.scan if cloud.scan else cloud.get_parent()
	for mesh_instance: MeshInstance3D in scan.find_children("*", "MeshInstance3D", true, true):
		mesh_instance.visible = _showing_meshes
	_refresh()


func _refresh() -> void:
	if not _status:
		return
	var active := PackedStringArray()
	for i in EFFECTS.size():
		var on: bool = cloud.get(EFFECTS[i].property)
		_toggles[i].set_pressed_no_signal(on)
		if on:
			active.append(EFFECTS[i].name)
	_tour_button.text = "Arrêter la visite" if _touring else "Visite auto (Espace)"
	var lines := PackedStringArray()
	if _showing_meshes:
		lines.append("Affichage : maillage du scan (M pour revenir au nuage)")
	if _touring and _tour_index >= 0:
		var effect := EFFECTS[_tour_index]
		lines.append("Visite %d/%d : %s, %s" % [_tour_index + 1, EFFECTS.size(), effect.name, effect.hint])
	elif active.is_empty():
		lines.append("Aucun effet : le nuage tel que scanné.")
	else:
		lines.append("Actifs : " + ", ".join(active))
	_status.text = "\n".join(lines)
