extends Node

## Simple inventory system for collecting resources

# Singleton instance
static var instance: Node

# Inventory storage: { "iron": 5, "gold": 2, etc. }
var inventory: Dictionary = {}
const _CURRENCY_KEYS := ["gold", "gems", "tokens"]

signal item_collected(item_type: String, amount: int, total: int)
signal inventory_changed()
signal currency_changed(type: String, amount: int)


func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	load_inventory()
	print("InventoryManager: Ready (loaded ", inventory.size(), " item types)")


func _normalize_item_type(item_type: String) -> String:
	var normalized := item_type.strip_edges().to_lower()
	if normalized == "coin" or normalized == "coins":
		return "gold"
	return normalized


func _is_currency(item_type: String) -> bool:
	return _CURRENCY_KEYS.has(_normalize_item_type(item_type))


func _persist_to_save() -> void:
	if not SaveManager:
		return
	if SaveManager.has_method("save_inventory_items"):
		SaveManager.save_inventory_items(inventory)
	else:
		# Fallback for legacy SaveManager API.
		var legacy_array: Array = []
		for item_name in inventory.keys():
			legacy_array.append({
				"id": str(item_name),
				"amount": int(inventory[item_name])
			})
		SaveManager.save_inventory(legacy_array)

	if SaveManager.has_method("set_currency_map"):
		var currency_snapshot := {}
		for currency_type in _CURRENCY_KEYS:
			currency_snapshot[currency_type] = int(inventory.get(currency_type, 0))
		SaveManager.set_currency_map(currency_snapshot)


func load_inventory() -> void:
	"""Load inventory and currencies from SaveManager."""
	inventory.clear()
	if SaveManager:
		if SaveManager.has_method("get_inventory_items"):
			var saved_items_variant: Variant = SaveManager.get_inventory_items()
			if saved_items_variant is Dictionary:
				var saved_items: Dictionary = saved_items_variant
				for key in saved_items.keys():
					var item_id := _normalize_item_type(str(key))
					inventory[item_id] = max(int(saved_items[key]), 0)
		elif SaveManager.has_method("get_inventory"):
			var legacy_variant: Variant = SaveManager.get_inventory()
			if legacy_variant is Dictionary:
				var legacy_dict: Dictionary = legacy_variant
				for key in legacy_dict.keys():
					var item_id := _normalize_item_type(str(key))
					inventory[item_id] = max(int(legacy_dict[key]), 0)
			elif legacy_variant is Array:
				for row_variant in legacy_variant:
					if row_variant is Dictionary:
						var row: Dictionary = row_variant
						var item_id := _normalize_item_type(str(row.get("id", "")))
						if item_id == "":
							continue
						inventory[item_id] = max(int(row.get("amount", 0)), 0)

		if SaveManager.has_method("get_all_currency"):
			var currency_map_variant: Variant = SaveManager.get_all_currency()
			if currency_map_variant is Dictionary:
				var currency_map: Dictionary = currency_map_variant
				for currency_type in _CURRENCY_KEYS:
					if currency_map.has(currency_type):
						inventory[currency_type] = max(int(currency_map[currency_type]), 0)

	# Ensure currency keys exist for UI consumers.
	for currency_type in _CURRENCY_KEYS:
		if not inventory.has(currency_type):
			inventory[currency_type] = 0

	inventory_changed.emit()
	for currency_type in _CURRENCY_KEYS:
		currency_changed.emit(currency_type, int(inventory.get(currency_type, 0)))


func add_item(item_type: String, amount: int = 1) -> void:
	"""Add items to inventory"""
	var normalized_type := _normalize_item_type(item_type)
	if amount == 0:
		return
	if not inventory.has(normalized_type):
		inventory[normalized_type] = 0
	
	inventory[normalized_type] = max(int(inventory[normalized_type]) + amount, 0)
	var total = int(inventory[normalized_type])
	
	print("InventoryManager: Collected ", amount, " ", normalized_type, " (Total: ", total, ")")
	
	item_collected.emit(normalized_type, amount, total)
	inventory_changed.emit()
	_persist_to_save()
	
	if _is_currency(normalized_type):
		currency_changed.emit(normalized_type, total)


func get_item_count(item_type: String) -> int:
	"""Get count of a specific item"""
	return int(inventory.get(_normalize_item_type(item_type), 0))


func has_item(item_type: String, amount: int = 1) -> bool:
	"""Check if inventory has at least amount of item"""
	return get_item_count(item_type) >= amount


func remove_item(item_type: String, amount: int = 1) -> bool:
	"""Remove items from inventory, returns true if successful"""
	var normalized_type := _normalize_item_type(item_type)
	if not has_item(normalized_type, amount):
		return false
	
	inventory[normalized_type] = int(inventory[normalized_type]) - amount
	if int(inventory[normalized_type]) <= 0:
		inventory.erase(normalized_type)
	
	inventory_changed.emit()
	_persist_to_save()
	
	if _is_currency(normalized_type):
		currency_changed.emit(normalized_type, int(inventory[normalized_type]) if inventory.has(normalized_type) else 0)
		
	return true


func clear_inventory() -> void:
	"""Clear all items"""
	inventory.clear()
	for currency_type in _CURRENCY_KEYS:
		inventory[currency_type] = 0
	inventory_changed.emit()
	_persist_to_save()


func get_all_items() -> Dictionary:
	"""Get a copy of the entire inventory"""
	return inventory.duplicate(true)


func get_currency(currency_type: String) -> int:
	"""Helper to get currency amount"""
	return get_item_count(currency_type)


func add_currency(currency_type: String, amount: int) -> void:
	"""Compatibility helper to add currencies."""
	add_item(currency_type, amount)


func spend_currency(currency_type: String, amount: int) -> bool:
	"""Spend currency if enough balance exists."""
	return remove_item(currency_type, amount)
