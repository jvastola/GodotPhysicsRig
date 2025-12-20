extends PanelContainer

# LLM Chat Terminal UI v2 - Streaming chat interface for LLM APIs
# Supports Claude, OpenAI, OpenRouter, Google Gemini with tool calling

signal message_sent(message: String)
signal response_received(response: String)
signal stream_chunk_received(chunk: String)
signal api_error(error: String)
signal tool_call_requested(tool_name: String, arguments: Dictionary)
signal tool_call_completed(tool_name: String, result: String)

enum Provider { CLAUDE, OPENAI, OPENROUTER, GEMINI, CUSTOM }
enum MessageRole { USER, ASSISTANT, SYSTEM, TOOL }
enum SystemPreset { ASSISTANT, CODER, GODOT_DEV, ANALYST, CREATIVE }

@export var max_messages: int = 100
@export var auto_scroll: bool = true
@export var font_size: int = 12

# UI References - Chat Tab
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer
@onready var chat_output: RichTextLabel = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ScrollContainer/ChatOutput
@onready var chat_scroll: ScrollContainer = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ScrollContainer
@onready var message_input: TextEdit = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/InputContainer/MessageInput
@onready var send_button: Button = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/InputContainer/SendButton
@onready var clear_chat_button: Button = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ButtonRow/ClearChatButton
@onready var copy_chat_button: Button = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ButtonRow/CopyChatButton
@onready var stop_button: Button = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ButtonRow/StopButton
@onready var history_button: Button = $MarginContainer/VBoxContainer/TabContainer/Chat/VBoxContainer/ButtonRow/HistoryButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusBar/StatusLabel
@onready var token_label: Label = $MarginContainer/VBoxContainer/StatusBar/TokenLabel

# UI References - History Tab
@onready var history_list: ItemList = $MarginContainer/VBoxContainer/TabContainer/History/VBoxContainer/HistoryList
@onready var load_history_button: Button = $MarginContainer/VBoxContainer/TabContainer/History/VBoxContainer/ButtonRow/LoadHistoryButton
@onready var delete_history_button: Button = $MarginContainer/VBoxContainer/TabContainer/History/VBoxContainer/ButtonRow/DeleteHistoryButton
@onready var export_history_button: Button = $MarginContainer/VBoxContainer/TabContainer/History/VBoxContainer/ButtonRow/ExportHistoryButton

# UI References - Debug Tab
@onready var debug_output: RichTextLabel = $MarginContainer/VBoxContainer/TabContainer/Debug/VBoxContainer/ScrollContainer/DebugOutput
@onready var clear_debug_button: Button = $MarginContainer/VBoxContainer/TabContainer/Debug/VBoxContainer/ButtonRow/ClearDebugButton
@onready var copy_debug_button: Button = $MarginContainer/VBoxContainer/TabContainer/Debug/VBoxContainer/ButtonRow/CopyDebugButton

# UI References - Settings Tab
@onready var provider_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ProviderRow/ProviderOption
@onready var api_key_input: LineEdit = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ApiKeyRow/ApiKeyInput
@onready var show_key_button: Button = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ApiKeyRow/ShowKeyButton
@onready var model_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ModelRow/ModelOption
@onready var refresh_models_button: Button = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ModelRow/RefreshModelsButton
@onready var endpoint_input: LineEdit = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/EndpointRow/EndpointInput
@onready var max_tokens_spin: SpinBox = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/MaxTokensRow/MaxTokensSpin
@onready var temperature_slider: HSlider = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/TemperatureRow/TemperatureSlider
@onready var temperature_value: Label = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/TemperatureRow/TemperatureValue
@onready var preset_option: OptionButton = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/PresetRow/PresetOption
@onready var system_prompt_input: TextEdit = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/SystemPromptContainer/SystemPromptInput
@onready var tools_enabled_check: CheckBox = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ToolsRow/ToolsEnabledCheck
@onready var save_settings_button: Button = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ButtonRow/SaveSettingsButton
@onready var test_connection_button: Button = $MarginContainer/VBoxContainer/TabContainer/Settings/ScrollContainer/VBoxContainer/ButtonRow/TestConnectionButton

# Chat state
var _messages: Array[Dictionary] = []
var _is_streaming: bool = false
var _current_response: String = ""
var _http_request: HTTPRequest = null
var _models_http_request: HTTPRequest = null
var _total_tokens_used: int = 0
var _pending_tool_calls: Array[Dictionary] = []
var _current_session_id: String = ""
var _auto_save_enabled: bool = true

# Debug log
var _debug_log: PackedStringArray = []
const MAX_DEBUG_LINES := 500

# History
const HISTORY_DIR := "user://llm_chat_history/"
const MAX_HISTORY_FILES := 50

# Settings
var _current_provider: Provider = Provider.CLAUDE
var _api_key: String = ""
var _model: String = "claude-sonnet-4-20250514"
var _custom_endpoint: String = ""
var _max_tokens: int = 4096
var _temperature: float = 0.7
var _system_prompt: String = ""
var _current_preset: SystemPreset = SystemPreset.CODER
var _tools_enabled: bool = true
var _available_models: Array[String] = []

# Provider configurations
const PROVIDER_CONFIGS := {
	Provider.CLAUDE: {
		"name": "Claude (Anthropic)",
		"endpoint": "https://api.anthropic.com/v1/messages",
		"models_endpoint": "",
		"default_model": "claude-sonnet-4-20250514",
		"models": ["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"],
		"supports_tools": true,
		"api_format": "claude"
	},
	Provider.OPENAI: {
		"name": "OpenAI",
		"endpoint": "https://api.openai.com/v1/chat/completions",
		"models_endpoint": "https://api.openai.com/v1/models",
		"default_model": "gpt-4o",
		"models": ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1-preview", "o1-mini"],
		"supports_tools": true,
		"api_format": "openai"
	},
	Provider.OPENROUTER: {
		"name": "OpenRouter",
		"endpoint": "https://openrouter.ai/api/v1/chat/completions",
		"models_endpoint": "https://openrouter.ai/api/v1/models",
		"default_model": "anthropic/claude-sonnet-4-20250514",
		"models": ["anthropic/claude-sonnet-4-20250514", "openai/gpt-4o", "google/gemini-pro-1.5", "meta-llama/llama-3.1-405b-instruct"],
		"supports_tools": true,
		"api_format": "openai"
	},
	Provider.GEMINI: {
		"name": "Google Gemini",
		"endpoint": "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
		"models_endpoint": "https://generativelanguage.googleapis.com/v1beta/models",
		"default_model": "gemini-1.5-pro",
		"models": ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.5-flash-8b", "gemini-2.0-flash-exp"],
		"supports_tools": true,
		"api_format": "gemini"
	},
	Provider.CUSTOM: {
		"name": "Custom (OpenAI Compatible)",
		"endpoint": "",
		"models_endpoint": "",
		"default_model": "",
		"models": [],
		"supports_tools": true,
		"api_format": "openai"
	}
}

# System prompt presets
const SYSTEM_PRESETS := {
	SystemPreset.ASSISTANT: {
		"name": "General Assistant",
		"prompt": "You are a helpful AI assistant. Provide clear, accurate, and concise responses."
	},
	SystemPreset.CODER: {
		"name": "Coding Assistant (Claude Code Style)",
		"prompt": """You are an expert coding assistant with capabilities similar to Claude Code and GitHub Copilot.

## CAPABILITIES
- Write, analyze, debug, and refactor code in any programming language
- Execute structured tool calls for file operations, searches, and commands
- Provide deterministic, reproducible solutions
- Follow best practices and coding standards

## BEHAVIOR GUIDELINES
1. **Be Precise**: Give exact code solutions, not vague suggestions
2. **Be Deterministic**: Same input should yield same output
3. **Show Your Work**: Explain reasoning before providing code
4. **Use Tools**: When available, use tool calls for file operations
5. **Verify**: Double-check code for syntax errors and edge cases

## TOOL USAGE
When tools are enabled, you can:
- `read_file`: Read file contents
- `write_file`: Create or overwrite files
- `edit_file`: Make targeted edits to existing files
- `search_files`: Search for patterns in codebase
- `run_command`: Execute shell commands
- `list_directory`: List directory contents

## OUTPUT FORMAT
- Use markdown code blocks with language tags
- Provide complete, runnable code snippets
- Include necessary imports and dependencies
- Add inline comments for complex logic

## BOUNDARIES
- Do not execute destructive operations without confirmation
- Do not access external systems beyond provided tools
- Do not make assumptions about file contents - read first
- Always preserve existing code style and conventions"""
	},
	SystemPreset.GODOT_DEV: {
		"name": "Godot Developer",
		"prompt": """You are an expert Godot 4 game developer assistant.

## EXPERTISE
- GDScript 2.0 syntax and best practices
- Godot 4 node system and scene architecture
- 2D and 3D game development patterns
- XR/VR development with OpenXR
- Performance optimization for mobile/Quest

## GUIDELINES
1. Use static typing in GDScript (var x: int = 0)
2. Follow Godot naming conventions (snake_case for functions/variables)
3. Prefer composition over inheritance
4. Use signals for decoupled communication
5. Optimize for mobile when relevant

## SAFE SCRIPT GENERATION (CRITICAL)
When creating scripts with create_scene or create_and_load_scene:
1. ALWAYS check if nodes exist before accessing them: `if mesh_instance and mesh_instance.mesh:`
2. Use @onready for node references: `@onready var mesh: MeshInstance3D = $MeshInstance3D`
3. NEVER set material_override on a MeshInstance3D without first ensuring it has a mesh
4. For color-changing cubes, create the mesh in _ready() first, then set material
5. Use null checks: `if node != null:`

## CORRECT PATTERN FOR COLORED MESH:
```gdscript
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
    # Ensure mesh exists before setting material
    if mesh_instance and mesh_instance.mesh:
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color.RED
        mesh_instance.material_override = mat
```

## TOOL USAGE
Use available tools to:
- Read and analyze existing scripts
- Create new scenes with create_scene or create_and_load_scene
- Use children array to add MeshInstance3D with mesh and color properties
- The tool handles mesh/material creation in TSCN - scripts should only modify existing nodes"""
	},
	SystemPreset.ANALYST: {
		"name": "Data Analyst",
		"prompt": """You are a data analysis assistant focused on clear, actionable insights.

## CAPABILITIES
- Statistical analysis and interpretation
- Data visualization recommendations
- SQL query optimization
- Python/pandas data manipulation
- Report generation

## APPROACH
1. Understand the question before analyzing
2. Validate data quality assumptions
3. Use appropriate statistical methods
4. Present findings clearly with visualizations
5. Highlight limitations and caveats"""
	},
	SystemPreset.CREATIVE: {
		"name": "Creative Writer",
		"prompt": """You are a creative writing assistant.

## CAPABILITIES
- Story development and plotting
- Character creation and dialogue
- World-building and lore
- Editing and style refinement
- Multiple genres and formats

## APPROACH
1. Understand the creative vision
2. Maintain consistent voice and tone
3. Show, don't tell
4. Balance description with action
5. Respect the author's style"""
	}
}

