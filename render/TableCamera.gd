class_name TableCamera
extends Camera3D
## Perspective camera anchored to the local player's seat around the table.
##
## Starts looking at the table from that seat (see reset_to_seat, called once
## by GameScene after the local player's seat is known). Dragging rotates it
## horizontally around the table's vertical axis at a fixed height and
## radius - no zoom, no tilt, no free movement, and no auto-return to the
## seat once the player has dragged it elsewhere.

const FOV_DEGREES := 60.0
const HEIGHT_RATIO := 0.55
const RADIUS_RATIO := 0.85
const LOOK_AT_HEIGHT := 0.3
const DRAG_SENSITIVITY := 0.006

var _table_size := 15.0
var _angle := 0.0
var _dragging := false
var _drag_last_x := 0.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = FOV_DEGREES
	current = true
	_update_position()

## Called whenever the active ruleset's board size changes (e.g. switching
## between classic's 15 and megapolis's 11). Keeps the orbit radius/height
## matched to the table without resetting the angle the player rotated to.
func set_table_size(size: float) -> void:
	_table_size = size
	_update_position()

## Called once, when the local player's seat is first known - sets the
## starting angle at that seat. Never called again on later snapshots, so it
## never fights the player's own dragging.
func reset_to_seat(order: int, player_count: int) -> void:
	_angle = TAU * float(order) / float(maxi(player_count, 1))
	_update_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_last_x = event.position.x
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var delta_x: float = motion.position.x - _drag_last_x
		_drag_last_x = motion.position.x
		_angle -= delta_x * DRAG_SENSITIVITY
		_update_position()

func _update_position() -> void:
	var radius := _table_size * RADIUS_RATIO
	var height := _table_size * HEIGHT_RATIO
	position = Vector3(sin(_angle) * radius, height, cos(_angle) * radius)
	look_at(Vector3(0, LOOK_AT_HEIGHT, 0), Vector3.UP)
