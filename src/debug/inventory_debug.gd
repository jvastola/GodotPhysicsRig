extends Node

## Debug script to test inventory and currency systems
## Press keys to add currency and items for testing


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	
	# Add currency with number keys
	match event.keycode:
		KEY_1:
			InventoryManager.add_currency("gold", 100)
			print("Debug: Added 100 gold")
		KEY_2:
			InventoryManager.add_currency("gems", 10)
			print("Debug: Added 10 gems")
		KEY_3:
			InventoryManager.add_currency("tokens", 5)
			print("Debug: Added 5 tokens")
		KEY_4:
			InventoryManager.add_item("sword", 1)
			print("Debug: Added sword")
		KEY_5:
			InventoryManager.add_item("potion", 3)
			print("Debug: Added 3 potions")
		KEY_6:
			InventoryManager.add_item("gem_fragment", 10)
			print("Debug: Added 10 gem fragments")
		KEY_0:
			# Clear all inventory and currency for testing
			SaveManager.clear_save_data()
			InventoryManager.load_inventory()
			print("Debug: Cleared all save data")