# Available tools definition
const AVAILABLE_TOOLS := [
	{
		"name": "read_file",
		"description": "Read the contents of a file at the specified path",
		"parameters": {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "Path to the file to read (user:// or res://)"}
			},
			"required": ["path"]
		}
	},
	{
		"name": "write_file",
		"description": "Write content to a file, creating it if it doesn't exist. Only works in user:// directory.",
		"parameters": {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "Path to the file to write (must be user://)"},
				"content": {"type": "string", "description": "Content to write to the file"}
			},
			"required": ["path", "content"]
		}
	},
	{
		"name": "list_directory",
		"description": "List contents of a directory",
		"parameters": {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "Path to the directory to list"}
			},
			"required": ["path"]
		}
	},
	{
		"name": "search_files",
		"description": "Search for a pattern in files",
		"parameters": {
			"type": "object",
			"properties": {
				"pattern": {"type": "string", "description": "Pattern to search for"},
				"path": {"type": "string", "description": "Directory to search in"}
			},
			"required": ["pattern"]
		}
	},
	{
		"name": "get_scene_tree",
		"description": "Get the current scene tree structure showing all nodes and their paths",
		"parameters": {
			"type": "object",
			"properties": {
				"max_depth": {"type": "integer", "description": "Maximum depth to traverse (default 5)"}
			},
			"required": []
		}
	},
	{
		"name": "remove_node",
		"description": "Remove a node from the scene tree by its path",
		"parameters": {
			"type": "object",
			"properties": {
				"node_path": {"type": "string", "description": "Path to the node to remove (e.g., '/root/Main/MyNode')"}
			},
			"required": ["node_path"]
		}
	},
	{
		"name": "create_scene",
		"description": "Create a complete TSCN scene file with nodes and optional attached GDScript. Validates the scene before saving. IMPORTANT: Use children array to define MeshInstance3D nodes - they auto-get BoxMesh and material. Scripts should reference these child nodes.",
		"parameters": {
			"type": "object",
			"properties": {
				"scene_name": {"type": "string", "description": "Name for the scene (without .tscn extension)"},
				"root_type": {"type": "string", "description": "Root node type: Node3D, RigidBody3D, StaticBody3D, Area3D, CharacterBody3D, Node2D, Control, etc."},
				"root_name": {"type": "string", "description": "Name for the root node"},
				"script_content": {"type": "string", "description": "Optional GDScript code to attach to the root node. Must be valid GDScript starting with 'extends'. Reference children via $ChildName."},
				"children": {
					"type": "array",
					"description": "REQUIRED for visible meshes. Array of child nodes: [{type: 'MeshInstance3D', name: 'CubeMesh', properties: {mesh: 'box', color: [1,0,0], position: [0,1,0]}}]. MeshInstance3D auto-gets BoxMesh if mesh not specified."
				}
			},
			"required": ["scene_name", "root_type", "root_name"]
		}
	},
	{
		"name": "create_and_load_scene",
		"description": "Create a scene and immediately load it. IMPORTANT: For visible cubes, MUST include children array with MeshInstance3D. Example: children=[{type:'MeshInstance3D', name:'Cube', properties:{mesh:'box', color:[1,0,0]}}]",
		"parameters": {
			"type": "object",
			"properties": {
				"scene_name": {"type": "string", "description": "Name for the scene (without .tscn extension)"},
				"root_type": {"type": "string", "description": "Root node type: Node3D, RigidBody3D, etc."},
				"root_name": {"type": "string", "description": "Name for the root node"},
				"script_content": {"type": "string", "description": "Optional GDScript. Reference mesh child via $ChildName. The mesh already exists - just modify material."},
				"children": {
					"type": "array",
					"description": "REQUIRED for meshes! Example: [{type:'MeshInstance3D', name:'CubeMesh', properties:{mesh:'box', color:[1,0,0], position:[0,1,0]}}]"
				},
				"parent_path": {"type": "string", "description": "Path to parent node. Default: /root/LegalGate/MainScene21 for visibility."},
				"position": {
					"type": "array",
					"description": "Position [x, y, z] where to place the loaded scene"
				}
			},
			"required": ["scene_name", "root_type", "root_name"]
		}
	},
	{
		"name": "validate_gdscript",
		"description": "Validate GDScript code for syntax errors without executing it. Returns OK or error details.",
		"parameters": {
			"type": "object",
			"properties": {
				"code": {"type": "string", "description": "GDScript code to validate"}
			},
			"required": ["code"]
		}
	},
	{
		"name": "load_scene",
		"description": "Load an existing TSCN scene file into the current scene tree.",
		"parameters": {
			"type": "object",
			"properties": {
				"path": {"type": "string", "description": "Path to the .tscn scene file (user:// or res://)"},
				"parent_path": {"type": "string", "description": "Path to parent node. Empty = current scene root."},
				"position": {"type": "array", "description": "Optional position [x, y, z] for 3D scenes"}
			},
			"required": ["path"]
		}
	}
]

# Colors
const USER_COLOR := Color(0.4, 0.8, 1.0)
const ASSISTANT_COLOR := Color(0.5, 1.0, 0.6)
const SYSTEM_COLOR := Color(0.8, 0.8, 0.5)
const ERROR_COLOR := Color(1.0, 0.4, 0.4)
const TOOL_COLOR := Color(0.9, 0.6, 1.0)
const TIMESTAMP_COLOR := Color(0.5, 0.5, 0.55)

static var instance: PanelContainer = null


func _ready() -> void:
	instance = self
	_setup_ui()
	_load_settings()
	_update_status("Ready")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null
		_cleanup_http()


