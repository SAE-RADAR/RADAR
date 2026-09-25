@tool
class_name InfoBox
extends Node3D

## Floating panel showing information about a place: title, subtitle, a
## picture, a description, a list of key facts and a source line.
##
## The text comes from an [InfoBoxData] resource, so the same box can present
## any place. The panel is centered on this node, sizes itself to its content,
## and can turn to face the player and fade in only when they come close.

## Depth offset keeping the text in front of the background.
const TEXT_OFFSET := 0.002

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

@export_group("Behavior")
## Turns the panel around its vertical axis to face the player.
@export var face_player := true

## How quickly the panel turns toward the player, per second.
@export var turn_speed := 4.0

## Distance from the player within which the panel shows; 0 always shows it.
@export_range(0.0, 50.0, 0.1, "suffix:m") var show_distance := 0.0

## Seconds to fade in or out.
@export var fade_time := 0.4

var _panel: Node3D
var _content: Node3D
var _background: MeshInstance3D
var _divider: MeshInstance3D
var _title: Label3D
var _subtitle: Label3D
var _image: Sprite3D
var _description: Label3D
var _source: Label3D
var _fact_labels: Array[Label3D] = []
var _layout_queued := false
var _opacity := 1.0


func _ready() -> void:
	_build()
	_layout()
	if not Engine.is_editor_hint() and show_distance > 0.0:
		_opacity = 0.0
		_apply_opacity()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	if face_player:
		_turn_toward(camera.global_position, delta)

	var shown := show_distance <= 0.0 or global_position.distance_to(camera.global_position) <= show_distance
	var target := 1.0 if shown else 0.0
	if _opacity != target:
		_opacity = move_toward(_opacity, target, delta / maxf(fade_time, 0.001))
		_apply_opacity()


func _turn_toward(target_position: Vector3, delta: float) -> void:
	var to_target := target_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	# The text faces +Z, so point -Z away from the player.
	var goal := Basis.looking_at(-to_target.normalized()).get_rotation_quaternion()
	var current := _panel.global_basis.get_rotation_quaternion()
	var turned := current.slerp(goal, 1.0 - exp(-turn_speed * delta))
	_panel.global_basis = Basis(turned).scaled(global_basis.get_scale())


func _build() -> void:
	# Internal children are regenerated on load, never saved with the scene.
	_panel = Node3D.new()
	_panel.name = "Panel"
	add_child(_panel, false, INTERNAL_MODE_BACK)

	_content = Node3D.new()
	_content.name = "Content"
	_panel.add_child(_content)

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
## background to fit and centers the whole panel on this node.
func _layout() -> void:
	_layout_queued = false
	if not _content:
		return

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

	_apply_opacity()


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


func _apply_opacity() -> void:
	if not _panel:
		return
	_panel.visible = _opacity > 0.0
	for child in _content.get_children():
		if child is GeometryInstance3D:
			child.transparency = 1.0 - _opacity


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
