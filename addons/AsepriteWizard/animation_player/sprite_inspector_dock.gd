tool
extends PanelContainer

var result_code = preload("../config/result_codes.gd")
var animation_creator = preload("animation_creator.gd").new()

var scene: Node
var sprite: Sprite

var config
var file_system: EditorFileSystem

var _source: String = ""
var _animation_player_path: String
var _file_dialog_aseprite: FileDialog
var _output_folder_dialog: FileDialog
var _warning_dialog: AcceptDialog
var _importing := false

var _output_folder := ""
var _out_folder_default := "[Same as scene]"

onready var _options_field = $margin/VBoxContainer/animation_player/options
onready var _source_field = $margin/VBoxContainer/source/button
onready var _options_title = $margin/VBoxContainer/options_title/options_title
onready var _options_container = $margin/VBoxContainer/options
onready var _out_folder_field = $margin/VBoxContainer/options/out_folder/button
onready var _out_filename_field = $margin/VBoxContainer/options/out_filename/LineEdit
onready var _visible_layers_field =  $margin/VBoxContainer/options/visible_layers/CheckButton
onready var _trim_mode_field = $margin/VBoxContainer/options/trim_mode/field
onready var _ex_pattern_field = $margin/VBoxContainer/options/ex_pattern/LineEdit

func _ready():
	var description = _decode_config(sprite.editor_description)

	if _is_wizard_config(description):
		_load_config(description)
	else:
		_load_default_config()

	animation_creator.init(config, file_system)


func _decode_config(editor_description: String) -> String:
	var description = ""
	if editor_description != "":
		description = Marshalls.base64_to_utf8(editor_description)
		if description == null:
			description = ""
	return description


func _is_wizard_config(description: String) -> bool:
	return description.begins_with("aseprite_wizard_config")


func _load_config(description):
	var cfg = description.split("\n")
	var config = {}
	for c in cfg:
		var parts = c.split("|=", 1)
		print(parts)
		if parts.size() == 2:
			config[parts[0].strip_edges()] = parts[1].strip_edges()

	if config.has("source"):
		_set_source(config.source)

	if config.has("player"):
		_set_animation_player(config.player)

	_output_folder = config.get("o_folder", "")
	_out_folder_field.text = _output_folder if _output_folder != "" else _out_folder_default
	_out_filename_field.text = config.get("o_name", "")
	_visible_layers_field.pressed = config.get("only_visible", "") == "True"
	_trim_mode_field.selected = int(config.get("trim", "0"))
	_ex_pattern_field.text = config.get("o_ex_p", "")

	if config.get("op_exp", "false") == "True":
		_options_container.visible = true
		_options_title.pressed = true


func _load_default_config():
	# TODO load from config
	pass


func _set_source(source):
	_source = source
	_source_field.text = _source
	_source_field.hint_tooltip = _source


func _set_animation_player(player):
	_animation_player_path = player
	_options_field.add_item(_animation_player_path)


func _on_options_pressed():
	var animation_players = []
	var root = get_tree().get_edited_scene_root()
	_find_animation_players(root, root, animation_players)

	var current = 0
	_options_field.clear()
	_options_field.add_item("[empty]")

	for ap in animation_players:
		_options_field.add_item(ap)
		if ap == _animation_player_path:
			current = _options_field.get_item_count() - 1

	_options_field.select(current)


func _find_animation_players(root: Node, node: Node, players: Array):
	if node is AnimationPlayer:
		players.push_back(root.get_path_to(node))

	for c in node.get_children():
		_find_animation_players(root, c, players)


func _on_options_item_selected(index):
	_animation_player_path = _options_field.get_item_text(index)
	_save_config()


func _on_source_pressed():
	_open_source_dialog()


func _on_import_pressed():
	if _importing:
		return
	_importing = true

	var root = get_tree().get_edited_scene_root()

	if _animation_player_path == "" or not root.has_node(_animation_player_path):
		_show_message("AnimationPlayer not found")
		_importing = false
		return

	if _source == "":
		_show_message("Aseprite file not selected")
		_importing = false
		return

	var options = {
		"source": ProjectSettings.globalize_path(_source),
		"output_folder": _output_folder if _output_folder != "" else root.filename.get_base_dir(),
#		"export_mode": export_mode,
		"exception_pattern": _ex_pattern_field.text,
		"only_visible_layers": _visible_layers_field.pressed,
		"trim_images": _trim_mode_field.selected == 1,
		"trim_by_grid": _trim_mode_field.selected == 2,
		"output_filename": _out_filename_field.text,
	}

	_save_config()

	var exit_code = animation_creator.create_animations(sprite, root.get_node(_animation_player_path), options)
	if exit_code is GDScriptFunctionState:
		exit_code = yield(exit_code, "completed")

	if exit_code == 0:
		_show_message("Import completed")
	else:
		_show_message(result_code.get_error_message(exit_code))

	_importing = false



func _save_config():
	var text = "aseprite_wizard_config\n"
	if _animation_player_path != "":
		text += _prop("player", _animation_player_path)
	if _source != "":
		text += _prop("source", _source)

	text += _prop("op_exp", _options_title.pressed)

	text += _prop("o_folder", _output_folder)
	text += _prop("o_name", _out_filename_field.text)
	text += _prop("only_visible", _visible_layers_field.pressed)
	text += _prop("trim", _trim_mode_field.selected)
	text += _prop("o_ex_p", _ex_pattern_field.text)

	sprite.editor_description = Marshalls.utf8_to_base64(text)


func _prop(prop, value):
	return "%s|= %s\n" % [prop, value]


func _open_source_dialog():
	_file_dialog_aseprite = _create_aseprite_file_selection()
	get_parent().add_child(_file_dialog_aseprite)
	if _source != "":
		_file_dialog_aseprite.current_dir = _source.get_base_dir()
	_file_dialog_aseprite.popup_centered_ratio()


func _create_aseprite_file_selection():
	var file_dialog = FileDialog.new()
	file_dialog.mode = FileDialog.MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.connect("file_selected", self, "_on_aseprite_file_selected")
	file_dialog.set_filters(PoolStringArray(["*.ase","*.aseprite"]))
	return file_dialog


func _on_aseprite_file_selected(path):
	_set_source(ProjectSettings.localize_path(path))
	_save_config()
	_file_dialog_aseprite.queue_free()


func _show_message(message: String):
	_warning_dialog = AcceptDialog.new()
	get_parent().add_child(_warning_dialog)
	_warning_dialog.dialog_text = message
	_warning_dialog.popup_centered()
	_warning_dialog.connect("popup_hide", _warning_dialog, "queue_free")


func _on_options_title_toggled(button_pressed):
	_options_container.visible = button_pressed
	_save_config()


func _on_out_folder_pressed():
	_output_folder_dialog = _create_output_folder_selection()
	get_parent().add_child(_output_folder_dialog)
	if _output_folder != _out_folder_default:
		_output_folder_dialog.current_dir = _output_folder
	_output_folder_dialog.popup_centered_ratio()


func _create_output_folder_selection():
	var file_dialog = FileDialog.new()
	file_dialog.mode = FileDialog.MODE_OPEN_DIR
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.connect("dir_selected", self, "_on_output_folder_selected")
	return file_dialog


func _on_output_folder_selected(path):
	_output_folder = path
	_out_folder_field.text = _output_folder if _output_folder != "" else _out_folder_default
	_output_folder_dialog.queue_free()