func _setup_ui() -> void:
	# Chat output setup
	if chat_output:
		chat_output.bbcode_enabled = true
		chat_output.scroll_following = auto_scroll
		chat_output.add_theme_font_size_override("normal_font_size", font_size)
		chat_output.selection_enabled = true
	
	# Button connections
	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if clear_chat_button:
		clear_chat_button.pressed.connect(_on_clear_chat_pressed)
	if copy_chat_button:
		copy_chat_button.pressed.connect(_on_copy_chat_pressed)
	if stop_button:
		stop_button.pressed.connect(_on_stop_pressed)
		stop_button.disabled = true
	
	# Message input
	if message_input:
		message_input.placeholder_text = "Type your message... (Ctrl+Enter to send)"
		message_input.gui_input.connect(_on_message_input_gui)
	
	# Provider selection
	if provider_option:
		provider_option.clear()
		provider_option.add_item("Claude (Anthropic)", Provider.CLAUDE)
		provider_option.add_item("OpenAI", Provider.OPENAI)
		provider_option.add_item("OpenRouter", Provider.OPENROUTER)
		provider_option.add_item("Google Gemini", Provider.GEMINI)
		provider_option.add_item("Custom", Provider.CUSTOM)
		provider_option.item_selected.connect(_on_provider_changed)
	
	# API key
	if show_key_button:
		show_key_button.pressed.connect(_toggle_api_key_visibility)
	if api_key_input:
		api_key_input.secret = true
		api_key_input.placeholder_text = "Enter your API key..."
	
	# Model selection
	if refresh_models_button:
		refresh_models_button.pressed.connect(_fetch_models)
	
	# Temperature
	if temperature_slider:
		temperature_slider.min_value = 0.0
		temperature_slider.max_value = 2.0
		temperature_slider.step = 0.1
		temperature_slider.value = _temperature
		temperature_slider.value_changed.connect(_on_temperature_changed)
	
	# Max tokens
	if max_tokens_spin:
		max_tokens_spin.min_value = 100
		max_tokens_spin.max_value = 200000
		max_tokens_spin.step = 100
		max_tokens_spin.value = _max_tokens
	
	# System prompt presets
	if preset_option:
		preset_option.clear()
		preset_option.add_item("General Assistant", SystemPreset.ASSISTANT)
		preset_option.add_item("Coding Assistant", SystemPreset.CODER)
		preset_option.add_item("Godot Developer", SystemPreset.GODOT_DEV)
		preset_option.add_item("Data Analyst", SystemPreset.ANALYST)
		preset_option.add_item("Creative Writer", SystemPreset.CREATIVE)
		preset_option.item_selected.connect(_on_preset_changed)
	
	# Settings buttons
	if save_settings_button:
		save_settings_button.pressed.connect(_save_settings)
	if test_connection_button:
		test_connection_button.pressed.connect(_test_connection)
	
	# History buttons
	if history_button:
		history_button.pressed.connect(_on_history_button_pressed)
	if load_history_button:
		load_history_button.pressed.connect(_on_load_history_pressed)
	if delete_history_button:
		delete_history_button.pressed.connect(_on_delete_history_pressed)
	if export_history_button:
		export_history_button.pressed.connect(_on_export_history_pressed)
	if history_list:
		history_list.item_selected.connect(_on_history_item_selected)
	
	# Debug tab buttons
	if clear_debug_button:
		clear_debug_button.pressed.connect(_on_clear_debug_pressed)
	if copy_debug_button:
		copy_debug_button.pressed.connect(_on_copy_debug_pressed)
	
	# Create HTTP request nodes
	_http_request = HTTPRequest.new()
	_http_request.use_threads = true
	_http_request.timeout = 120.0
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	_models_http_request = HTTPRequest.new()
	_models_http_request.use_threads = true
	_models_http_request.timeout = 30.0
	add_child(_models_http_request)
	_models_http_request.request_completed.connect(_on_models_request_completed)
	
	# Ensure history directory exists
	_ensure_history_dir()
	
	# Start new session
	_start_new_session()
	
	# Welcome message
	_add_system_message("Welcome to LLM Chat Terminal v2!")
	_add_system_message("Configure your API key in Settings to get started.")


func _on_message_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			_on_send_pressed()
			get_viewport().set_input_as_handled()


func _on_send_pressed() -> void:
	if not message_input or message_input.text.strip_edges().is_empty():
		return
	if _is_streaming:
		_add_system_message("Please wait for the current response to complete.")
		return
	if _api_key.is_empty():
		_add_error_message("API key not configured. Set it in Settings tab.")
		return
	
	var user_message := message_input.text.strip_edges()
	message_input.text = ""
	_add_user_message(user_message)
	_send_to_llm(user_message)


func _on_clear_chat_pressed() -> void:
	# Save current conversation before clearing
	_auto_save_conversation()
	
	_messages.clear()
	_current_response = ""
	_total_tokens_used = 0
	_pending_tool_calls.clear()
	
	# Start a new session
	_start_new_session()
	
	_refresh_chat_display()
	_add_system_message("Chat cleared. Previous conversation saved to history.")
	_update_token_count()


func _on_copy_chat_pressed() -> void:
	var text := ""
	for msg in _messages:
		var role_name := _get_role_name(msg.role)
		text += "[%s] %s:\n%s\n\n" % [msg.timestamp, role_name, msg.content]
	DisplayServer.clipboard_set(text)
	_add_system_message("Chat copied to clipboard.")


func _on_stop_pressed() -> void:
	if _is_streaming:
		_cancel_stream()
		_add_system_message("Response generation stopped.")


func _on_provider_changed(index: int) -> void:
	_current_provider = provider_option.get_item_id(index) as Provider
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	
	# Update model dropdown with default models
	_update_model_dropdown(config.models)
	if model_option and config.default_model:
		_select_model(config.default_model)
	
	# Update endpoint
	if endpoint_input:
		endpoint_input.text = config.endpoint
		endpoint_input.editable = (_current_provider == Provider.CUSTOM)
	
	_update_status("Provider: " + config.name)


func _on_temperature_changed(value: float) -> void:
	_temperature = value
	if temperature_value:
		temperature_value.text = "%.1f" % value


func _on_preset_changed(index: int) -> void:
	_current_preset = preset_option.get_item_id(index) as SystemPreset
	var preset: Dictionary = SYSTEM_PRESETS[_current_preset]
	_system_prompt = preset.prompt
	if system_prompt_input:
		system_prompt_input.text = _system_prompt


func _toggle_api_key_visibility() -> void:
	if api_key_input:
		api_key_input.secret = not api_key_input.secret
		if show_key_button:
			show_key_button.text = "Hide" if not api_key_input.secret else "Show"


func _get_role_name(role: MessageRole) -> String:
	match role:
		MessageRole.USER: return "You"
		MessageRole.ASSISTANT: return "Assistant"
		MessageRole.SYSTEM: return "System"
		MessageRole.TOOL: return "Tool"
	return "Unknown"


# ============================================================================
# MODEL FETCHING
# ============================================================================

