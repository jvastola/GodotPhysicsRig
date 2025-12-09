# Test Inventory System
extends Node

@export var quit_when_done: bool = false
@export_file("*.tscn") var return_scene: String = "res://src/levels/MainScene.tscn"

var test_results: Array[String] = []


func _ready() -> void:
	print("\n=== INVENTORY SYSTEM TEST ===")
	
	# Wait a frame for autoloads to initialize
	await get_tree().process_frame
	
	# Test 1: Check autoloads exist
	test_autoloads()
	
	# Test 2: Test SaveManager currency functions
	test_save_manager()
	
	# Test 3: Test InventoryManager
	test_inventory_manager()
	
	# Print results
	print("\n=== TEST RESULTS ===")
	for result in test_results:
		print(result)
	
	print("\n=== TEST COMPLETE ===")
	
	# After tests, either quit (desktop) or return to main scene (device)
	await get_tree().create_timer(0.5).timeout
	if quit_when_done:
		print("TestInventory: quit_when_done=true, exiting tree")
		get_tree().quit()
	elif GameManager and GameManager.has_method("change_scene_with_player"):
		print("TestInventory: returning to main scene via GameManager")
		GameManager.call_deferred("change_scene_with_player", return_scene, { "use_spawn_point": true, "spawn_point": "SpawnPoint" })
	else:
		print("TestInventory: no GameManager; staying in test scene")


func test_autoloads() -> void:
	print("\n--- Testing Autoloads ---")
	
	if has_node("/root/SaveManager"):
		test_results.append("✓ SaveManager autoload exists")
		print("✓ SaveManager found")
	else:
		test_results.append("✗ SaveManager autoload NOT FOUND")
		print("✗ SaveManager NOT FOUND")
	
	if has_node("/root/InventoryManager"):
		test_results.append("✓ InventoryManager autoload exists")
		print("✓ InventoryManager found")
	else:
		test_results.append("✗ InventoryManager autoload NOT FOUND")
		print("✗ InventoryManager NOT FOUND")


func test_save_manager() -> void:
	print("\n--- Testing SaveManager ---")
	
	if not has_node("/root/SaveManager"):
		test_results.append("✗ Cannot test SaveManager - not found")
		return
	
	var save_mgr = get_node("/root/SaveManager")
	
	# Test currency
	save_mgr.add_currency("gold", 100)
	var gold = save_mgr.get_currency("gold")
	
	if gold == 100:
		test_results.append("✓ SaveManager currency works (gold: %d)" % gold)
		print("✓ Currency test passed: gold = %d" % gold)
	else:
		test_results.append("✗ SaveManager currency failed (expected 100, got %d)" % gold)
		print("✗ Currency test failed: expected 100, got %d" % gold)
	
	# Test inventory save/load
	var test_inventory = [{"id": "test_item", "amount": 5}]
	save_mgr.save_inventory(test_inventory)
	var loaded = save_mgr.get_inventory()
	
	if loaded.size() == 1 and loaded[0].get("id") == "test_item":
		test_results.append("✓ SaveManager inventory save/load works")
		print("✓ Inventory save/load passed")
	else:
		test_results.append("✗ SaveManager inventory save/load failed")
		print("✗ Inventory save/load failed")
	
	# Clear for next test
	save_mgr.clear_save_data()


func test_inventory_manager() -> void:
	print("\n--- Testing InventoryManager ---")
	
	if not has_node("/root/InventoryManager"):
		test_results.append("✗ Cannot test InventoryManager - not found")
		return
	
	var inv_mgr = get_node("/root/InventoryManager")
	
	# Test adding items
	inv_mgr.add_item("sword", 1)
	inv_mgr.add_item("potion", 3)
	
	if inv_mgr.has_item("sword", 1):
		test_results.append("✓ InventoryManager add_item/has_item works")
		print("✓ Item management passed")
	else:
		test_results.append("✗ InventoryManager add_item failed")
		print("✗ Item management failed")
	
	# Test currency
	inv_mgr.add_currency("gems", 50)
	var gems = inv_mgr.get_currency("gems")
	
	if gems == 50:
		test_results.append("✓ InventoryManager currency works (gems: %d)" % gems)
		print("✓ Currency via InventoryManager passed: gems = %d" % gems)
	else:
		test_results.append("✗ InventoryManager currency failed (expected 50, got %d)" % gems)
		print("✗ Currency via InventoryManager failed")
	
	print("\nInventory contents: ", inv_mgr.inventory)
