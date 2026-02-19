extends Control

@onready var gold_label: Label = $Panel/MarginContainer/VBoxContainer/CurrencyContainer/GoldLabel
@onready var gems_label: Label = $Panel/MarginContainer/VBoxContainer/CurrencyContainer/GemsLabel
@onready var tokens_label: Label = $Panel/MarginContainer/VBoxContainer/CurrencyContainer/TokensLabel
@onready var inventory_grid: GridContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/InventoryGrid


func _ready() -> void:
	# Connect to InventoryManager signals
	if InventoryManager:
		InventoryManager.inventory_changed.connect(_on_inventory_changed)
		InventoryManager.currency_changed.connect(_on_currency_changed)
	
	# Initial update
	_update_currency()
	_update_inventory()


func _update_currency() -> void:
	if not InventoryManager:
		return
	
	var gold = InventoryManager.get_currency("gold")
	var gems = InventoryManager.get_currency("gems")
	var tokens = InventoryManager.get_currency("tokens")
	
	if gold_label:
		gold_label.text = "Gold: %d" % gold
	if gems_label:
		gems_label.text = "Gems: %d" % gems
	if tokens_label:
		tokens_label.text = "Tokens: %d" % tokens


func _update_inventory() -> void:
	if not InventoryManager or not inventory_grid:
		return
	
	# Clear existing slots
	for child in inventory_grid.get_children():
		child.queue_free()
	
	# Create slots for each item
	var items = InventoryManager.inventory
	for item in items:
		var slot = _create_inventory_slot(item)
		inventory_grid.add_child(slot)


func _create_inventory_slot(item_data: Dictionary) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(64, 64)
	
	var vbox = VBoxContainer.new()
	slot.add_child(vbox)
	
	var item_label = Label.new()
	item_label.text = item_data.get("id", "???")
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(item_label)
	
	var amount_label = Label.new()
	amount_label.text = "x%d" % item_data.get("amount", 1)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(amount_label)
	
	return slot


func _on_inventory_changed(_items: Array) -> void:
	_update_inventory()


func _on_currency_changed(_type: String, _amount: int) -> void:
	_update_currency()
