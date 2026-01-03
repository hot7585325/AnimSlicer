extends VBoxContainer

signal clip_selected(clip_data: Dictionary)
signal clips_changed()

const ClipItemScene = preload("res://scenes/components/clip_item.tscn")

var clips: Array[Dictionary] = []
var selected_index: int = -1
var drag_from_index: int = -1
var is_dragging: bool = false

func _ready():
	set_process_input(true)

func add_clip(clip_data: Dictionary):
	clips.append(clip_data.duplicate())
	_rebuild_list()
	clips_changed.emit()

func remove_selected_clip():
	if selected_index >= 0 and selected_index < clips.size():
		clips.remove_at(selected_index)
		selected_index = -1
		_rebuild_list()
		clips_changed.emit()

func get_selected_clip() -> Dictionary:
	if selected_index >= 0 and selected_index < clips.size():
		return clips[selected_index]
	return {}

func update_selected_clip_range(start: float, end: float):
	"""更新選中片段的時間範圍"""
	if selected_index >= 0 and selected_index < clips.size():
		clips[selected_index].start = start
		clips[selected_index].end = end
		clips_changed.emit()

func get_all_clips() -> Array[Dictionary]:
	return clips

func get_clip_count() -> int:
	return clips.size()

func clear_clips():
	clips.clear()
	selected_index = -1
	_rebuild_list()
	clips_changed.emit()

func _rebuild_list():
	# 清除所有子節點
	for child in get_children():
		child.queue_free()
	
	# 重建列表
	for i in range(clips.size()):
		var clip_item = ClipItemScene.instantiate()
		add_child(clip_item)
		clip_item.set_clip_data(clips[i], i)
		clip_item.set_selected(i == selected_index)
		
		# 連接信號
		clip_item.gui_input.connect(_on_clip_item_input.bind(i))
		clip_item.clip_data_changed.connect(_on_clip_data_changed.bind(i))

func _on_clip_item_input(event: InputEvent, index: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_clip(index)
			# 開始拖曳檢測
			drag_from_index = index
			is_dragging = true

func _select_clip(index: int):
	if index != selected_index:
		selected_index = index
		_rebuild_list()
		if index >= 0 and index < clips.size():
			clip_selected.emit(clips[index])

func _on_clip_data_changed(new_data: Dictionary, index: int):
	if index >= 0 and index < clips.size():
		# 只更新 name, loop, speed，保留 start, end
		clips[index].name = new_data.get("name", clips[index].name)
		clips[index].loop = new_data.get("loop", clips[index].loop)
		clips[index].speed = new_data.get("speed", clips[index].speed)
		clips_changed.emit()

# 拖曳排序實作
func _input(event: InputEvent):
	if not is_dragging:
		return
	
	if event is InputEventMouseMotion and drag_from_index >= 0:
		# 獲取滑鼠的全域位置
		var mouse_global_pos = get_viewport().get_mouse_position()
		
		# 轉換為相對於容器的位置
		var container_global_pos = global_position
		var local_y = mouse_global_pos.y - container_global_pos.y
		
		# 計算目標索引 (根據滑鼠 Y 座標)
		var item_height = 90  # 每個 clip item 的高度
		var target_index = int(local_y / item_height)
		target_index = clamp(target_index, 0, clips.size() - 1)
		
		# 如果位置改變，交換片段
		if target_index != drag_from_index and target_index >= 0 and target_index < clips.size():
			var temp = clips[drag_from_index]
			clips.remove_at(drag_from_index)
			clips.insert(target_index, temp)
			
			# 更新選中索引
			if selected_index == drag_from_index:
				selected_index = target_index
			elif selected_index == target_index:
				selected_index = drag_from_index
			
			drag_from_index = target_index
			_rebuild_list()
	
	# 滑鼠放開時停止拖曳
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = false
			drag_from_index = -1
