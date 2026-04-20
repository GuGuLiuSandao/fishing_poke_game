extends Control

@onready var status_label: Label = $Margin/VBox/Header/StatusLabel
@onready var next_step_label: Label = $Margin/VBox/Body/BodyMargin/Content/NextStepLabel
@onready var notes_label: RichTextLabel = $Margin/VBox/Body/BodyMargin/Content/NotesLabel

func _ready() -> void:
	status_label.text = "Godot 骨架已就位"
	next_step_label.text = "下一步：先把单机规则层塞进来，再接 WebSocket 联机。"
	notes_label.text = "[b]当前分层建议[/b]\n- Godot: UI / 动画 / 输入\n- Python: 先保留服务端和 Bot\n- 后续抽核心规则层，单机和联机共用一套逻辑"
