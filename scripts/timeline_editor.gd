extends VBoxContainer

signal time_changed(time: float)
signal range_changed(start: float, end: float)

@onready var play_button = $ControlBar/PlayButton
@onready var current_time_label = $ControlBar/CurrentTimeLabel
@onready var range_slider = $RangeSlider
@onready var start_spinbox = $Header/TimeInputs/StartSpinBox
@onready var end_spinbox = $Header/TimeInputs/EndSpinBox
@onready var fps_check = $Header/TimeInputs/FPSCheck

var animation_player: AnimationPlayer = null
var total_duration: float = 0.0
var current_time: float = 0.0
var is_playing: bool = false

var use_frames: bool = false
const FPS: float = 30.0

func _ready():
	await get_tree().process_frame
	_connect_signals()
	# 初始設定
	if start_spinbox: start_spinbox.set_value_no_signal(0.0)
	if end_spinbox: end_spinbox.set_value_no_signal(1.0)
	_update_spinbox_props() # 設定初始 step/suffix

func _connect_signals():
	# 綁定信號
	if start_spinbox: start_spinbox.value_changed.connect(_on_start_spinbox_changed)
	if end_spinbox: end_spinbox.value_changed.connect(_on_end_spinbox_changed)
	
	if range_slider:
		if range_slider.has_signal("value_changed"):
			range_slider.value_changed.connect(_on_range_slider_changed)
		if range_slider.has_signal("current_time_changed"):
			range_slider.current_time_changed.connect(_on_current_time_changed)
	
	if fps_check:
		fps_check.toggled.connect(_on_fps_toggled)

# --- 核心修復：安全地切換模式 ---
func _on_fps_toggled(toggled: bool):
	# 1. 先暫存當前 Slider 的秒數 (這是最準確的真理值)
	var current_start_s = range_slider.start_value
	var current_end_s = range_slider.end_value
	
	# 2. 切換狀態
	use_frames = toggled
	
	# 3. [關鍵] 暫時斷開信號，避免修改 step 時觸發 value_changed 造成數值錯亂
	if start_spinbox.value_changed.is_connected(_on_start_spinbox_changed):
		start_spinbox.value_changed.disconnect(_on_start_spinbox_changed)
	if end_spinbox.value_changed.is_connected(_on_end_spinbox_changed):
		end_spinbox.value_changed.disconnect(_on_end_spinbox_changed)
	
	# 4. 修改 UI 屬性 (Step, Suffix, Max)
	_update_spinbox_props()
	
	# 5. 將原本的秒數轉換為新單位，填入 SpinBox
	start_spinbox.set_value_no_signal(_to_display_unit(current_start_s))
	end_spinbox.set_value_no_signal(_to_display_unit(current_end_s))
	
	# 6. 設定完成後，重新連接信號
	start_spinbox.value_changed.connect(_on_start_spinbox_changed)
	end_spinbox.value_changed.connect(_on_end_spinbox_changed)
	
	_update_time_label()

func _update_spinbox_props():
	# 設定最大值
	var max_val = _to_display_unit(total_duration) if total_duration > 0 else 1000.0
	
	if use_frames:
		if start_spinbox: 
			start_spinbox.step = 1.0
			start_spinbox.suffix = "f"
			start_spinbox.max_value = max_val
		if end_spinbox: 
			end_spinbox.step = 1.0
			end_spinbox.suffix = "f"
			end_spinbox.max_value = max_val
	else:
		if start_spinbox: 
			start_spinbox.step = 0.01
			start_spinbox.suffix = "s"
			start_spinbox.max_value = max_val
		if end_spinbox: 
			end_spinbox.step = 0.01
			end_spinbox.suffix = "s"
			end_spinbox.max_value = max_val

# --- 單位轉換 ---
func _to_display_unit(seconds: float) -> float:
	if use_frames: return round(seconds * FPS)
	return seconds

func _from_display_unit(value: float) -> float:
	if use_frames: return value / FPS
	return value

