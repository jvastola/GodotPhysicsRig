extends Node

## Simple inventory system for collecting resources

# Singleton instance
static var instance: Node

# Inventory storage: { "iron": 5, "gold": 2, etc. }
var inventory: Dictionary = {}
const _CURRENCY_KEYS := ["gold", "gems", "tokens"]
const _SERVER_EARN_SYNC_INTERVAL_SEC := 20.0

signal item_collected(item_type: String, amount: int, total: int)
signal inventory_changed()
signal currency_changed(type: String, amount: int)

var _session_id: String = ""
var _pending_earned_currency: Dictionary = {}
var _wallet_sync_available := true
var _wallet_sync_in_flight := false
var _wallet_bootstrap_done := false
var _sync_timer_sec := 0.0
var _session_cap: int = 0
var _session_window_sec: int = 0

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	load_inventory()
	_build_session_id()
	_connect_nakama_signals()
	print("InventoryManager: Ready (loaded ", inventory.size(), " item types)")


func _normalize_item_type(item_type: String) -> String:
	var normalized := item_type.strip_edges().to_lower()
	if normalized == "coin" or normalized == "coins":
		return "gold"
	return normalized


func _is_currency(item_type: String) -> bool:
	return _CURRENCY_KEYS.has(_normalize_item_type(item_type))


