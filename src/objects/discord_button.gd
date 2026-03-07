extends PokeableButton
class_name DiscordButton

## Discord invite URL
const DISCORD_URL := "https://discord.gg/f8bK6NRyCq"

@export var press_cooldown_sec: float = 1.0

var _next_press_msec: int = 0


func _ready() -> void:
	super._ready()
	# Connect to the pressed signal from PokeableButton
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	_open_discord()


func _open_discord() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_press_msec:
		return
	_next_press_msec = now_msec + int(press_cooldown_sec * 1000.0)

	print("DiscordButton: Opening Discord invite...")
	var err := OS.shell_open(DISCORD_URL)
	if err == OK:
		print("DiscordButton: Discord invite opened successfully")
	else:
		push_error("DiscordButton: Failed to open Discord invite. Error code: ", err)