# --- 信號處理 ---
func _on_start_spinbox_changed(value: float):
	var start_s = _from_display_unit(value)
	var end_s = range_slider.end_value 
	
	if start_s >= end_s:
		start_s = end_s - (1.0/FPS if use_frames else 0.01)
		start_spinbox.set_value_no_signal(_to_display_unit(start_s))
	
	if range_slider: range_slider.set_range(start_s, end_s)
	_emit_range_changed()

func _on_end_spinbox_changed(value: float):
	var end_s = _from_display_unit(value)
	var start_s = range_slider.start_value
	
	if end_s <= start_s:
		end_s = start_s + (1.0/FPS if use_frames else 0.01)
		end_spinbox.set_value_no_signal(_to_display_unit(end_s))
	
	if range_slider: range_slider.set_range(start_s, end_s)
	_emit_range_changed()

func _on_range_slider_changed(start_sec: float, end_sec: float):
	# Slider 傳來的是秒數，轉為顯示單位填入 UI
	if start_spinbox: start_spinbox.set_value_no_signal(_to_display_unit(start_sec))
	if end_spinbox: end_spinbox.set_value_no_signal(_to_display_unit(end_sec))
	_emit_range_changed()

func _emit_range_changed():
	range_changed.emit(range_slider.start_value, range_slider.end_value)

# --- 其他標準功能 ---
func set_animation_player(player: AnimationPlayer, duration: float):
	animation_player = player
	total_duration = duration
	
	if start_spinbox.value_changed.is_connected(_on_start_spinbox_changed):
		start_spinbox.value_changed.disconnect(_on_start_spinbox_changed)
	if end_spinbox.value_changed.is_connected(_on_end_spinbox_changed):
		end_spinbox.value_changed.disconnect(_on_end_spinbox_changed)
		
	_update_spinbox_props()
	
	if range_slider:
		range_slider.set_max_value(duration)
		range_slider.set_range(0.0, duration)
	
	start_spinbox.set_value_no_signal(0.0)
	end_spinbox.set_value_no_signal(_to_display_unit(duration))
	
	start_spinbox.value_changed.connect(_on_start_spinbox_changed)
	end_spinbox.value_changed.connect(_on_end_spinbox_changed)
	
	if play_button: play_button.disabled = false
	current_time = 0.0
	_update_time_label()

func set_range(start_sec: float, end_sec: float):
	if range_slider: range_slider.set_range(start_sec, end_sec)
	if start_spinbox: start_spinbox.set_value_no_signal(_to_display_unit(start_sec))
	if end_spinbox: end_spinbox.set_value_no_signal(_to_display_unit(end_sec))

func clear():
	animation_player = null
	total_duration = 0.0
	current_time = 0.0
	is_playing = false
	if play_button:
		play_button.disabled = true
		play_button.text = "▶"
	_update_time_label()

func _on_play_button_pressed():
	if animation_player == null: return
	is_playing = not is_playing
	if is_playing:
		play_button.text = "⏸"
		var anim_list = animation_player.get_animation_list()
		if anim_list.size() > 0: animation_player.play(anim_list[0])
	else:
		play_button.text = "▶"
		animation_player.pause()

func _process(delta):
	if is_playing and animation_player:
		current_time = animation_player.current_animation_position
		var start_s = range_slider.start_value
		var end_s = range_slider.end_value
		
		if current_time < start_s or current_time > end_s:
			current_time = start_s
			animation_player.seek(current_time, true)
		
		if range_slider: range_slider.set_current_time(current_time)
		_update_time_label()
		
		if current_time >= end_s - 0.05:
			current_time = start_s
			animation_player.seek(current_time, true)

func _on_current_time_changed(time: float):
	current_time = time
	_update_time_label()
	time_changed.emit(time)

func _update_time_label():
	if current_time_label:
		if use_frames: current_time_label.text = "%d f" % int(current_time * FPS)
		else: current_time_label.text = "%.2fs" % current_time
