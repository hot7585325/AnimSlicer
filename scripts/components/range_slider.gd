extends Control

signal value_changed(start: float, end: float)
signal current_time_changed(time: float)

@onready var background = $Background
@onready var selected_range = $SelectedRange
@onready var start_handle = $StartHandle
@onready var end_handle = $EndHandle
@onready var current_time_line = $CurrentTimeLine

var min_value: float = 0.0
var max_value: float = 10.0
var start_value: float = 0.0
var end_value: float = 10.0
var current_time: float = 0.0

var dragging_start: bool = false
var dragging_end: bool = false
var dragging_timeline: bool = false

var handle_width: float = 10.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_visuals()

func set_max_value(value: float):
	max_value = value
	end_value = value
	queue_redraw() # 觸發重繪刻度
	_update_visuals()

func set_range(start: float, end: float):
	start_value = clamp(start, min_value, max_value)
	end_value = clamp(end, min_value, max_value)
	_update_visuals()

func set_current_time(time: float):
	current_time = clamp(time, min_value, max_value)
	_update_visuals()

# [新增] 繪製刻度
func _draw():
	var width = size.x
	var height = size.y
	
	# 決定刻度間距 (秒)
	var step = 1.0
	if max_value <= 1.0: step = 0.1
	elif max_value <= 5.0: step = 0.5
	elif max_value <= 10.0: step = 1.0
	elif max_value <= 30.0: step = 5.0
	else: step = 10.0
	
	var time = 0.0
	while time <= max_value:
		var x = (time / max_value) * width
		
		# 畫刻度線
		var color = Color(1, 1, 1, 0.3)
		var line_height = height * 0.3
		
		# 整數秒加長加粗
		if fmod(time, 1.0) == 0:
			color = Color(1, 1, 1, 0.5)
			line_height = height * 0.5
			
		draw_line(Vector2(x, height), Vector2(x, height - line_height), color, 1.0)
		time += step

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var mouse_x = event.position.x
				var start_pos = _value_to_position(start_value)
				var end_pos = _value_to_position(end_value)
				
				# 判斷點擊位置 (增加一點容錯距離 10px)
				if abs(mouse_x - start_pos) < handle_width + 10:
					dragging_start = true
				elif abs(mouse_x - end_pos) < handle_width + 10:
					dragging_end = true
				else:
					dragging_timeline = true
					_update_from_mouse(mouse_x)
			else:
				dragging_start = false
				dragging_end = false
				dragging_timeline = false
	
	elif event is InputEventMouseMotion:
		if dragging_start:
			var new_value = _position_to_value(event.position.x)
			start_value = clamp(new_value, min_value, end_value - 0.01) # 最小間隔
			value_changed.emit(start_value, end_value)
			_update_visuals()
		elif dragging_end:
			var new_value = _position_to_value(event.position.x)
			end_value = clamp(new_value, start_value + 0.01, max_value)
			value_changed.emit(start_value, end_value)
			_update_visuals()
		elif dragging_timeline:
			_update_from_mouse(event.position.x)

func _update_from_mouse(mouse_x: float):
	var time = _position_to_value(mouse_x)
	current_time = clamp(time, min_value, max_value)
	current_time_changed.emit(current_time)
	_update_visuals()

func _value_to_position(value: float) -> float:
	var width = size.x
	if max_value == min_value: return 0.0
	var normalized = (value - min_value) / (max_value - min_value)
	return normalized * width

func _position_to_value(position: float) -> float:
	var width = size.x
	if width == 0: return 0.0
	var normalized = position / width
	return min_value + normalized * (max_value - min_value)

func _update_visuals():
	if not is_inside_tree(): return
	
	# 重繪時也需要更新刻度位置
	queue_redraw()
	
	var start_pos = _value_to_position(start_value)
	var end_pos = _value_to_position(end_value)
	var time_pos = _value_to_position(current_time)
	
	# 更新 UI 元素位置
	if selected_range:
		selected_range.position.x = start_pos
		selected_range.size.x = max(end_pos - start_pos, 0)
	
	if start_handle: start_handle.position.x = start_pos - (start_handle.size.x / 2)
	if end_handle: end_handle.position.x = end_pos - (end_handle.size.x / 2)
	if current_time_line: current_time_line.position.x = time_pos
