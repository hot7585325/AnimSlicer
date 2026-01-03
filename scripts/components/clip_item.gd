extends PanelContainer

signal clip_data_changed(data: Dictionary)

@onready var name_edit = $MarginContainer/VBox/NameEdit
@onready var loop_check = $MarginContainer/VBox/HBox/LoopCheck
# [修正] 配合新的 SpeedContainer 結構更新路徑
@onready var speed_spinbox = $MarginContainer/VBox/HBox/SpeedContainer/SpeedSpinBox

var clip_data: Dictionary = {}
var clip_index: int = -1
var is_selected: bool = false
var is_updating: bool = false

func _ready():
	_connect_signals()

func _connect_signals():
	if name_edit:
		name_edit.text_changed.connect(_on_name_changed)
	if loop_check:
		loop_check.toggled.connect(_on_loop_toggled)
	if speed_spinbox:
		speed_spinbox.value_changed.connect(_on_speed_changed)

func set_clip_data(data: Dictionary, index: int):
	is_updating = true
	clip_data = data.duplicate()
	clip_index = index
	
	if name_edit:
		name_edit.text = data.get("name", "Clip")
	if loop_check:
		loop_check.button_pressed = data.get("loop", true)
	if speed_spinbox:
		speed_spinbox.value = data.get("speed", 1.0)
	
	is_updating = false

func get_clip_data() -> Dictionary:
	return clip_data

func set_selected(selected: bool):
	is_selected = selected
	
	# 根據是否選中切換邊框顏色
	var style = get_theme_stylebox("panel").duplicate()
	if is_selected:
		style.border_color = Color(0.3, 0.7, 1.0, 1.0) # 亮藍色
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	else:
		style.border_color = Color(0.3, 0.3, 0.3, 1.0) # 深灰色
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
	
	add_theme_stylebox_override("panel", style)

func _on_name_changed(new_text: String):
	if is_updating: return
	clip_data.name = new_text
	_emit_change()

func _on_loop_toggled(toggled: bool):
	if is_updating: return
	clip_data.loop = toggled
	_emit_change()

func _on_speed_changed(value: float):
	if is_updating: return
	clip_data.speed = value
	_emit_change()

func _emit_change():
	clip_data_changed.emit(clip_data)