func _fetch_models() -> void:
	if _api_key.is_empty():
		_add_error_message("Set API key first to fetch models.")
		return
	
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var models_endpoint: String = config.get("models_endpoint", "")
	
	if models_endpoint.is_empty():
		_add_system_message("This provider doesn't support model listing. Using defaults.")
		_update_model_dropdown(config.models)
		return
	
	_update_status("Fetching models...")
	
	var headers := _build_auth_headers()
	
	# Gemini uses query param for API key
	if _current_provider == Provider.GEMINI:
		models_endpoint += "?key=" + _api_key
		headers = PackedStringArray(["Content-Type: application/json"])
	
	var error := _models_http_request.request(models_endpoint, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_add_error_message("Failed to fetch models: " + str(error))


func _on_models_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_add_error_message("Failed to fetch models (code: %d)" % response_code)
		_update_status("Ready")
		return
	
	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(response_text) != OK:
		_add_error_message("Failed to parse models response")
		_update_status("Ready")
		return
	
	var data: Dictionary = json.data
	var models: Array[String] = []
	
	match _current_provider:
		Provider.OPENAI:
			if data.has("data"):
				for model_data in data.data:
					var model_id: String = model_data.get("id", "")
					if model_id.begins_with("gpt") or model_id.begins_with("o1"):
						models.append(model_id)
		Provider.OPENROUTER:
			if data.has("data"):
				for model_data in data.data:
					var model_id: String = model_data.get("id", "")
					models.append(model_id)
		Provider.GEMINI:
			if data.has("models"):
				for model_data in data.models:
					var model_name: String = model_data.get("name", "")
					if model_name.begins_with("models/gemini"):
						models.append(model_name.replace("models/", ""))
	
	if models.is_empty():
		var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
		models.assign(config.models)
	
	models.sort()
	_available_models = models
	_update_model_dropdown(models)
	_add_system_message("Loaded %d models." % models.size())
	_update_status("Ready")


func _update_model_dropdown(models: Array) -> void:
	if not model_option:
		return
	
	var current_model := _model
	model_option.clear()
	
	for model_name in models:
		model_option.add_item(model_name)
	
	_select_model(current_model)


func _select_model(model_name: String) -> void:
	if not model_option:
		return
	
	for i in model_option.item_count:
		if model_option.get_item_text(i) == model_name:
			model_option.select(i)
			_model = model_name
			return
	
	# If not found, select first item
	if model_option.item_count > 0:
		model_option.select(0)
		_model = model_option.get_item_text(0)


# ============================================================================
# MESSAGE HANDLING
# ============================================================================

func _add_user_message(content: String) -> void:
	_messages.append({
		"role": MessageRole.USER,
		"content": content,
		"timestamp": Time.get_time_string_from_system()
	})
	_trim_messages()
	_refresh_chat_display()
	message_sent.emit(content)


func _add_assistant_message(content: String) -> void:
	_messages.append({
		"role": MessageRole.ASSISTANT,
		"content": content,
		"timestamp": Time.get_time_string_from_system()
	})
	_trim_messages()
	_refresh_chat_display()
	response_received.emit(content)
	# Auto-save after assistant response
	_auto_save_conversation()


func _add_system_message(content: String) -> void:
	_messages.append({
		"role": MessageRole.SYSTEM,
		"content": content,
		"timestamp": Time.get_time_string_from_system()
	})
	_trim_messages()
	_refresh_chat_display()


func _add_error_message(content: String) -> void:
	_messages.append({
		"role": MessageRole.SYSTEM,
		"content": "ERROR: " + content,
		"timestamp": Time.get_time_string_from_system()
	})
	_trim_messages()
	_refresh_chat_display()
	api_error.emit(content)


func _trim_messages() -> void:
	while _messages.size() > max_messages:
		_messages.pop_front()


func _refresh_chat_display() -> void:
	if not chat_output:
		return
	
	var bbcode := ""
	
	for msg in _messages:
		var color: Color
		var role_name: String = _get_role_name(msg.role)
		
		match msg.role:
			MessageRole.USER:
				color = USER_COLOR
			MessageRole.ASSISTANT:
				color = ASSISTANT_COLOR
			MessageRole.SYSTEM:
				color = SYSTEM_COLOR
				if msg.content.begins_with("ERROR:"):
					color = ERROR_COLOR
			MessageRole.TOOL:
				color = TOOL_COLOR
		
		var timestamp_str := "[color=#%s][%s][/color] " % [TIMESTAMP_COLOR.to_html(false), msg.timestamp]
		var role_str := "[color=#%s][b]%s:[/b][/color]\n" % [color.to_html(false), role_name]
		var content_str := _escape_bbcode(msg.content) + "\n\n"
		
		bbcode += timestamp_str + role_str + content_str
	
	if _is_streaming:
		bbcode += "[color=#%s]▌[/color]" % [ASSISTANT_COLOR.to_html(false)]
	
	chat_output.text = bbcode
	
	if auto_scroll and chat_scroll:
		await get_tree().process_frame
		chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")


# ============================================================================
# LLM API COMMUNICATION
# ============================================================================

func _send_to_llm(_user_message: String) -> void:
	_is_streaming = true
	_current_response = ""
	
	if stop_button:
		stop_button.disabled = false
	if send_button:
		send_button.disabled = true
	
	_update_status("Sending request...")
	
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var endpoint: String = config.endpoint
	
	if _current_provider == Provider.CUSTOM:
		endpoint = _custom_endpoint
	elif _current_provider == Provider.GEMINI:
		endpoint = endpoint.replace("{model}", _model) + "?key=" + _api_key
	
	if endpoint.is_empty():
		_add_error_message("No endpoint configured.")
		_finish_streaming()
		return
	
	var headers := _build_auth_headers()
	var body := _build_request_body()
	var json_body := JSON.stringify(body)
	
	var error := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		_add_error_message("Failed to send request: " + str(error))
		_finish_streaming()


func _build_auth_headers() -> PackedStringArray:
	match _current_provider:
		Provider.CLAUDE:
			return PackedStringArray([
				"Content-Type: application/json",
				"x-api-key: " + _api_key,
				"anthropic-version: 2023-06-01"
			])
		Provider.GEMINI:
			return PackedStringArray(["Content-Type: application/json"])
		_:  # OpenAI, OpenRouter, Custom
			var headers := PackedStringArray([
				"Content-Type: application/json",
				"Authorization: Bearer " + _api_key
			])
			if _current_provider == Provider.OPENROUTER:
				headers.append("HTTP-Referer: godot-llm-chat")
				headers.append("X-Title: Godot LLM Chat")
			return headers


func _build_request_body() -> Dictionary:
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var api_format: String = config.get("api_format", "openai")
	
	match api_format:
		"claude":
			return _build_claude_body()
		"gemini":
			return _build_gemini_body()
		_:
			return _build_openai_body()


func _build_claude_body() -> Dictionary:
	var messages_array: Array = []
	
	for msg in _messages:
		if msg.role == MessageRole.USER:
			messages_array.append({"role": "user", "content": msg.content})
		elif msg.role == MessageRole.ASSISTANT:
			# Check if this is a tool use response (stored as raw content blocks)
			if msg.has("raw_content"):
				messages_array.append({"role": "assistant", "content": msg.raw_content})
			else:
				messages_array.append({"role": "assistant", "content": msg.content})
		elif msg.role == MessageRole.TOOL:
			# Tool results must reference the tool_use_id from the previous assistant message
			messages_array.append({
				"role": "user",
				"content": [{"type": "tool_result", "tool_use_id": msg.get("tool_use_id", ""), "content": msg.get("result", msg.content)}]
			})
	
	var body := {
		"model": _model,
		"max_tokens": _max_tokens,
		"messages": messages_array
	}
	
	if not _system_prompt.is_empty():
		body["system"] = _system_prompt
	
	if _tools_enabled:
		body["tools"] = _build_claude_tools()
	
	return body


func _build_openai_body() -> Dictionary:
	var messages_array: Array = []
	
	if not _system_prompt.is_empty():
		messages_array.append({"role": "system", "content": _system_prompt})
	
	for msg in _messages:
		if msg.role == MessageRole.USER:
			messages_array.append({"role": "user", "content": msg.content})
		elif msg.role == MessageRole.ASSISTANT:
			if msg.has("tool_calls_data"):
				# Assistant message with tool calls
				messages_array.append({
					"role": "assistant",
					"content": msg.content if msg.content else null,
					"tool_calls": msg.tool_calls_data
				})
			else:
				messages_array.append({"role": "assistant", "content": msg.content})
		elif msg.role == MessageRole.TOOL:
			# Tool result for OpenAI format
			messages_array.append({
				"role": "tool",
				"tool_call_id": msg.get("tool_use_id", ""),
				"content": msg.get("result", msg.content)
			})
	
	var body := {
		"model": _model,
		"max_tokens": _max_tokens,
		"temperature": _temperature,
		"messages": messages_array
	}
	
	if _tools_enabled:
		body["tools"] = _build_openai_tools()
	
	return body


func _build_gemini_body() -> Dictionary:
	var contents: Array = []
	
	for msg in _messages:
		var role := "user" if msg.role == MessageRole.USER else "model"
		if msg.role == MessageRole.SYSTEM:
			continue
		contents.append({
			"role": role,
			"parts": [{"text": msg.content}]
		})
	
	var body := {
		"contents": contents,
		"generationConfig": {
			"maxOutputTokens": _max_tokens,
			"temperature": _temperature
		}
	}
	
	if not _system_prompt.is_empty():
		body["systemInstruction"] = {"parts": [{"text": _system_prompt}]}
	
	if _tools_enabled:
		body["tools"] = [{"functionDeclarations": _build_gemini_tools()}]
	
	return body


func _build_claude_tools() -> Array:
	var tools: Array = []
	for tool in AVAILABLE_TOOLS:
		tools.append({
			"name": tool.name,
			"description": tool.description,
			"input_schema": tool.parameters
		})
	return tools


func _build_openai_tools() -> Array:
	var tools: Array = []
	for tool in AVAILABLE_TOOLS:
		tools.append({
			"type": "function",
			"function": {
				"name": tool.name,
				"description": tool.description,
				"parameters": tool.parameters
			}
		})
	return tools


func _build_gemini_tools() -> Array:
	var tools: Array = []
	for tool in AVAILABLE_TOOLS:
		tools.append({
			"name": tool.name,
			"description": tool.description,
			"parameters": tool.parameters
		})
	return tools


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_add_error_message("Request failed: " + str(result))
		_finish_streaming()
		return
	
	if response_code != 200:
		var error_text := body.get_string_from_utf8()
		_add_error_message("API error (%d): %s" % [response_code, error_text.left(500)])
		_finish_streaming()
		return
	
	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(response_text) != OK:
		_add_error_message("Failed to parse response")
		_finish_streaming()
		return
	
	var data: Dictionary = json.data
	
	# Check for tool calls
	var tool_calls := _extract_tool_calls(data)
	if not tool_calls.is_empty():
		_handle_tool_calls(tool_calls, data)
		return
	
	var content := _extract_response_content(data)
	
	if content.is_empty():
		_add_error_message("Empty response from API")
	else:
		_add_assistant_message(content)
		_update_token_usage(data)
	
	_finish_streaming()


func _extract_response_content(data: Dictionary) -> String:
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var api_format: String = config.get("api_format", "openai")
	
	match api_format:
		"claude":
			if data.has("content") and data.content is Array:
				for block in data.content:
					if block.get("type") == "text":
						return block.get("text", "")
		"gemini":
			if data.has("candidates") and data.candidates is Array and data.candidates.size() > 0:
				var candidate: Dictionary = data.candidates[0]
				if candidate.has("content") and candidate.content.has("parts"):
					for part in candidate.content.parts:
						if part.has("text"):
							return part.text
		_:  # OpenAI format
			if data.has("choices") and data.choices is Array and data.choices.size() > 0:
				var choice: Dictionary = data.choices[0]
				if choice.has("message") and choice.message.has("content"):
					return choice.message.content if choice.message.content else ""
	
	return ""


func _extract_tool_calls(data: Dictionary) -> Array:
	var tool_calls: Array = []
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var api_format: String = config.get("api_format", "openai")
	
	match api_format:
		"claude":
			if data.has("content") and data.content is Array:
				for block in data.content:
					if block.get("type") == "tool_use":
						tool_calls.append({
							"id": block.get("id", ""),
							"name": block.get("name", ""),
							"arguments": block.get("input", {})
						})
		"gemini":
			if data.has("candidates") and data.candidates is Array and data.candidates.size() > 0:
				var candidate: Dictionary = data.candidates[0]
				if candidate.has("content") and candidate.content.has("parts"):
					for part in candidate.content.parts:
						if part.has("functionCall"):
							var fc: Dictionary = part.functionCall
							tool_calls.append({
								"id": fc.get("name", ""),
								"name": fc.get("name", ""),
								"arguments": fc.get("args", {})
							})
		_:  # OpenAI format
			if data.has("choices") and data.choices is Array and data.choices.size() > 0:
				var choice: Dictionary = data.choices[0]
				if choice.has("message") and choice.message.has("tool_calls"):
					for tc in choice.message.tool_calls:
						var func_data: Dictionary = tc.get("function", {})
						var args_str: String = func_data.get("arguments", "{}")
						var args_json := JSON.new()
						var args := {}
						if args_json.parse(args_str) == OK:
							args = args_json.data
						tool_calls.append({
							"id": tc.get("id", ""),
							"name": func_data.get("name", ""),
							"arguments": args
						})
	
	return tool_calls


func _handle_tool_calls(tool_calls: Array, response_data: Dictionary) -> void:
	# Store the assistant's response with tool_use blocks
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var api_format: String = config.get("api_format", "openai")
	
	if api_format == "claude":
		# Store the raw assistant response with tool_use blocks for Claude
		var raw_content: Array = response_data.get("content", [])
		var text_content := ""
		for block in raw_content:
			if block.get("type") == "text":
				text_content += block.get("text", "")
		
		_messages.append({
			"role": MessageRole.ASSISTANT,
			"content": text_content if text_content else "(using tools...)",
			"timestamp": Time.get_time_string_from_system(),
			"raw_content": raw_content
		})
		_refresh_chat_display()
	elif api_format == "openai":
		# Store OpenAI format tool calls
		if response_data.has("choices") and response_data.choices.size() > 0:
			var choice: Dictionary = response_data.choices[0]
			if choice.has("message"):
				var msg_data: Dictionary = choice.message
				var openai_tool_calls: Array = []
				if msg_data.has("tool_calls"):
					for tc in msg_data.tool_calls:
						openai_tool_calls.append({
							"id": tc.get("id", ""),
							"type": "function",
							"function": tc.get("function", {})
						})
				
				_messages.append({
					"role": MessageRole.ASSISTANT,
					"content": msg_data.get("content", "") if msg_data.get("content") else "(using tools...)",
					"timestamp": Time.get_time_string_from_system(),
					"tool_calls_data": openai_tool_calls
				})
				_refresh_chat_display()
	
	# Execute each tool and store results
	for tc in tool_calls:
		var tool_name: String = tc.name
		var tool_id: String = tc.id
		var arguments: Dictionary = tc.arguments
		
		_add_system_message("Executing tool: %s" % tool_name)
		tool_call_requested.emit(tool_name, arguments)
		
		var result := _execute_tool(tool_name, arguments)
		
		# Store tool result with proper ID reference
		_messages.append({
			"role": MessageRole.TOOL,
			"content": "[%s]\n%s" % [tool_name, result],
			"timestamp": Time.get_time_string_from_system(),
			"tool_name": tool_name,
			"tool_use_id": tool_id,
			"result": result
		})
		_refresh_chat_display()
		tool_call_completed.emit(tool_name, result)
	
	_update_token_usage(response_data)
	_finish_streaming()
	
	# Auto-continue after tool execution to get the LLM's response
	await get_tree().create_timer(0.3).timeout
	_continue_after_tools()


func _execute_tool(tool_name: String, arguments: Dictionary) -> String:
	# Wrap all tool execution in error handling to prevent crashes
	_log_debug("Executing tool: %s with args: %s" % [tool_name, str(arguments).left(200)])
	var result := _execute_tool_internal(tool_name, arguments)
	_log_debug("Tool result: %s" % result.left(200))
	return result


func _execute_tool_internal(tool_name: String, arguments: Dictionary) -> String:
	match tool_name:
		"read_file":
			return _tool_read_file(arguments.get("path", ""))
		"write_file":
			return _tool_write_file(arguments.get("path", ""), arguments.get("content", ""))
		"list_directory":
			return _tool_list_directory(arguments.get("path", ""))
		"search_files":
			return _tool_search_files(arguments.get("pattern", ""), arguments.get("path", "user://"))
		"load_scene":
			return _tool_load_scene_safe(arguments.get("path", ""), arguments.get("parent_path", ""), arguments.get("position", []))
		"remove_node":
			return _tool_remove_node(arguments.get("node_path", ""))
		"get_scene_tree":
			return _tool_get_scene_tree(arguments.get("max_depth", 5))
		"create_scene":
			return _tool_create_scene(
				arguments.get("scene_name", ""),
				arguments.get("root_type", "Node3D"),
				arguments.get("root_name", "Root"),
				arguments.get("script_content", ""),
				arguments.get("children", [])
			)
		"create_and_load_scene":
			return _tool_create_and_load_scene_safe(
				arguments.get("scene_name", ""),
				arguments.get("root_type", "Node3D"),
				arguments.get("root_name", "Root"),
				arguments.get("script_content", ""),
				arguments.get("children", []),
				arguments.get("parent_path", ""),
				arguments.get("position", [])
			)
		"validate_gdscript":
			return _tool_validate_gdscript(arguments.get("code", ""))
	return "Unknown tool: " + tool_name


# Safe wrapper for load_scene that catches runtime errors
func _tool_load_scene_safe(path: String, parent_path: String, position_arr: Array = []) -> String:
	# Validate the scene file first before loading
	var validation_result := _validate_scene_file(path)
	if not validation_result.is_empty():
		_log_debug("Scene validation failed: " + validation_result)
		return "Error: " + validation_result
	
	return _tool_load_scene(path, parent_path, position_arr)


# Safe wrapper for create_and_load that validates everything first
func _tool_create_and_load_scene_safe(scene_name: String, root_type: String, root_name: String, script_content: String, children: Array, parent_path: String, position_arr: Array) -> String:
	# First create the scene (this already validates the script)
	var create_result := _tool_create_scene(scene_name, root_type, root_name, script_content, children)
	if create_result.begins_with("Error"):
		_log_debug("Scene creation failed: " + create_result)
		return create_result
	
	# Validate the created scene can be loaded safely
	var scene_path := "user://" + scene_name + ".tscn"
	var validation_result := _validate_scene_file(scene_path)
	if not validation_result.is_empty():
		_log_debug("Created scene validation failed: " + validation_result)
		return create_result + "\nWarning: Scene created but validation failed: " + validation_result
	
	# Load with error catching
	var load_result := _tool_load_scene(scene_path, parent_path, position_arr)
	
	return create_result + "\n" + load_result


# Validate a scene file before loading
func _validate_scene_file(path: String) -> String:
	if path.is_empty():
		return "No scene path provided"
	
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return "Scene file not found: " + path
	
	# Try to load the resource
	var scene_resource = load(path)
	if not scene_resource:
		return "Failed to load scene resource: " + path
	
	if not scene_resource is PackedScene:
		return "File is not a valid PackedScene: " + path
	
	# Check if the scene has an attached script and validate it
	var packed_scene: PackedScene = scene_resource
	var state := packed_scene.get_state()
	
	for i in state.get_node_count():
		for j in state.get_node_property_count(i):
			var prop_name := state.get_node_property_name(i, j)
			if prop_name == "script":
				var script_res = state.get_node_property_value(i, j)
				if script_res is GDScript:
					var gdscript: GDScript = script_res
					# Check if script has errors by trying to reload
					var err := gdscript.reload()
					if err != OK:
						return "Script attached to node has errors (code: %d)" % err
	
	return ""  # Empty = valid


# Debug logging to chat and debug tab
func _log_debug(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var log_entry := "[%s] %s" % [timestamp, message]
	
	# Add to debug log array
	_debug_log.append(log_entry)
	while _debug_log.size() > MAX_DEBUG_LINES:
		_debug_log.remove_at(0)
	
	# Update debug output if available
	_refresh_debug_output()
	
	# Also print to Godot console
	push_warning("[LLM Chat] " + message)


func _refresh_debug_output() -> void:
	if not debug_output:
		return
	
	var bbcode := ""
	for line in _debug_log:
		var color := "#888888"
		if line.contains("Error") or line.contains("ERROR"):
			color = "#ff6666"
		elif line.contains("Warning") or line.contains("WARNING"):
			color = "#ffaa44"
		elif line.contains("Success") or line.contains("OK"):
			color = "#66ff66"
		bbcode += "[color=%s]%s[/color]\n" % [color, _escape_bbcode(line)]
	
	debug_output.text = bbcode


func _on_clear_debug_pressed() -> void:
	_debug_log.clear()
	_refresh_debug_output()


func _on_copy_debug_pressed() -> void:
	var text := "\n".join(_debug_log)
	DisplayServer.clipboard_set(text)
	_log_debug("Debug log copied to clipboard")


func _tool_read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Error: File not found: " + path
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Error: Cannot read file: " + path
	var content := file.get_as_text()
	file.close()
	return content.left(10000)


func _tool_write_file(path: String, content: String) -> String:
	if not path.begins_with("user://"):
		return "Error: Can only write to user:// directory"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return "Error: Cannot write to file: " + path
	file.store_string(content)
	file.close()
	return "Successfully wrote %d bytes to %s" % [content.length(), path]


func _tool_list_directory(path: String) -> String:
	var dir := DirAccess.open(path)
	if not dir:
		return "Error: Cannot open directory: " + path
	var entries: PackedStringArray = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var prefix := "[DIR] " if dir.current_is_dir() else "      "
		entries.append(prefix + name)
		name = dir.get_next()
	dir.list_dir_end()
	entries.sort()
	return "\n".join(entries) if not entries.is_empty() else "(empty directory)"


func _tool_search_files(pattern: String, path: String) -> String:
	var results: PackedStringArray = []
	_search_recursive(path, pattern, results, 0)
	return "\n".join(results) if not results.is_empty() else "No matches found"


func _search_recursive(path: String, pattern: String, results: PackedStringArray, depth: int) -> void:
	if depth > 5 or results.size() > 50:
		return
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and results.size() < 50:
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := path.rstrip("/") + "/" + name
		if dir.current_is_dir():
			_search_recursive(full_path, pattern, results, depth + 1)
		elif name.containsn(pattern) or full_path.containsn(pattern):
			results.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()


func _tool_load_scene(path: String, parent_path: String, position_arr: Array = []) -> String:
	if path.is_empty():
		return "Error: No scene path provided"
	
	# Check if file exists
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return "Error: Scene file not found: " + path
	
	# Load the scene
	var scene_resource = load(path)
	if not scene_resource:
		return "Error: Failed to load scene: " + path
	
	if not scene_resource is PackedScene:
		return "Error: File is not a valid scene: " + path
	
	# Instantiate the scene with error handling
	var scene_instance: Node = null
	var instantiate_error := ""
	
	# Use call_deferred pattern to catch instantiation errors
	scene_instance = (scene_resource as PackedScene).instantiate()
	if not scene_instance:
		return "Error: Failed to instantiate scene: " + path
	
	# Find parent node - default to MainScene21 for better visibility
	var parent_node: Node
	if parent_path.is_empty():
		# Try to find MainScene21 first (where player and objects are)
		parent_node = get_tree().root.get_node_or_null("/root/LegalGate/MainScene21")
		if not parent_node:
			parent_node = get_tree().current_scene
		if not parent_node:
			parent_node = get_tree().root
	else:
		parent_node = get_tree().root.get_node_or_null(parent_path)
		if not parent_node:
			scene_instance.queue_free()
			return "Error: Parent node not found: " + parent_path
	
	# Set position if provided (before adding to tree to avoid script errors)
	if position_arr.size() >= 3 and scene_instance is Node3D:
		(scene_instance as Node3D).position = Vector3(float(position_arr[0]), float(position_arr[1]), float(position_arr[2]))
	
	# Connect to script errors if the scene has a script
	var script_instance = scene_instance.get_script()
	if script_instance:
		_log_debug("Scene has attached script: " + str(script_instance.resource_path))
	
	# Add to scene tree
	parent_node.add_child(scene_instance)
	scene_instance.owner = get_tree().current_scene
	
	return "Successfully loaded scene '%s' as child of '%s'. Instance name: %s" % [path, parent_node.name, scene_instance.name]


func _tool_remove_node(node_path: String) -> String:
	if node_path.is_empty():
		return "Error: No node path provided"
	
	var node := get_tree().root.get_node_or_null(node_path)
	if not node:
		return "Error: Node not found: " + node_path
	
	# Safety check - don't remove critical nodes
	if node == get_tree().root or node == get_tree().current_scene:
		return "Error: Cannot remove root or current scene node"
	
	var node_name := node.name
	node.queue_free()
	return "Successfully removed node: %s (%s)" % [node_name, node_path]


func _tool_get_scene_tree(max_depth: int) -> String:
	var lines: PackedStringArray = []
	var root := get_tree().root
	lines.append("Scene Tree:")
	_build_tree_string(root, lines, "", 0, max_depth)
	return "\n".join(lines)


func _build_tree_string(node: Node, lines: PackedStringArray, indent: String, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		if node.get_child_count() > 0:
			lines.append(indent + "  ... (%d more children)" % node.get_child_count())
		return
	
	for i in node.get_child_count():
		var child := node.get_child(i)
		var prefix := "├─ " if i < node.get_child_count() - 1 else "└─ "
		var child_indent := "│  " if i < node.get_child_count() - 1 else "   "
		var class_name_str := child.get_class()
		lines.append(indent + prefix + child.name + " [" + class_name_str + "]")
		_build_tree_string(child, lines, indent + child_indent, depth + 1, max_depth)


# ============================================================================
# SCENE CREATION TOOLS
# ============================================================================

func _tool_validate_gdscript(code: String) -> String:
	if code.is_empty():
		return "Error: No code provided"
	
	var script := GDScript.new()
	script.source_code = code
	var err := script.reload()
	
	if err != OK:
		return "Error: Script validation failed (error code: %d). Check syntax." % err
	
	# Additional static analysis for common issues
	var warnings: PackedStringArray = []
	
	# Check for potential null reference issues
	if code.contains(".material_override") and not code.contains("if ") and not code.contains("mesh"):
		warnings.append("Warning: Setting material_override without checking if mesh exists")
	
	# Check for missing extends
	if not code.strip_edges().begins_with("extends"):
		warnings.append("Warning: Script should start with 'extends' statement")
	
	# Check for _ready accessing potentially uninitialized nodes
	if code.contains("func _ready()") and code.contains("$") and not code.contains("@onready"):
		warnings.append("Warning: Using $ node paths in _ready() - consider using @onready")
	
	var result := "OK: Script syntax is valid"
	if not warnings.is_empty():
		result += "\n" + "\n".join(warnings)
	
	return result


func _tool_create_scene(scene_name: String, root_type: String, root_name: String, script_content: String, children: Array) -> String:
	if scene_name.is_empty():
		return "Error: Scene name is required"
	
	var scene_path := "user://" + scene_name + ".tscn"
	var script_path := "user://" + scene_name + ".gd"
	
	# Validate script if provided
	if not script_content.is_empty():
		var validation := _tool_validate_gdscript(script_content)
		if not validation.begins_with("OK"):
			return "Script validation failed: " + validation
	
	# Build the TSCN content
	var tscn_content := _build_tscn_content(root_type, root_name, script_content, script_path, children)
	
	# Write script file if provided
	if not script_content.is_empty():
		var script_file := FileAccess.open(script_path, FileAccess.WRITE)
		if not script_file:
			return "Error: Cannot write script file: " + script_path
		script_file.store_string(script_content)
		script_file.close()
	
	# Write scene file
	var scene_file := FileAccess.open(scene_path, FileAccess.WRITE)
	if not scene_file:
		return "Error: Cannot write scene file: " + scene_path
	scene_file.store_string(tscn_content)
	scene_file.close()
	
	# Validate by trying to load
	var test_load = load(scene_path)
	if not test_load:
		return "Error: Scene file was written but failed to load. Check TSCN syntax."
	
	return "Successfully created scene: %s\nScript: %s" % [scene_path, script_path if not script_content.is_empty() else "(none)"]


func _tool_create_and_load_scene(scene_name: String, root_type: String, root_name: String, script_content: String, children: Array, parent_path: String, position_arr: Array) -> String:
	# Redirect to safe version
	return _tool_create_and_load_scene_safe(scene_name, root_type, root_name, script_content, children, parent_path, position_arr)


func _build_tscn_content(root_type: String, root_name: String, script_content: String, script_path: String, children: Array) -> String:
	var load_steps := 1
	var has_script := not script_content.is_empty()
	
	# Count resources needed
	var sub_resources: Array[String] = []
	var ext_resources: Array[String] = []
	
	if has_script:
		ext_resources.append('[ext_resource type="Script" path="%s" id="1_script"]' % script_path)
	
	# Build sub-resources for meshes, materials, shapes
	var resource_id := 1
	var child_resources: Dictionary = {}  # child index -> {mesh_id, material_id, shape_id}
	
	for i in children.size():
		var child: Dictionary = children[i]
		var child_type: String = child.get("type", "Node3D")
		var props: Dictionary = child.get("properties", {})
		child_resources[i] = {}
		
		# Auto-add BoxMesh for MeshInstance3D if no mesh specified
		var needs_mesh := child_type == "MeshInstance3D" and not props.has("mesh")
		if needs_mesh:
			props["mesh"] = "box"
		
		# Mesh
		if props.has("mesh"):
			var mesh_type := _get_mesh_class(str(props.mesh))
			if mesh_type:
				var size_str := ""
				if props.has("mesh_size") and props.mesh_size is Array and props.mesh_size.size() >= 3:
					var sz: Array = props.mesh_size
					if mesh_type == "BoxMesh":
						size_str = "\nsize = Vector3(%s, %s, %s)" % [sz[0], sz[1], sz[2]]
				sub_resources.append('[sub_resource type="%s" id="Mesh_%d"]%s' % [mesh_type, resource_id, size_str])
				child_resources[i]["mesh_id"] = resource_id
				resource_id += 1
		
		# Material/Color - auto-add white material for MeshInstance3D if none specified
		if props.has("color") and props.color is Array and props.color.size() >= 3:
			var c: Array = props.color
			var alpha: float = c[3] if c.size() > 3 else 1.0
			sub_resources.append('[sub_resource type="StandardMaterial3D" id="Material_%d"]\nalbedo_color = Color(%s, %s, %s, %s)' % [resource_id, c[0], c[1], c[2], alpha])
			child_resources[i]["material_id"] = resource_id
			resource_id += 1
		elif child_type == "MeshInstance3D" and not props.has("color"):
			# Add default white material for visibility
			sub_resources.append('[sub_resource type="StandardMaterial3D" id="Material_%d"]\nalbedo_color = Color(1, 1, 1, 1)' % resource_id)
			child_resources[i]["material_id"] = resource_id
			resource_id += 1
		
		# Shape
		if props.has("shape"):
			var shape_type := _get_shape_class(str(props.shape))
			if shape_type:
				var shape_size_str := ""
				if props.has("shape_size") and props.shape_size is Array:
					var sz: Array = props.shape_size
					if shape_type == "BoxShape3D" and sz.size() >= 3:
						shape_size_str = "\nsize = Vector3(%s, %s, %s)" % [sz[0], sz[1], sz[2]]
					elif shape_type == "SphereShape3D" and sz.size() >= 1:
						shape_size_str = "\nradius = %s" % sz[0]
				sub_resources.append('[sub_resource type="%s" id="Shape_%d"]%s' % [shape_type, resource_id, shape_size_str])
				child_resources[i]["shape_id"] = resource_id
				resource_id += 1
	
	load_steps = 1 + ext_resources.size() + sub_resources.size()
	
	# Build header
	var tscn := "[gd_scene load_steps=%d format=3]\n\n" % load_steps
	
	# Add external resources
	for ext_res in ext_resources:
		tscn += ext_res + "\n"
	if not ext_resources.is_empty():
		tscn += "\n"
	
	# Add sub-resources
	for sub_res in sub_resources:
		tscn += sub_res + "\n\n"
	
	# Root node
	tscn += '[node name="%s" type="%s"]\n' % [root_name, root_type]
	if has_script:
		tscn += 'script = ExtResource("1_script")\n'
	tscn += "\n"
	
	# Child nodes
	for i in children.size():
		var child: Dictionary = children[i]
		var child_type: String = child.get("type", "Node3D")
		var child_name: String = child.get("name", "Child%d" % i)
		var props: Dictionary = child.get("properties", {})
		var res_ids: Dictionary = child_resources.get(i, {})
		
		tscn += '[node name="%s" type="%s" parent="."]\n' % [child_name, child_type]
		
		# Position
		if props.has("position") and props.position is Array and props.position.size() >= 3:
			var p: Array = props.position
			tscn += "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\n" % [p[0], p[1], p[2]]
		
		# Mesh
		if res_ids.has("mesh_id"):
			tscn += 'mesh = SubResource("Mesh_%d")\n' % res_ids.mesh_id
		
		# Material
		if res_ids.has("material_id"):
			tscn += 'material_override = SubResource("Material_%d")\n' % res_ids.material_id
		
		# Shape
		if res_ids.has("shape_id"):
			tscn += 'shape = SubResource("Shape_%d")\n' % res_ids.shape_id
		
		# Text for Label3D
		if props.has("text") and child_type == "Label3D":
			tscn += 'text = "%s"\n' % str(props.text).replace('"', '\\"')
		
		tscn += "\n"
	
	return tscn


func _get_mesh_class(mesh_name: String) -> String:
	match mesh_name.to_lower():
		"box", "cube": return "BoxMesh"
		"sphere": return "SphereMesh"
		"cylinder": return "CylinderMesh"
		"capsule": return "CapsuleMesh"
		"plane": return "PlaneMesh"
		"prism": return "PrismMesh"
		"torus": return "TorusMesh"
	return ""


func _get_shape_class(shape_name: String) -> String:
	match shape_name.to_lower():
		"box", "cube": return "BoxShape3D"
		"sphere": return "SphereShape3D"
		"capsule": return "CapsuleShape3D"
		"cylinder": return "CylinderShape3D"
	return ""


func _update_token_usage(data: Dictionary) -> void:
	var tokens := 0
	
	if data.has("usage"):
		var usage: Dictionary = data.usage
		tokens = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
		tokens = usage.get("total_tokens", tokens)
	
	# Gemini format
	if data.has("usageMetadata"):
		var usage: Dictionary = data.usageMetadata
		tokens = usage.get("totalTokenCount", 0)
	
	_total_tokens_used += tokens
	_update_token_count()

func _update_token_count() -> void:
	if token_label:
		token_label.text = "Tokens: %d" % _total_tokens_used


func _cancel_stream() -> void:
	if _http_request:
		_http_request.cancel_request()
	_finish_streaming()


func _finish_streaming() -> void:
	_is_streaming = false
	if stop_button:
		stop_button.disabled = true
	if send_button:
		send_button.disabled = false
	_update_status("Ready")


func _continue_after_tools() -> void:
	# Continue the conversation after tool execution
	_is_streaming = true
	_current_response = ""
	
	if stop_button:
		stop_button.disabled = false
	if send_button:
		send_button.disabled = true
	
	_update_status("Getting response after tool use...")
	
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	var endpoint: String = config.endpoint
	
	if _current_provider == Provider.CUSTOM:
		endpoint = _custom_endpoint
	elif _current_provider == Provider.GEMINI:
		endpoint = endpoint.replace("{model}", _model) + "?key=" + _api_key
	
	var headers := _build_auth_headers()
	var body := _build_request_body()
	var json_body := JSON.stringify(body)
	
	var error := _http_request.request(endpoint, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		_add_error_message("Failed to continue after tools: " + str(error))
		_finish_streaming()


func _cleanup_http() -> void:
	if _http_request:
		_http_request.cancel_request()
		_http_request.queue_free()
		_http_request = null
	if _models_http_request:
		_models_http_request.cancel_request()
		_models_http_request.queue_free()
		_models_http_request = null


# ============================================================================
# SETTINGS MANAGEMENT
# ============================================================================

func _save_settings() -> void:
	if api_key_input:
		_api_key = api_key_input.text.strip_edges()
	if model_option and model_option.selected >= 0:
		_model = model_option.get_item_text(model_option.selected)
	if endpoint_input:
		_custom_endpoint = endpoint_input.text.strip_edges()
	if max_tokens_spin:
		_max_tokens = int(max_tokens_spin.value)
	if temperature_slider:
		_temperature = temperature_slider.value
	if system_prompt_input:
		_system_prompt = system_prompt_input.text
	if tools_enabled_check:
		_tools_enabled = tools_enabled_check.button_pressed
	
	var config := ConfigFile.new()
	config.set_value("llm", "provider", _current_provider)
	config.set_value("llm", "api_key", _api_key)
	config.set_value("llm", "model", _model)
	config.set_value("llm", "custom_endpoint", _custom_endpoint)
	config.set_value("llm", "max_tokens", _max_tokens)
	config.set_value("llm", "temperature", _temperature)
	config.set_value("llm", "system_prompt", _system_prompt)
	config.set_value("llm", "preset", _current_preset)
	config.set_value("llm", "tools_enabled", _tools_enabled)
	
	var error := config.save("user://llm_chat_settings.cfg")
	if error == OK:
		_add_system_message("Settings saved.")
	else:
		_add_error_message("Failed to save settings.")


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://llm_chat_settings.cfg") != OK:
		_apply_default_settings()
		return
	
	_current_provider = config.get_value("llm", "provider", Provider.CLAUDE) as Provider
	_api_key = config.get_value("llm", "api_key", "")
	_model = config.get_value("llm", "model", "claude-sonnet-4-20250514")
	_custom_endpoint = config.get_value("llm", "custom_endpoint", "")
	_max_tokens = config.get_value("llm", "max_tokens", 4096)
	_temperature = config.get_value("llm", "temperature", 0.7)
	_system_prompt = config.get_value("llm", "system_prompt", "")
	_current_preset = config.get_value("llm", "preset", SystemPreset.CODER) as SystemPreset
	_tools_enabled = config.get_value("llm", "tools_enabled", true)
	
	if _system_prompt.is_empty():
		_system_prompt = SYSTEM_PRESETS[_current_preset].prompt
	
	_apply_settings_to_ui()


func _apply_default_settings() -> void:
	_current_provider = Provider.CLAUDE
	_api_key = ""
	_model = "claude-sonnet-4-20250514"
	_custom_endpoint = ""
	_max_tokens = 4096
	_temperature = 0.7
	_current_preset = SystemPreset.CODER
	_system_prompt = SYSTEM_PRESETS[_current_preset].prompt
	_tools_enabled = true
	
	_apply_settings_to_ui()


func _apply_settings_to_ui() -> void:
	if provider_option:
		for i in provider_option.item_count:
			if provider_option.get_item_id(i) == _current_provider:
				provider_option.select(i)
				break
	
	var config: Dictionary = PROVIDER_CONFIGS[_current_provider]
	_update_model_dropdown(config.models)
	_select_model(_model)
	
	if api_key_input:
		api_key_input.text = _api_key
	if endpoint_input:
		endpoint_input.text = _custom_endpoint if _current_provider == Provider.CUSTOM else config.endpoint
		endpoint_input.editable = (_current_provider == Provider.CUSTOM)
	if max_tokens_spin:
		max_tokens_spin.value = _max_tokens
	if temperature_slider:
		temperature_slider.value = _temperature
	if temperature_value:
		temperature_value.text = "%.1f" % _temperature
	if preset_option:
		for i in preset_option.item_count:
			if preset_option.get_item_id(i) == _current_preset:
				preset_option.select(i)
				break
	if system_prompt_input:
		system_prompt_input.text = _system_prompt
	if tools_enabled_check:
		tools_enabled_check.button_pressed = _tools_enabled


func _test_connection() -> void:
	if api_key_input:
		_api_key = api_key_input.text.strip_edges()
	if _api_key.is_empty():
		_add_error_message("Enter an API key first.")
		return
	
	_add_system_message("Testing connection...")
	_add_user_message("Say 'Connection successful!' in exactly those words.")
	_send_to_llm("test")


func _update_status(status: String) -> void:
	if status_label:
		status_label.text = status


# ============================================================================
# PUBLIC API
# ============================================================================

func send_message(message: String) -> void:
	if message_input:
		message_input.text = message
	_on_send_pressed()

func get_conversation() -> Array[Dictionary]:
	return _messages.duplicate()

func clear_conversation() -> void:
	_on_clear_chat_pressed()

func set_api_key(key: String) -> void:
	_api_key = key
	if api_key_input:
		api_key_input.text = key

func set_model(model_name: String) -> void:
	_model = model_name
	_select_model(model_name)

func set_provider(provider: Provider) -> void:
	_current_provider = provider
	if provider_option:
		for i in provider_option.item_count:
			if provider_option.get_item_id(i) == provider:
				provider_option.select(i)
				_on_provider_changed(i)
				break

func is_streaming() -> bool:
	return _is_streaming

func focus_input() -> void:
	if message_input:
		message_input.grab_focus()

# ============================================================================
# CONVERSATION HISTORY MANAGEMENT
# ============================================================================

func _ensure_history_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("llm_chat_history"):
		dir.make_dir("llm_chat_history")


func _start_new_session() -> void:
	var datetime := Time.get_datetime_dict_from_system()
	_current_session_id = "%04d%02d%02d_%02d%02d%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]


func _get_session_filename() -> String:
	return HISTORY_DIR + _current_session_id + ".json"


func _auto_save_conversation() -> void:
	if not _auto_save_enabled or _messages.is_empty():
		return
	_save_conversation_to_file(_get_session_filename())


func _save_conversation_to_file(filepath: String) -> bool:
	var save_data := {
		"session_id": _current_session_id,
		"timestamp": Time.get_unix_time_from_system(),
		"provider": _current_provider,
		"model": _model,
		"tokens_used": _total_tokens_used,
		"messages": []
	}
	
	# Convert messages to serializable format
	for msg in _messages:
		var msg_copy := {}
		for key in msg.keys():
			var value = msg[key]
			if value is int:
				msg_copy[key] = value
			else:
				msg_copy[key] = str(value) if not (value is String or value is Array or value is Dictionary) else value
		save_data.messages.append(msg_copy)
	
	var json_str := JSON.stringify(save_data, "\t")
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(json_str)
	file.close()
	return true


func _load_conversation_from_file(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		return false
	
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return false
	
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return false
	
	var data: Dictionary = json.data
	if not data.has("messages"):
		return false
	
	# Clear current conversation
	_messages.clear()
	
	# Load messages
	for msg_data in data.messages:
		var msg: Dictionary = {}
		msg["role"] = int(msg_data.get("role", 0)) as MessageRole
		msg["content"] = msg_data.get("content", "")
		msg["timestamp"] = msg_data.get("timestamp", "")
		
		# Copy optional fields
		for key in ["tool_name", "tool_use_id", "result", "raw_content", "tool_calls_data"]:
			if msg_data.has(key):
				msg[key] = msg_data[key]
		
		_messages.append(msg)
	
	# Restore session info
	_current_session_id = data.get("session_id", _current_session_id)
	_total_tokens_used = data.get("tokens_used", 0)
	
	_refresh_chat_display()
	_update_token_count()
	return true


func _get_history_files() -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	var dir := DirAccess.open(HISTORY_DIR)
	if not dir:
		return files
	
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var filepath := HISTORY_DIR + filename
			var info := _get_history_file_info(filepath)
			if not info.is_empty():
				files.append(info)
		filename = dir.get_next()
	dir.list_dir_end()
	
	# Sort by timestamp descending (newest first)
	files.sort_custom(func(a, b): return a.timestamp > b.timestamp)
	return files


func _get_history_file_info(filepath: String) -> Dictionary:
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return {}
	
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return {}
	
	var data: Dictionary = json.data
	var msg_count: int = data.get("messages", []).size()
	
	# Get first user message as preview
	var preview := ""
	for msg in data.get("messages", []):
		if int(msg.get("role", 0)) == MessageRole.USER:
			preview = str(msg.get("content", "")).left(50)
			if preview.length() >= 50:
				preview += "..."
			break
	
	return {
		"filepath": filepath,
		"session_id": data.get("session_id", ""),
		"timestamp": data.get("timestamp", 0),
		"model": data.get("model", "unknown"),
		"message_count": msg_count,
		"tokens_used": data.get("tokens_used", 0),
		"preview": preview
	}


func _refresh_history_list() -> void:
	if not history_list:
		return
	
	history_list.clear()
	var files := _get_history_files()
	
	for info in files:
		var datetime := Time.get_datetime_dict_from_unix_time(int(info.timestamp))
		var date_str := "%04d-%02d-%02d %02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute
		]
		var label := "%s | %s | %d msgs | %s" % [
			date_str,
			str(info.model).left(20),
			info.message_count,
			info.preview if info.preview else "(empty)"
		]
		history_list.add_item(label)
		history_list.set_item_metadata(history_list.item_count - 1, info.filepath)


func _on_history_button_pressed() -> void:
	# Save current conversation first
	_auto_save_conversation()
	
	# Switch to history tab and refresh
	if tab_container:
		for i in tab_container.get_tab_count():
			if tab_container.get_tab_title(i) == "History":
				tab_container.current_tab = i
				break
	_refresh_history_list()


func _on_history_item_selected(_index: int) -> void:
	# Enable load/delete/export buttons when item selected
	if load_history_button:
		load_history_button.disabled = false
	if delete_history_button:
		delete_history_button.disabled = false
	if export_history_button:
		export_history_button.disabled = false


func _on_load_history_pressed() -> void:
	if not history_list or history_list.get_selected_items().is_empty():
		return
	
	var selected_idx: int = history_list.get_selected_items()[0]
	var filepath: String = history_list.get_item_metadata(selected_idx)
	
	if _load_conversation_from_file(filepath):
		_add_system_message("Loaded conversation from history.")
		# Switch back to chat tab
		if tab_container:
			tab_container.current_tab = 0
	else:
		_add_error_message("Failed to load conversation.")


func _on_delete_history_pressed() -> void:
	if not history_list or history_list.get_selected_items().is_empty():
		return
	
	var selected_idx: int = history_list.get_selected_items()[0]
	var filepath: String = history_list.get_item_metadata(selected_idx)
	
	var dir := DirAccess.open(HISTORY_DIR)
	if dir:
		var filename := filepath.get_file()
		if dir.remove(filename) == OK:
			_refresh_history_list()
			_add_system_message("Deleted history entry.")
		else:
			_add_error_message("Failed to delete history entry.")


func _on_export_history_pressed() -> void:
	if not history_list or history_list.get_selected_items().is_empty():
		return
	
	var selected_idx: int = history_list.get_selected_items()[0]
	var filepath: String = history_list.get_item_metadata(selected_idx)
	
	# Load and export as readable text
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		_add_error_message("Failed to read history file.")
		return
	
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_str) != OK:
		_add_error_message("Failed to parse history file.")
		return
	
	var data: Dictionary = json.data
	var export_text := "# LLM Chat Export\n"
	export_text += "# Session: %s\n" % data.get("session_id", "unknown")
	export_text += "# Model: %s\n" % data.get("model", "unknown")
	export_text += "# Tokens: %d\n\n" % data.get("tokens_used", 0)
	
	for msg in data.get("messages", []):
		var role_name := "Unknown"
		match int(msg.get("role", 0)):
			MessageRole.USER: role_name = "User"
			MessageRole.ASSISTANT: role_name = "Assistant"
			MessageRole.SYSTEM: role_name = "System"
			MessageRole.TOOL: role_name = "Tool"
		
		export_text += "## [%s] %s\n%s\n\n" % [
			msg.get("timestamp", ""),
			role_name,
			msg.get("content", "")
		]
	
	DisplayServer.clipboard_set(export_text)
	_add_system_message("Exported conversation to clipboard.")