func _process(delta: float) -> void:
	if _pending_earned_currency.is_empty():
		return
	_sync_timer_sec += delta
	if _sync_timer_sec < _SERVER_EARN_SYNC_INTERVAL_SEC:
		return
	_sync_timer_sec = 0.0
	_request_earned_sync(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_request_earned_sync(true)


func _build_session_id() -> void:
	var existing := _session_id.strip_edges()
	var base_id := "local"
	if NakamaManager:
		var user_id := String(NakamaManager.local_user_id).strip_edges()
		if not user_id.is_empty():
			base_id = "uid_" + user_id
		elif String(NakamaManager.device_id).strip_edges() != "":
			base_id = String(NakamaManager.device_id)
	if existing.begins_with(base_id + "_"):
		return
	_session_id = "%s_%d_%d" % [base_id, Time.get_unix_time_from_system(), randi()]


func _connect_nakama_signals() -> void:
	if not NakamaManager:
		return
	if NakamaManager.has_signal("authenticated") and not NakamaManager.authenticated.is_connected(_on_nakama_authenticated):
		NakamaManager.authenticated.connect(_on_nakama_authenticated)
	if NakamaManager.has_signal("connection_restored") and not NakamaManager.connection_restored.is_connected(_on_nakama_connection_restored):
		NakamaManager.connection_restored.connect(_on_nakama_connection_restored)
	if NakamaManager.is_authenticated:
		_on_nakama_authenticated({})


func _on_nakama_authenticated(_session: Dictionary) -> void:
	_build_session_id()
	_wallet_sync_available = true
	_request_wallet_bootstrap()


func _on_nakama_connection_restored() -> void:
	_request_wallet_bootstrap()
	_request_earned_sync(true)


func _request_wallet_bootstrap() -> void:
	if _wallet_sync_in_flight:
		return
	if not _can_use_wallet_rpc():
		return
	_wallet_sync_in_flight = true
	call_deferred("_run_wallet_bootstrap")


func _run_wallet_bootstrap() -> void:
	await _run_wallet_bootstrap_async()


func _run_wallet_bootstrap_async() -> void:
	var result: Dictionary = await NakamaManager.request_currency_wallet_snapshot()
	_wallet_sync_in_flight = false
	if not bool(result.get("ok", false)):
		_handle_wallet_rpc_failure(
			int(result.get("code", 0)),
			String(result.get("error", "wallet snapshot failed"))
		)
		return

	_wallet_bootstrap_done = true
	var wallet_variant: Variant = result.get("wallet", {})
	if wallet_variant is Dictionary:
		var wallet: Dictionary = wallet_variant
		for currency_type in _CURRENCY_KEYS:
			var server_amount: int = maxi(int(wallet.get(currency_type, 0)), 0)
			var local_amount: int = maxi(int(inventory.get(currency_type, 0)), 0)
			if local_amount > server_amount:
				_queue_earned_currency(currency_type, local_amount - server_amount)
		_reconcile_with_server_wallet(wallet_variant, true)
		_request_earned_sync(true)


func _can_use_wallet_rpc() -> bool:
	if not _wallet_sync_available:
		return false
	if not NakamaManager or not NakamaManager.has_method("commit_currency_session_deltas"):
		return false
	if not NakamaManager.is_authenticated:
		return false
	return true


func _handle_wallet_rpc_failure(code: int, error_text: String) -> void:
	# If the server runtime endpoint is not deployed yet, stay local-only.
	if code == 404 or code == 501:
		if _wallet_sync_available:
			push_warning("InventoryManager: Wallet RPC unavailable (%d). Falling back to local currency only for this session." % code)
		_wallet_sync_available = false
		return
	push_warning("InventoryManager: Wallet RPC failed (%d): %s" % [code, error_text])


func _queue_earned_currency(currency_type: String, amount: int) -> void:
	if amount <= 0:
		return
	var normalized := _normalize_item_type(currency_type)
	if not _is_currency(normalized):
		return
	var current_pending := int(_pending_earned_currency.get(normalized, 0))
	_pending_earned_currency[normalized] = current_pending + amount


func _apply_applied_deltas(pending: Dictionary, applied_variant: Variant) -> void:
	if not (applied_variant is Dictionary):
		return
	var applied: Dictionary = applied_variant
	for key_variant in applied.keys():
		var key: String = _normalize_item_type(String(key_variant))
		var applied_amount: int = maxi(int(applied[key_variant]), 0)
		var current_pending: int = maxi(int(pending.get(key, 0)), 0)
		var remaining: int = maxi(current_pending - applied_amount, 0)
		if remaining == 0:
			pending.erase(key)
		else:
			pending[key] = remaining


func _reconcile_with_server_wallet(wallet_variant: Variant, preserve_pending_earned: bool) -> void:
	if not (wallet_variant is Dictionary):
		return
	var wallet: Dictionary = wallet_variant
	var changed: bool = false

	for currency_type in _CURRENCY_KEYS:
		var server_amount: int = maxi(int(wallet.get(currency_type, 0)), 0)
		var pending_local: int = 0
		if preserve_pending_earned:
			pending_local = maxi(int(_pending_earned_currency.get(currency_type, 0)), 0)
		var target: int = server_amount + pending_local
		var current: int = int(inventory.get(currency_type, 0))
		if current != target:
			inventory[currency_type] = target
			changed = true

	if changed:
		inventory_changed.emit()
		for currency_type in _CURRENCY_KEYS:
			currency_changed.emit(currency_type, int(inventory.get(currency_type, 0)))
		_persist_to_save()


func _request_earned_sync(force: bool) -> void:
	if _pending_earned_currency.is_empty():
		return
	if _wallet_sync_in_flight:
		return
	if not _can_use_wallet_rpc():
		return
	_wallet_sync_in_flight = true
	call_deferred("_run_earned_sync", force)


func _run_earned_sync(force: bool) -> void:
	await _run_earned_sync_async(force)


func _run_earned_sync_async(force: bool) -> void:
	if _pending_earned_currency.is_empty():
		_wallet_sync_in_flight = false
		return

	var earned_snapshot := _pending_earned_currency.duplicate(true)
	var result: Dictionary = await NakamaManager.commit_currency_session_deltas(
		earned_snapshot,
		{},
		"earn_sync",
		false,
		_session_id
	)
	_wallet_sync_in_flight = false
	_sync_timer_sec = 0.0

	if not bool(result.get("ok", false)):
		_handle_wallet_rpc_failure(
			int(result.get("code", 0)),
			String(result.get("error", "currency sync failed"))
		)
		return

	_session_cap = int(result.get("cap", _session_cap))
	_session_window_sec = int(result.get("window_sec", _session_window_sec))
	_apply_applied_deltas(_pending_earned_currency, result.get("applied_earned", {}))
	_reconcile_with_server_wallet(result.get("wallet", {}), true)

	if force and not _pending_earned_currency.is_empty():
		# One immediate follow-up attempt when force-flushing (e.g. on reconnect/exit).
		_request_earned_sync(false)


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
	var had_explicit_currency_data := false
	var legacy_currency_snapshot: Dictionary = {}
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

		for currency_type in _CURRENCY_KEYS:
			legacy_currency_snapshot[currency_type] = maxi(int(inventory.get(currency_type, 0)), 0)

		if SaveManager.has_method("has_currency_data"):
			had_explicit_currency_data = bool(SaveManager.has_currency_data())

		if had_explicit_currency_data and SaveManager.has_method("get_all_currency"):
			var currency_map_variant: Variant = SaveManager.get_all_currency()
			if currency_map_variant is Dictionary:
				var currency_map: Dictionary = currency_map_variant
				var healed_currency_map: Dictionary = {}
				var needs_heal: bool = false
				for currency_type in _CURRENCY_KEYS:
					var legacy_amount: int = maxi(int(legacy_currency_snapshot.get(currency_type, 0)), 0)
					var map_amount: int = maxi(int(currency_map.get(currency_type, 0)), 0)
					var merged_amount: int = maxi(legacy_amount, map_amount)
					inventory[currency_type] = merged_amount
					healed_currency_map[currency_type] = merged_amount
					if merged_amount != map_amount:
						needs_heal = true
				if needs_heal and SaveManager.has_method("set_currency_map"):
					SaveManager.set_currency_map(healed_currency_map)

	# Ensure currency keys exist for UI consumers.
	for currency_type in _CURRENCY_KEYS:
		if not inventory.has(currency_type):
			inventory[currency_type] = 0

	# One-time legacy migration path: if save had inventory currency counts but no
	# explicit currency map yet, persist them now so future loads are stable.
	if SaveManager and not had_explicit_currency_data and SaveManager.has_method("set_currency_map"):
		var migrated_currency: Dictionary = {}
		for currency_type in _CURRENCY_KEYS:
			migrated_currency[currency_type] = int(inventory.get(currency_type, 0))
		SaveManager.set_currency_map(migrated_currency)

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
		if amount > 0:
			_queue_earned_currency(normalized_type, amount)
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


func spend_currency_authoritative(currency_type: String, amount: int, reason: String = "purchase") -> Dictionary:
	"""Spend currency with optional server wallet validation."""
	var normalized := _normalize_item_type(currency_type)
	if amount <= 0:
		return {"ok": true, "message": "Nothing to spend"}

	if get_currency(normalized) < amount:
		return {"ok": false, "message": "Insufficient funds"}

	if not _can_use_wallet_rpc():
		var local_ok := spend_currency(normalized, amount)
		return {
			"ok": local_ok,
			"message": "Spent locally" if local_ok else "Insufficient funds"
		}

	if _wallet_sync_in_flight:
		# Let any in-flight sync settle first so we do not overlap RPC updates.
		await get_tree().process_frame
		if _wallet_sync_in_flight:
			await get_tree().process_frame

	_wallet_sync_in_flight = true
	var earned_snapshot := _pending_earned_currency.duplicate(true)
	var spend_snapshot := {normalized: amount}
	var result: Dictionary = await NakamaManager.commit_currency_session_deltas(
		earned_snapshot,
		spend_snapshot,
		reason,
		true,
		_session_id
	)
	_wallet_sync_in_flight = false
	_sync_timer_sec = 0.0

	if not bool(result.get("ok", false)):
		_session_cap = int(result.get("cap", _session_cap))
		_session_window_sec = int(result.get("window_sec", _session_window_sec))
		_apply_applied_deltas(_pending_earned_currency, result.get("applied_earned", {}))
		_reconcile_with_server_wallet(result.get("wallet", {}), true)
		var error_code := int(result.get("code", 0))
		if error_code != 200:
			_handle_wallet_rpc_failure(
				error_code,
				String(result.get("error", "currency spend validation failed"))
			)
		return {"ok": false, "message": String(result.get("error", "Spend validation failed"))}

	_session_cap = int(result.get("cap", _session_cap))
	_session_window_sec = int(result.get("window_sec", _session_window_sec))
	_apply_applied_deltas(_pending_earned_currency, result.get("applied_earned", {}))

	var applied_spent_variant: Variant = result.get("applied_spent", {})
	var applied_spent_amount := 0
	if applied_spent_variant is Dictionary:
		applied_spent_amount = max(int((applied_spent_variant as Dictionary).get(normalized, 0)), 0)
	if applied_spent_amount < amount:
		_reconcile_with_server_wallet(result.get("wallet", {}), true)
		return {"ok": false, "message": "Insufficient server wallet balance"}

	_reconcile_with_server_wallet(result.get("wallet", {}), true)
	return {"ok": true, "message": "Spent with server validation"}
