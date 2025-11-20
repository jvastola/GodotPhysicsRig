extends Control

## Debug overlay for VoxelChunkManager statistics
## Add this to your scene to see real-time voxel system info

@export var voxel_manager_path: NodePath = NodePath()
@export var update_interval: float = 0.5

var _voxel_manager: VoxelChunkManager = null
var _label: Label = null
var _time_since_update: float = 0.0

func _ready() -> void:
	# Create label for stats display
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	
	# Find voxel manager
	if voxel_manager_path != NodePath():
		_voxel_manager = get_node_or_null(voxel_manager_path) as VoxelChunkManager
	
	if not _voxel_manager:
		_voxel_manager = get_tree().root.find_child("VoxelChunkManager", true, false) as VoxelChunkManager
	
	if _voxel_manager:
		print("VoxelDebugOverlay: Found manager")
	else:
		print("VoxelDebugOverlay: Manager not found")

func _process(delta: float) -> void:
	_time_since_update += delta
	if _time_since_update < update_interval:
		return
	_time_since_update = 0.0
	
	if not _voxel_manager:
		_label.text = "Voxel Manager: NOT FOUND"
		return
	
	var stats := _voxel_manager.get_stats()
	var text := "=== Voxel System Stats ===\n"
	text += "Chunks: %d\n" % stats.chunks
	text += "Voxels: %d\n" % stats.voxels
	text += "Avg Voxels/Chunk: %.1f\n" % stats.avg_voxels_per_chunk
	text += "Voxel Size: %.3f\n" % _voxel_manager._voxel_size
	
	# Memory estimation
	var node_count := stats.chunks * 3  # StaticBody + MeshInstance + CollisionShape per chunk
	var old_node_count := stats.voxels * 3  # What it would be without chunking
	var reduction := 100.0 * (1.0 - float(node_count) / max(old_node_count, 1))
	text += "\nNode Count: %d (vs %d)\n" % [node_count, old_node_count]
	text += "Reduction: %.2f%%\n" % reduction
	
	_label.text = text
