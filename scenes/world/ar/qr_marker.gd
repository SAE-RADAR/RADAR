@tool
class_name QRMarker
extends Marker3D

## Where a printed QR code is stuck on the real site, for [ARSession] to line
## the scan up with it in AR.
##
## Place it on the scan's surface at the center of the code, as it is on the
## real wall: +Y (green) toward the top of the code, +Z (blue) out of its
## printed face, toward whoever looks at it. The square shown in the editor is
## the code at its printed [member size], with a red tab on its top edge.
##
## The better it matches the real code, the better the scan lines up; what is
## left can be corrected in the headset (see [ARSession]).

## Text encoded in the QR code. Codes with other text are ignored, so stray QR
## codes on the site don't move the scan; empty matches any QR code.
@export var data := ""

## Side of the printed code, in meters; only for the preview.
@export_range(0.02, 1.0, 0.01, "or_greater", "suffix:m") var size := 0.2:
	set(value):
		size = maxf(value, 0.02)
		_update_preview()

## Shows the code's square; always on in the editor, and in AR while
## calibrating.
var preview_visible := false:
	set(value):
		preview_visible = value
		if _preview:
			_preview.visible = value or Engine.is_editor_hint()

var _preview: Node3D


func _ready() -> void:
	_preview = Node3D.new()
	_preview.name = "Preview"
	add_child(_preview)
	_update_preview()
	preview_visible = preview_visible


func _update_preview() -> void:
	if not _preview:
		return
	for child in _preview.get_children():
		child.queue_free()
	# Just off the wall so the scan doesn't hide it.
	_preview.add_child(_quad(Vector2(size, size), Vector3(0.0, 0.0, 0.002), Color(1.0, 1.0, 1.0, 0.6)))
	var tab := size * 0.2
	_preview.add_child(_quad(Vector2(tab, tab), Vector3(0.0, (size + tab) * 0.5, 0.002), Color(1.0, 0.2, 0.2, 0.9)))


func _quad(quad_size: Vector2, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
