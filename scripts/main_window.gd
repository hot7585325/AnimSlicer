extends Control

# 節點引用
@onready var info_label = $VBoxContainer/TopBar/MarginContainer/HBox/InfoLabel
@onready var import_button = $VBoxContainer/TopBar/MarginContainer/HBox/ActionButtons/ImportButton
@onready var export_button = $VBoxContainer/TopBar/MarginContainer/HBox/ActionButtons/ExportButton
# [新增] 重新匯入按鈕 (稍後在 UI 加入)
@onready var update_button = $VBoxContainer/TopBar/MarginContainer/HBox/ActionButtons/UpdateModelButton

@onready var add_clip_button = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBox/HeaderBox/ToolBar/AddClipButton
@onready var remove_clip_button = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBox/HeaderBox/ToolBar/RemoveClipButton
@onready var clip_manager = $VBoxContainer/HSplitContainer/LeftPanel/MarginContainer/VBox/ClipList/ClipContainer
@onready var timeline_editor = $VBoxContainer/BottomPanel/MarginContainer/VBox
@onready var model_holder = $VBoxContainer/HSplitContainer/ViewportPanel/SubViewportContainer/SubViewport/ModelHolder
@onready var camera = $VBoxContainer/HSplitContainer/ViewportPanel/SubViewportContainer/SubViewport/Camera3D
@onready var file_dialog = $FileDialog

@onready var source_anim_option = $VBoxContainer/TopBar/MarginContainer/HBox/ActionButtons/SourceAnimOption
@onready var single_file_check = $VBoxContainer/TopBar/MarginContainer/HBox/ActionButtons/SingleFileCheck
# 狀態變數
var current_model_path: String = ""
var loaded_scene: Node3D = null
var animation_player: AnimationPlayer = null
var is_updating_model: bool = false # [新增] 標記是否為更新模式
var model_info = {
	"vertices": 0,
	"faces": 0,
	"animations": 0,
	"duration": 0.0
}

func _ready():
	_setup_drag_and_drop()
	_setup_grid()
	_connect_signals()

func _setup_drag_and_drop():
	get_viewport().files_dropped.connect(_on_files_dropped)

func _on_export_dir_selected(dir_path: String):
	var exporter = load("res://scripts/export_handler.gd").new()
	var clips = clip_manager.get_all_clips()
	var is_single_file = single_file_check.button_pressed if single_file_check else false
	
	# [關鍵修正] 自動偵測邏輯
	var current_anim_name = ""
	
	# 策略：直接問 AnimationPlayer 現在載入的是哪一條
	if animation_player:
		current_anim_name = animation_player.current_animation
		
		# 如果 Player 說是空的 (有時剛載入沒播放)，則嘗試抓列表的第一個
		if current_anim_name == "":
			var list = animation_player.get_animation_list()
			if list.size() > 0:
				current_anim_name = list[0]
	
	# 開始匯出
	var success = exporter.export_web_files(
		dir_path,
		current_model_path,
		clips,
		model_info.duration,
		is_single_file,
		current_anim_name # 這裡會自動傳入正確的名稱
	)
	
	if success:
		info_label.text = "Export successful!"
		# 註解掉這行就不會自動打開資料夾
		# OS.shell_open(dir_path) 
		await get_tree().create_timer(2.0).timeout
		_update_info_label()
	else:
		info_label.text = "Export failed!"
		await get_tree().create_timer(2.0).timeout
		_update_info_label()

func _setup_grid():
	pass 
	# 如果以後想加回來，把下面解開註解即可
	# var grid_mesh = $VBoxContainer/HSplitContainer/ViewportPanel/SubViewportContainer/SubViewport/GridMesh
	# var plane_mesh = PlaneMesh.new()
	# plane_mesh.size = Vector2(10, 10)
	# plane_mesh.subdivide_width = 10
	# plane_mesh.subdivide_depth = 10
	# var material = StandardMaterial3D.new()
	# material.albedo_color = Color(0.3, 0.3, 0.3, 1.0)
	# material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# grid_mesh.mesh = plane_mesh
	# grid_mesh.material_override = material
	
	#var material = StandardMaterial3D.new()
	#material.albedo_color = Color(0.3, 0.3, 0.3, 1.0)
	#material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	#
	#grid_mesh.mesh = plane_mesh
	#grid_mesh.material_override = material

