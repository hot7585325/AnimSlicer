extends Camera3D

# Orbit Camera 控制參數
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 0.5
@export var pan_speed: float = 0.01
@export var min_distance: float = 2.0
@export var max_distance: float = 20.0

# 內部狀態
var target_position: Vector3 = Vector3.ZERO
var orbit_distance: float = 5.0
var orbit_rotation: Vector2 = Vector2(0, -30)  # yaw, pitch (degrees)
var is_rotating: bool = false
var is_panning: bool = false
var last_mouse_position: Vector2

func _ready():
	_update_camera_transform()

func _input(event):
	# 滑鼠右鍵旋轉
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			last_mouse_position = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			last_mouse_position = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_speed)
	
	# 滑鼠移動
	if event is InputEventMouseMotion:
		if is_rotating:
			var delta = event.position - last_mouse_position
			orbit_rotation.x += delta.x * orbit_speed * 100
			orbit_rotation.y = clamp(orbit_rotation.y + delta.y * orbit_speed * 100, -89, 89)
			_update_camera_transform()
			last_mouse_position = event.position
		elif is_panning:
			var delta = event.position - last_mouse_position
			_pan(delta)
			last_mouse_position = event.position

func _zoom(amount: float):
	orbit_distance = clamp(orbit_distance + amount, min_distance, max_distance)
	_update_camera_transform()

func _pan(delta: Vector2):
	var right = -transform.basis.x
	var up = transform.basis.y
	target_position += (right * delta.x + up * delta.y) * pan_speed * orbit_distance
	_update_camera_transform()

func _update_camera_transform():
	var yaw_rad = deg_to_rad(orbit_rotation.x)
	var pitch_rad = deg_to_rad(orbit_rotation.y)
	
	var x = orbit_distance * cos(pitch_rad) * sin(yaw_rad)
	var y = orbit_distance * sin(pitch_rad)
	var z = orbit_distance * cos(pitch_rad) * cos(yaw_rad)
	
	position = target_position + Vector3(x, y, z)
	look_at(target_position, Vector3.UP)

func focus_on_model(model: Node3D):
	# 計算模型的 AABB
	var aabb = _calculate_aabb(model)
	if aabb.has_volume():
		target_position = aabb.get_center()
		var size = aabb.size.length()
		orbit_distance = clamp(size * 1.5, min_distance, max_distance)
		_update_camera_transform()

func _calculate_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var first = true
	
	for child in _get_all_children(node):
		if child is MeshInstance3D:
			var mesh_aabb = child.get_aabb()
			var global_aabb = mesh_aabb
			
			# 轉換到世界空間
			global_aabb.position = child.global_transform.origin + global_aabb.position
			
			if first:
				aabb = global_aabb
				first = false
			else:
				aabb = aabb.merge(global_aabb)
	
	return aabb

func _get_all_children(node: Node) -> Array:
	var children = []
	children.append(node)
	for child in node.get_children():
		children.append_array(_get_all_children(child))
	return children
