class_name SearchJob
extends RefCounted

const SearchBotScript = preload("res://scripts/game/search_bot.gd")

var _context: Dictionary
var _config: Dictionary
var _result: Dictionary = {}
var _mutex := Mutex.new()

func _init(context: Dictionary, config: Dictionary) -> void:
	_context = context.duplicate(true)
	_config = config.duplicate()

func run() -> void:
	var analysis := SearchBotScript.analyze(_context, _config)
	_mutex.lock()
	_result = analysis
	_mutex.unlock()

func result() -> Dictionary:
	_mutex.lock()
	var copy := _result.duplicate(true)
	_mutex.unlock()
	return copy