func _connect_signals():
	clip_manager.clip_selected.connect(_on_clip_selected)
	clip_manager.clips_changed.connect(_update_ui_state)
	timeline_editor.time_changed.connect(_on_timeline_time_changed)
	timeline_editor.range_changed.connect(_on_timeline_range_changed)
	
# [修正] 加入檢查，避免重複連接報錯
	if update_button and not update_button.pressed.is_connected(_on_update_model_pressed):
		update_button.pressed.connect(_on_update_model_pressed)

	# [修正] 同樣檢查下拉選單
	if source_anim_option and not source_anim_option.item_selected.is_connected(_on_source_anim_selected):
		source_anim_option.item_selected.connect(_on_source_anim_selected)

func _on_import_button_pressed():
	is_updating_model = false # 清除更新標記
	file_dialog.title = "Import GLB Model"
	file_dialog.popup_centered()

# [新增] 重新匯入按鈕邏輯
func _on_update_model_pressed():
	is_updating_model = true # 設定更新標記
	file_dialog.title = "Update GLB Model (Keep Clips)"
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	_load_glb(path, is_updating_model) # 傳入是否保留資料

func _on_files_dropped(files: PackedStringArray):
	if files.size() > 0:
		var file_path = files[0]
		if file_path.get_extension().to_lower() in ["glb", "gltf"]:
			# 拖放預設視為全新匯入，除非按住 Shift (可選優化，這裡暫時全當新匯入)
			_load_glb(file_path, false)
		else:
			_update_info_label("Error: Invalid file format (only .glb/.gltf)")

# [修改] 增加 keep_data 參數
func _load_glb(path: String, keep_data: bool = false):
	# 1. 備份舊資料
	var old_clips = []
	if keep_data:
		old_clips = clip_manager.get_all_clips()
	
	# 2. 清除舊模型
	_clear_model()
	
	info_label.text = "Loading..."
	
	# 3. 載入新模型
	var gltf_document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var error = gltf_document.append_from_file(path, gltf_state)
	
	if error != OK:
		_update_info_label("Error: Failed to load file (Corrupted or invalid)")
		return
	
	loaded_scene = gltf_document.generate_scene(gltf_state)
	model_holder.add_child(loaded_scene)
	current_model_path = path
	
	animation_player = _find_animation_player(loaded_scene)
	
	if animation_player == null:
		_update_info_label("Warning: No animations found")
		model_info.animations = 0
		model_info.duration = 0.0
	else:
		var anim_list = animation_player.get_animation_list()
		model_info.animations = anim_list.size()
		# [新增] 填入下拉選單
		source_anim_option.clear()
		source_anim_option.disabled = false
		for anim_name in anim_list:
			source_anim_option.add_item(anim_name)
		
		if anim_list.size() > 0:
			# 預設選取第一個，或保留上次選的(如果是 Update)
			_on_source_anim_selected(0) 
		else:
			model_info.duration = 0.0
			
	
	_calculate_model_info(loaded_scene)
	
	# [新增] 4. 還原舊資料
	if keep_data and old_clips.size() > 0:
		for clip in old_clips:
			# 安全檢查：確保時間不超過新模型的總長度
			if clip.start > model_info.duration:
				clip.start = 0.0
			if clip.end > model_info.duration:
				clip.end = model_info.duration
			# 加入還原的片段
			clip_manager.add_clip(clip)
		
		info_label.text = "Model updated! (%d clips restored)" % old_clips.size()
	else:
		_update_info_label()
		
	_update_ui_state()
	camera.focus_on_model(loaded_scene)

