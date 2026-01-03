extends Node

# [修改] 增加 source_anim_name 參數
func export_web_files(output_dir: String, model_path: String, clips: Array, duration: float, single_file: bool = false, source_anim_name: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(output_dir)
	
	var model_filename = model_path.get_file()
	var model_output_path = output_dir.path_join(model_filename)
	
	if model_path.replace("\\", "/") != model_output_path.replace("\\", "/"):
		if DirAccess.copy_absolute(model_path, model_output_path) != OK:
			push_error("Failed to copy model file")
			return false
	
	if single_file:
		return _generate_single_html_file(output_dir, model_filename, clips, source_anim_name)
	else:
		if not _generate_config_json(output_dir, model_filename, clips, source_anim_name): return false
		if not _generate_index_html(output_dir): return false
		if not _generate_main_js(output_dir): return false
		return true

# --- 模式 A: 標準輸出 ---

func _generate_config_json(output_dir: String, model_filename: String, clips: Array, source_anim_name: String) -> bool:
	var config = {
		"modelFile": model_filename,
		"sourceAnimationName": source_anim_name, # [新增] 儲存來源動畫名稱
		"clips": []
	}
	
	for clip in clips:
		config.clips.append({
			"name": clip.name,
			"start": clip.start,
			"end": clip.end,
			"loop": clip.loop,
			"speed": clip.get("speed", 1.0)
		})
	
	var json_string = JSON.stringify(config, "\t")
	var file = FileAccess.open(output_dir.path_join("config.json"), FileAccess.WRITE)
	if file == null: return false
	file.store_string(json_string)
	file.close()
	return true

func _generate_index_html(output_dir: String) -> bool:
	# Index HTML 內容不變，與上個版本相同，這裡簡略帶過
	# (確保使用包含 importmap 的那個版本)
	var html_template = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AnimSlicer Preview</title>
    <script type="importmap">
    {
        "imports": {
            "three": "https://cdn.jsdelivr.net/npm/three@0.158.0/build/three.module.js",
            "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.158.0/examples/jsm/"
        }
    }
    </script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: sans-serif; background: #1e1e1e; color: #fff; overflow: hidden; }
        #canvas-container { width: 100vw; height: 100vh; }
        #controls { position: absolute; bottom: 20px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.8); padding: 20px; border-radius: 10px; display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; min-width: 300px; }
        button { padding: 10px 20px; background: #4a9eff; color: white; border: none; border-radius: 5px; cursor: pointer; }
        button:hover { background: #357abd; }
        #info { position: absolute; top: 20px; left: 20px; background: rgba(0,0,0,0.5); padding: 10px; border-radius: 5px; pointer-events: none; }
    </style>
</head>
<body>
    <div id="canvas-container"></div>
    <div id="info">Current: None</div>
    <div id="controls"><div id="button-container"></div></div>
    <script type="module" src="main.js"></script>
</body>
</html>"""
	var file = FileAccess.open(output_dir.path_join("index.html"), FileAccess.WRITE)
	if file == null: return false
	file.store_string(html_template)
	file.close()
	return true

# res://scripts/export_handler.gd 的 _generate_main_js 函式

func _generate_main_js(output_dir: String) -> bool:
	var js_template = """import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

let config, mixer, actions = {}, currentAction = null, model = null;
const clock = new THREE.Clock();

async function init() {
    if (window.location.protocol === 'file:') {
        alert("⚠️ Security Warning (CORS)\\n\\nPlease use a Local Server.");
    }

    try {
        const response = await fetch('config.json');
        config = await response.json();
        
        const scene = new THREE.Scene();
        scene.background = new THREE.Color(0x1e1e1e);
        
        const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        camera.position.set(0, 2, 5);
        
        const renderer = new THREE.WebGLRenderer({ antialias: true });
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.shadowMap.enabled = true;
        document.getElementById('canvas-container').appendChild(renderer.domElement);
        
        const controls = new OrbitControls(camera, renderer.domElement);
        controls.enableDamping = true;
        
        // 燈光
        const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
        scene.add(ambientLight);
        
        const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
        directionalLight.position.set(5, 10, 5);
        directionalLight.castShadow = true;
        scene.add(directionalLight);
        
        // [修改 Q2] 地板程式碼已移除
        // 原本這裡有 const ground = ...

        const loader = new GLTFLoader();
        loader.load(config.modelFile, (gltf) => {
            model = gltf.scene;
            scene.add(model);
            
            // 啟用陰影
            model.traverse((node) => {
                if (node.isMesh) {
                    node.castShadow = true;
                    node.receiveShadow = true;
                }
            });
            
            if (gltf.animations && gltf.animations.length > 0) {
                mixer = new THREE.AnimationMixer(model);
                
                // 自動尋找正確的動畫軌道
                let fullAnimation = gltf.animations[0];
                if (config.sourceAnimationName) {
                    const found = gltf.animations.find(a => a.name === config.sourceAnimationName);
                    if (found) fullAnimation = found;
                }
                
                config.clips.forEach(clipConfig => {
                    const fps = 30;
                    const subClip = THREE.AnimationUtils.subclip(
                        fullAnimation,
                        clipConfig.name,
                        Math.floor(clipConfig.start * fps),
                        Math.floor(clipConfig.end * fps),
                        fps
                    );
                    const action = mixer.clipAction(subClip);
                    action.timeScale = clipConfig.speed || 1.0;
                    
                    if (!clipConfig.loop) {
                        action.setLoop(THREE.LoopOnce);
                        action.clampWhenFinished = true;
                    }
                    
                    actions[clipConfig.name] = action;
                });
                
                createAnimationButtons();
            }
        });

        function animate() {
            requestAnimationFrame(animate);
            if (mixer) mixer.update(clock.getDelta());
            controls.update();
            renderer.render(scene, camera);
        }
        animate();

        window.addEventListener('resize', () => {
            camera.aspect = window.innerWidth / window.innerHeight;
            camera.updateProjectionMatrix();
            renderer.setSize(window.innerWidth, window.innerHeight);
        });

    } catch (error) {
        console.error('Init error:', error);
    }
}

function createAnimationButtons() {
    const container = document.getElementById('button-container');
    if(!container) return;
    container.innerHTML = '';
    
    config.clips.forEach(clip => {
        const button = document.createElement('button');
        button.textContent = clip.name;
        button.onclick = () => playAnimation(clip.name);
        container.appendChild(button);
    });
}

function playAnimation(name) {
    if (currentAction) currentAction.fadeOut(0.3);
    currentAction = actions[name];
    if (currentAction) {
        currentAction.reset().fadeIn(0.3).play();
        const info = document.getElementById('current-animation');
        if(info) info.textContent = `Current: ${name}`;
    }
}

init();
"""
	
	var file = FileAccess.open(output_dir.path_join("main.js"), FileAccess.WRITE)
	if file == null: return false
	file.store_string(js_template)
	file.close()
	return true
# --- 模式 B: 單一檔案輸出 ---

func _generate_single_html_file(output_dir: String, model_filename: String, clips: Array, source_anim_name: String) -> bool:
	var config_dict = {
		"modelFile": model_filename,
		"sourceAnimationName": source_anim_name,
		"clips": []
	}
	for clip in clips:
		config_dict.clips.append({
			"name": clip.name,
			"start": clip.start,
			"end": clip.end,
			"loop": clip.loop,
			"speed": clip.get("speed", 1.0)
		})
	
	var config_json = JSON.stringify(config_dict, "\t")
	
	var content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AnimSlicer - Single File</title>
    <script type="importmap">
    {
        "imports": {
            "three": "https://cdn.jsdelivr.net/npm/three@0.158.0/build/three.module.js",
            "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.158.0/examples/jsm/"
        }
    }
    </script>
    <style>
        body { margin: 0; overflow: hidden; background: #1e1e1e; font-family: sans-serif; color: white; }
        #canvas-container { width: 100vw; height: 100vh; }
        #controls { position: absolute; bottom: 20px; left: 50%; transform: translateX(-50%); background: rgba(0,0,0,0.8); padding: 15px; border-radius: 8px; display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; }
        button { padding: 8px 16px; background: #4a9eff; border: none; border-radius: 4px; color: white; cursor: pointer; }
        button:hover { background: #6ab0ff; }
        #info { position: absolute; top: 20px; left: 20px; background: rgba(0,0,0,0.5); padding: 10px; border-radius: 4px; pointer-events: none; }
    </style>
</head>
<body>
    <div id="canvas-container"></div>
    <div id="info">Current: None</div>
    <div id="controls"></div>

    <script type="module">
        import * as THREE from 'three';
        import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
        import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

        const config = {{CONFIG_JSON}}; 

        let mixer, actions = {}, currentAction = null;
        const clock = new THREE.Clock();

        async function init() {
            if (window.location.protocol === 'file:') {
                 alert("⚠️ CORS Error: Please use a Local Server.");
            }

            const scene = new THREE.Scene();
            scene.background = new THREE.Color(0x1e1e1e);
            const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
            camera.position.set(0, 2, 5);
            const renderer = new THREE.WebGLRenderer({ antialias: true });
            renderer.setSize(window.innerWidth, window.innerHeight);
            document.getElementById('canvas-container').appendChild(renderer.domElement);
            const controls = new OrbitControls(camera, renderer.domElement);

            scene.add(new THREE.DirectionalLight(0xffffff, 1));
            scene.add(new THREE.AmbientLight(0xffffff, 0.6));
            
            // [修改 Q2] 地板程式碼已移除 (這裡原本有 ground)

            const loader = new GLTFLoader();
            loader.load(config.modelFile, (gltf) => {
                scene.add(gltf.scene);
                
                if (gltf.animations.length > 0) {
                    mixer = new THREE.AnimationMixer(gltf.scene);
                    
                    let fullAnim = gltf.animations[0];
                    if (config.sourceAnimationName) {
                         const found = gltf.animations.find(a => a.name === config.sourceAnimationName);
                         if(found) fullAnim = found;
                    }

                    config.clips.forEach(clip => {
                        const sub = THREE.AnimationUtils.subclip(fullAnim, clip.name, clip.start * 30, clip.end * 30);
                        const action = mixer.clipAction(sub);
                        if (!clip.loop) {
                            action.setLoop(THREE.LoopOnce);
                            action.clampWhenFinished = true;
                        }
                        action.timeScale = clip.speed;
                        actions[clip.name] = action;

                        const btn = document.createElement('button');
                        btn.textContent = clip.name;
                        btn.onclick = () => {
                            if (currentAction) currentAction.fadeOut(0.2);
                            currentAction = actions[clip.name];
                            currentAction.reset().fadeIn(0.2).play();
                            document.getElementById('info').textContent = 'Current: ' + clip.name;
                        };
                        document.getElementById('controls').appendChild(btn);
                    });
                }
            });

            function animate() {
                requestAnimationFrame(animate);
                if (mixer) mixer.update(clock.getDelta());
                controls.update();
                renderer.render(scene, camera);
            }
            animate();
            
            window.onresize = () => {
                camera.aspect = window.innerWidth / window.innerHeight;
                camera.updateProjectionMatrix();
                renderer.setSize(window.innerWidth, window.innerHeight);
            };
        }
        init();
    </script>
</body>
</html>
""" 
	
	content = content.replace("{{CONFIG_JSON}}", config_json)

	var file = FileAccess.open(output_dir.path_join("index.html"), FileAccess.WRITE)
	if file == null: return false
	file.store_string(content)
	file.close()
	return true
