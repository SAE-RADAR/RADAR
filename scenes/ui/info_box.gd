@tool
class_name InfoBox
extends Node3D

## Information point: an icon that opens into a panel about a place when the
## player looks at it, and closes back into the icon when they look away.
##
## The panel shows a title, subtitle, a picture, a description, a list of key
## facts and a source line, all read from an [InfoBoxData] resource so the same
## box can present any place. It sizes itself to its content, is centered on
## this node where the icon sits, and turns to face the player.
##
## Looking is detected with [member gaze_ray], a ray from the player's head:
## the icon and the open panel each carry an area on [member gaze_layer] for it
## to hit.

## Depth offset keeping the text in front of the background.
const TEXT_OFFSET := 0.002

## Scale of the panel while closed. Not zero, so its gaze area stays valid.
const CLOSED_SCALE := Vector3(0.01, 0.01, 0.01)

## Thickness of the gaze area over the open panel.
const PANEL_GAZE_DEPTH := 0.05

@export var data: InfoBoxData:
	set(value):
		if data and data.changed.is_connected(_queue_layout):
			data.changed.disconnect(_queue_layout)
		data = value
		if data:
			data.changed.connect(_queue_layout)
		_queue_layout()

@export_group("Layout")
## Panel width, in meters. The height follows the content.
@export_range(0.2, 4.0, 0.01, "suffix:m") var width := 0.9:
	set(value):
		width = value
		_queue_layout()

## Space between the panel edge and its content.
@export_range(0.0, 0.5, 0.005, "suffix:m") var padding := 0.05:
	set(value):
		padding = value
		_queue_layout()

## Space between blocks of content.
@export_range(0.0, 0.2, 0.005, "suffix:m") var spacing := 0.025:
	set(value):
		spacing = value
		_queue_layout()

## Share of the content width used by the fact labels; values take the rest.
@export_range(0.1, 0.9, 0.01) var fact_label_ratio := 0.35:
	set(value):
		fact_label_ratio = value
		_queue_layout()

## Height of the picture, reduced if needed to fit the width.
@export_range(0.0, 2.0, 0.01, "suffix:m") var image_height := 0.3:
	set(value):
		image_height = value
		_queue_layout()

## Size of one font pixel, in meters. Font sizes are rendering resolutions;
## this sets how big the text looks.
@export_range(0.0001, 0.005, 0.00001, "suffix:m") var pixel_size := 0.00035:
	set(value):
		pixel_size = value
		_queue_layout()

@export_group("Text")
## Font for all text; the default font when empty.
@export var font: Font:
	set(value):
		font = value
		_queue_layout()

@export var title_size := 96:
	set(value):
		title_size = value
		_queue_layout()

@export var subtitle_size := 56:
	set(value):
		subtitle_size = value
		_queue_layout()

@export var body_size := 48:
	set(value):
		body_size = value
		_queue_layout()

@export var source_size := 36:
	set(value):
		source_size = value
		_queue_layout()

@export_group("Colors")
@export var background_color := Color(0.02, 0.03, 0.07, 0.85):
	set(value):
		background_color = value
		_queue_layout()

## Divider under the header and subtitle text.
@export var accent_color := Color(0.12, 1.0, 0.42):
	set(value):
		accent_color = value
		_queue_layout()

@export var text_color := Color(0.93, 0.95, 1.0):
	set(value):
		text_color = value
		_queue_layout()

## Fact labels and source line.
@export var muted_color := Color(0.6, 0.66, 0.8):
	set(value):
		muted_color = value
		_queue_layout()

@export_group("Icon")
## Shown in place of the panel until the player looks at it.
@export var icon: Texture2D = preload("res://assets/thermes/texture/Information.webp"):
	set(value):
		icon = value
		_queue_layout()

## Icon height, in meters.
@export_range(0.05, 2.0, 0.01, "suffix:m") var icon_size := 0.35:
	set(value):
		icon_size = value
		_queue_layout()

@export_group("Gaze")
## Ray from the player's head, e.g. a RayCast3D under the XRCamera3D. It must
## collide with areas and its mask must include [member gaze_layer].
@export var gaze_ray: RayCast3D

## Physics layer of the areas the gaze ray looks for.
@export_flags_3d_physics var gaze_layer := 2:
	set(value):
		gaze_layer = value
		_queue_layout()

## Radius around the icon that counts as looking at it.
@export_range(0.05, 3.0, 0.01, "suffix:m") var gaze_radius := 0.5:
	set(value):
		gaze_radius = value
		_queue_layout()

## Seconds the player can look away before the panel closes, so a glance off
## its edge doesn't close it.
@export_range(0.0, 3.0, 0.05, "suffix:s") var close_delay := 0.3