# [新增] 處理來源動畫切換
func _on_source_anim_selected(index: int):
	if animation_player == null: return
	
	var anim_list = animation_player.get_animation_list()
	if index >= 0 and index < anim_list.size():
		var anim_name = anim_list[index]
		var anim = animation_player.get_animation(anim_name)
		
		# 1. 切換當前動畫
		animation_player.current_animation = anim_name
		animation_player.play(anim_name)
		animation_player.pause()
		
		# 2. 更新全域資訊
		model_info.duration = anim.length
		
		# 3. 通知 Timeline Editor 更新長度與範圍
		timeline_editor.set_animation_player(animation_player, anim.length)
		
		# 4. 更新資訊欄
		_update_info_label()
		
		# 5. [可選] 如果切換了來源動畫，是否要清空目前的 Clips？
		# 目前策略：保留 Clip，但使用者自己要注意時間軸是否對得上

func _clear_model():
	if loaded_scene:
		loaded_scene.queue_free()
		loaded_scene = null
	animation_player = null
	clip_manager.clear_clips()
	timeline_editor.clear()

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _calculate_model_info(node: Node):
	var vertices = 0
	var faces = 0
	for child in _get_all_children(node):
		if child is MeshInstance3D:
			var mesh = child.mesh
			if mesh:
				vertices += mesh.get_faces().size()
				faces += mesh.get_faces().size() / 3
	model_info.vertices = vertices
	model_info.faces = faces

func _get_all_children(node: Node) -> Array:
	var children = []
	children.append(node)
	for child in node.get_children():
		children.append_array(_get_all_children(child))
	return children

func _update_info_label(custom_text: String = ""):
	if custom_text != "":
		info_label.text = custom_text
	elif loaded_scene:
		info_label.text = "Vertices: %d | Faces: %d | Animations: %d | Duration: %.2fs" % [
			model_info.vertices,
			model_info.faces,
			model_info.animations,
			model_info.duration
		]
	else:
		info_label.text = "No model loaded"

func _update_ui_state():
	var has_model = loaded_scene != null
	var has_animation = animation_player != null and model_info.animations > 0
	
	export_button.disabled = not has_model or clip_manager.get_clip_count() == 0
	if update_button: update_button.disabled = not has_model # 只有載入模型後才能更新
	
	add_clip_button.disabled = not has_animation
	remove_clip_button.disabled = not has_animation or clip_manager.get_selected_clip() == null

func _on_add_clip_pressed():
	if animation_player == null: return
	
	var new_start = 0.0
	var new_end = min(2.0, model_info.duration)
	var existing_clips = clip_manager.get_all_clips()
	if existing_clips.size() > 0:
		var last_clip = existing_clips[-1]
		var last_duration = last_clip.end - last_clip.start
		new_start = last_clip.end
		if new_start >= model_info.duration - 0.1:
			new_start = 0.0
			new_end = min(2.0, model_info.duration)
		else:
			new_end = min(new_start + last_duration, model_info.duration)
			if new_end - new_start < 0.5:
				new_end = min(new_start + 2.0, model_info.duration)
	
	var clip_data = {
		"name": "Clip_%d" % (clip_manager.get_clip_count() + 1),
		"start": new_start,
		"end": new_end,
		"loop": true,
		"speed": 1.0
	}
	clip_manager.add_clip(clip_data)
	clip_manager._select_clip(clip_manager.get_clip_count() - 1)
	_update_ui_state()

func _on_remove_clip_pressed():
	clip_manager.remove_selected_clip()
	_update_ui_state()

func _on_clip_selected(clip_data: Dictionary):
	timeline_editor.set_range(clip_data.start, clip_data.end)

func _on_timeline_range_changed(start: float, end: float):
	clip_manager.update_selected_clip_range(start, end)

func _on_timeline_time_changed(time: float):
	if animation_player:
		var anim_list = animation_player.get_animation_list()
		if anim_list.size() > 0:
			animation_player.play(anim_list[0])
			animation_player.seek(time, true)
			animation_player.pause()

func _on_export_button_pressed():
	if loaded_scene == null or clip_manager.get_clip_count() == 0: return
	var dir_dialog = FileDialog.new()
	dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	dir_dialog.title = "Select Export Directory"
	dir_dialog.size = Vector2i(800, 500)
	dir_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	dir_dialog.dir_selected.connect(_on_export_dir_selected)
	add_child(dir_dialog)
	dir_dialog.popup_centered()
