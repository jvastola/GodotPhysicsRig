extends Node
class_name StaticNetworkSync
## A lightweight component dynamically attached to static meshes
## to allow them to receive network position and rotation updates.

var save_id: String = ""
var _network_manager: Node = null

func _ready() -> void:
    _network_manager = get_node_or_null("/root/NetworkManager")
    if _network_manager and _network_manager.has_signal("grabbable_sync_update"):
        _network_manager.grabbable_sync_update.connect(_on_network_sync)

func setup(id: String) -> void:
    save_id = id

func _on_network_sync(object_id: String, data: Dictionary) -> void:
    if object_id != save_id:
        return
    
    var parent = get_parent()
    if not is_instance_valid(parent) or not parent is Node3D:
        return
        
    # Ignore syncs if we are currently being grabbed locally
    if _network_manager and _network_manager.has_method("get_nakama_user_id"):
        var my_id = _network_manager.get_nakama_user_id()
        if _network_manager.has_method("get_object_owner"):
            if _network_manager.get_object_owner(object_id) == my_id:
                return

    if data.has("position"):
        parent.global_position = parent.global_position.lerp(data["position"], 0.3)
    
    if data.has("rotation"):
        var target_rot = data["rotation"]
        if target_rot is Quaternion:
            target_rot = (target_rot as Quaternion).normalized()
        var current_quat = parent.global_transform.basis.get_rotation_quaternion().normalized()
        var interpolated = current_quat.slerp(target_rot, 0.3)
        parent.global_transform.basis = Basis(interpolated)
        
    if data.has("scale"):
        var target_scale = data["scale"]
        if target_scale is Vector3:
            parent.scale = parent.scale.lerp(target_scale, 0.3)