@export_group("Animation")
## Seconds for the panel to pop open, and to shrink back into the icon.
@export_range(0.0, 2.0, 0.05, "suffix:s") var open_time := 0.3
@export_range(0.0, 2.0, 0.05, "suffix:s") var close_time := 0.2

## Turns the panel around its vertical axis to face the player.
@export var face_player := true

## How quickly the panel turns toward the player, per second.
@export var turn_speed := 4.0

## In the editor, shows the panel open instead of the icon.
@export var preview_open := true:
	set(value):
		preview_open = value
		if Engine.is_editor_hint() and is_node_ready():
			_set_open_now(preview_open)

var _icon: Sprite3D
var _icon_area: Area3D
var _icon_shape: SphereShape3D
# Turns to face the player.
var _panel: Node3D
# Scales to open and close, around the panel's center.
var _pop: Node3D
# Holds the content, laid out from its top edge.
var _content: Node3D
var _panel_area: Area3D
var _panel_shape: BoxShape3D
var _background: MeshInstance3D
var _divider: MeshInstance3D
var _title: Label3D
var _subtitle: Label3D
var _image: Sprite3D
var _description: Label3D
var _source: Label3D
var _fact_labels: Array[Label3D] = []
var _layout_queued := false
var _open := false
var _look_away_time := 0.0
var _tween: Tween


func _ready() -> void:
	_build()
	_layout()
	if Engine.is_editor_hint():
		_set_open_now(preview_open)
		return
	_set_open_now(false)
	if not gaze_ray:
		push_warning("InfoBox %s has no gaze ray, it will never open." % get_path())


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _is_looked_at():
		_look_away_time = 0.0
		show_info()
	elif _open:
		_look_away_time += delta
		if _look_away_time >= close_delay:
			hide_info()

	var camera := get_viewport().get_camera_3d()
	if face_player and camera and _panel.visible:
		_face(camera.global_position, 1.0 - exp(-turn_speed * delta))


## Pops the panel open in place of the icon.
func show_info() -> void:
	if _open:
		return
	_open = true
	_look_away_time = 0.0
	_icon.visible = false
	_panel.visible = true
	# Open already facing the player rather than swinging round.
	var camera := get_viewport().get_camera_3d()
	if face_player and camera:
		_face(camera.global_position, 1.0)

	var tween := _restart_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(_pop, "scale", Vector3.ONE, open_time)


## Shrinks the panel away and brings the icon back.
func hide_info() -> void:
	if not _open:
		return
	_open = false
	_icon.visible = true

	var tween := _restart_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(_pop, "scale", CLOSED_SCALE, close_time)
	tween.tween_callback(_panel.hide)


func _is_looked_at() -> bool:
	if not gaze_ray or not gaze_ray.is_colliding():
		return false
	var hit := gaze_ray.get_collider()
	return hit == _icon_area or hit == _panel_area


func _restart_tween() -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK)
	return _tween


func _set_open_now(open: bool) -> void:
	if _tween:
		_tween.kill()
	_open = open
	_icon.visible = not open
	_panel.visible = open
	_pop.scale = Vector3.ONE if open else CLOSED_SCALE


## Turns the panel toward [param target_position] by [param weight] (1 turns
## all the way).
func _face(target_position: Vector3, weight: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	# The text faces +Z, so point -Z away from the player.
	var goal := Basis.looking_at(-to_target.normalized()).get_rotation_quaternion()
	var current := _panel.global_basis.get_rotation_quaternion()
	_panel.global_basis = Basis(current.slerp(goal, weight)).scaled(global_basis.get_scale())


func _build() -> void:
	# Internal children are regenerated on load, never saved with the scene.
	_icon = Sprite3D.new()
	_icon.name = "Icon"
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_icon, false, INTERNAL_MODE_BACK)

	_icon_shape = SphereShape3D.new()
	_icon_area = _make_gaze_area(_icon_shape, self)

	_panel = Node3D.new()
	_panel.name = "Panel"
	add_child(_panel, false, INTERNAL_MODE_BACK)

	_pop = Node3D.new()
	_pop.name = "Pop"
	_panel.add_child(_pop)

	_content = Node3D.new()
	_content.name = "Content"
	_pop.add_child(_content)

	_panel_shape = BoxShape3D.new()
	_panel_area = _make_gaze_area(_panel_shape, _pop)

	_background = _make_quad(0)
	_divider = _make_quad(1)
	_title = _make_label()
	_subtitle = _make_label()
	_description = _make_label()
	_source = _make_label()

	_image = Sprite3D.new()
	_image.render_priority = 1
	_image.double_sided = false
	_content.add_child(_image)


func _queue_layout() -> void:
	if _layout_queued or not is_node_ready():
		return
	_layout_queued = true
	_layout.call_deferred()


