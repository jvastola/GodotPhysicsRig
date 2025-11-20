extends Node

# Loads the matchmaking server logic from your main project
const MatchmakingServer = preload("res://multiplayer/matchmaking_server.gd")

var server: Node = null

func _ready():
	server = MatchmakingServer.new()
	add_child(server)
	server.start_local_server(8080, "0.0.0.0")
	print("Matchmaking server running on port 8080 and address 0.0.0.0!")
