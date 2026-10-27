extends InteractionEffect
class_name ChangeSceneEffect

## 通用场景切换效果：具体目标场景由交互物资源配置，不硬编码剧情或关卡编号。
@export_file("*.tscn") var scene_path: String = ""


func apply(context: InteractionContext) -> void:
	var tree := context.tree()
	if scene_path.is_empty() or tree == null:
		push_warning("ChangeSceneEffect 缺少目标场景或有效场景树，已跳过")
		return
	tree.call_deferred(&"change_scene_to_file", scene_path)