## Places every block from the top of the panel down, then sizes the
## background and gaze area to fit and centers the panel on this node.
func _layout() -> void:
	_layout_queued = false
	if not _content:
		return

	_icon.texture = icon
	if icon:
		_icon.pixel_size = icon_size / maxf(icon.get_height(), 1.0)
	_icon_shape.radius = gaze_radius
	_icon_area.collision_layer = gaze_layer
	_panel_area.collision_layer = gaze_layer

	for label in _fact_labels:
		_content.remove_child(label)
		label.queue_free()
	_fact_labels.clear()

	var info := data if data else InfoBoxData.new()
	var content_width := maxf(width - padding * 2.0, 0.01)
	var left := -width / 2.0 + padding
	var y := -padding

	y = _place_label(_title, info.title, title_size, text_color, left, y, content_width)
	y = _place_label(_subtitle, info.subtitle, subtitle_size, accent_color, left, y, content_width)

	var has_header := not info.title.is_empty() or not info.subtitle.is_empty()
	var has_body := info.image or not info.description.is_empty() or not info.facts.is_empty()
	_divider.visible = has_header and has_body
	if _divider.visible:
		var thickness := 0.004
		(_divider.mesh as QuadMesh).size = Vector2(content_width, thickness)
		(_divider.material_override as StandardMaterial3D).albedo_color = accent_color
		_divider.position = Vector3(0.0, y - thickness / 2.0, TEXT_OFFSET)
		y -= thickness + spacing

	_image.visible = info.image != null and image_height > 0.0
	if _image.visible:
		var texture_size := info.image.get_size()
		var aspect := texture_size.x / maxf(texture_size.y, 1.0)
		var image_size := Vector2(image_height * aspect, image_height)
		if image_size.x > content_width:
			image_size = Vector2(content_width, content_width / aspect)
		_image.texture = info.image
		_image.pixel_size = image_size.y / maxf(texture_size.y, 1.0)
		_image.position = Vector3(0.0, y - image_size.y / 2.0, TEXT_OFFSET)
		y -= image_size.y + spacing

	y = _place_label(_description, info.description, body_size, text_color, left, y, content_width)

	if not info.facts.is_empty():
		var label_width := content_width * fact_label_ratio
		var value_width := content_width - label_width - spacing
		for key: String in info.facts:
			var key_label := _make_label()
			var value_label := _make_label()
			_fact_labels.append(key_label)
			_fact_labels.append(value_label)
			var key_bottom := _place_label(key_label, key, body_size, muted_color, left, y, label_width)
			var value_bottom := _place_label(value_label, info.facts[key], body_size, text_color, left + label_width + spacing, y, value_width)
			# Rows sit closer together than blocks.
			y = minf(key_bottom, value_bottom) + spacing / 2.0
		y -= spacing / 2.0

	y = _place_label(_source, info.source, source_size, muted_color, left, y, content_width)

	# The last block added spacing below itself; the padding replaces it.
	var height := -y - spacing + padding
	(_background.mesh as QuadMesh).size = Vector2(width, height)
	(_background.material_override as StandardMaterial3D).albedo_color = background_color
	_background.position = Vector3(0.0, -height / 2.0, 0.0)
	_content.position = Vector3(0.0, height / 2.0, 0.0)
	_panel_shape.size = Vector3(width, height, PANEL_GAZE_DEPTH)


## Shows [param text] in [param label] with its top-left corner at
## ([param x], [param y]). Returns the top of the next block.
func _place_label(label: Label3D, text: String, font_size: int, color: Color, x: float, y: float, max_width: float) -> float:
	label.visible = not text.is_empty()
	if not label.visible:
		return y
	label.text = text
	label.font = font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.width = max_width / pixel_size
	label.modulate = color
	label.position = Vector3(x, y, TEXT_OFFSET)
	return y - _label_height(label) - spacing


func _label_height(label: Label3D) -> float:
	var label_font := label.font if label.font else ThemeDB.fallback_font
	var size := label_font.get_multiline_string_size(
			label.text, label.horizontal_alignment, label.width, label.font_size, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	return size.y * label.pixel_size


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.outline_size = 0
	label.double_sided = false
	label.render_priority = 1
	label.visible = false
	_content.add_child(label)
	return label


func _make_quad(priority: int) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority

	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(quad)
	return quad


## Area the gaze ray hits; it only needs to be found, not to detect anything.
func _make_gaze_area(shape: Shape3D, parent: Node) -> Area3D:
	var area := Area3D.new()
	area.name = "GazeArea"
	area.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	if parent == self:
		add_child(area, false, INTERNAL_MODE_BACK)
	else:
		parent.add_child(area)
	return area
