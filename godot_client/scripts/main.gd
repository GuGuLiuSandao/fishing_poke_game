extends Control

const SEATS := [
	{"name": "你", "role": "玩家", "chips": 2400, "state": "待开局", "cards": "?? ??"},
	{"name": "小孩", "role": "队友", "chips": 3180, "state": "等待行动", "cards": "A♠ K♠"},
	{"name": "Bot-03", "role": "机器人", "chips": 1860, "state": "已弃牌", "cards": "-- --"},
	{"name": "Bot-07", "role": "机器人", "chips": 2710, "state": "跟注中", "cards": "9♦ 9♣"},
]

var phase := "lobby"
var round_index := 0
var active_seat_index := -1
var action_log: Array[String] = []

@onready var status_label: Label = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/StatusLabel
@onready var round_label: Label = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/MetaRow/RoundLabel
@onready var phase_label: Label = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/MetaRow/PhaseLabel
@onready var start_button: Button = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/MetaRow/ButtonRow/StartButton
@onready var next_button: Button = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/MetaRow/ButtonRow/NextButton
@onready var reset_button: Button = $HUD/HUDVBox/Header/HeaderMargin/HeaderVBox/MetaRow/ButtonRow/ResetButton
@onready var table_title: Label = $HUD/HUDVBox/MainRow/Board/Table/Inner/CenterBlock/TableTitle
@onready var table_text: RichTextLabel = $HUD/HUDVBox/MainRow/Board/Table/Inner/CenterBlock/TableText
@onready var log_text: RichTextLabel = $HUD/HUDVBox/MainRow/Sidebar/SidebarMargin/SidebarVBox/LogCard/LogMargin/LogText
@onready var seat_panels: Dictionary = {
	"top": {
		"panel": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop,
		"name": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop/SeatMargin/SeatVBox/NameLabel,
		"role": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop/SeatMargin/SeatVBox/RoleLabel,
		"chips": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop/SeatMargin/SeatVBox/ChipsLabel,
		"state": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop/SeatMargin/SeatVBox/StateLabel,
		"cards": $HUD/HUDVBox/MainRow/Board/Seats/SeatTop/SeatMargin/SeatVBox/CardsLabel,
	},
	"left": {
		"panel": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft,
		"name": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft/SeatMargin/SeatVBox/NameLabel,
		"role": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft/SeatMargin/SeatVBox/RoleLabel,
		"chips": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft/SeatMargin/SeatVBox/ChipsLabel,
		"state": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft/SeatMargin/SeatVBox/StateLabel,
		"cards": $HUD/HUDVBox/MainRow/Board/Seats/SeatLeft/SeatMargin/SeatVBox/CardsLabel,
	},
	"right": {
		"panel": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight,
		"name": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight/SeatMargin/SeatVBox/NameLabel,
		"role": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight/SeatMargin/SeatVBox/RoleLabel,
		"chips": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight/SeatMargin/SeatVBox/ChipsLabel,
		"state": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight/SeatMargin/SeatVBox/StateLabel,
		"cards": $HUD/HUDVBox/MainRow/Board/Seats/SeatRight/SeatMargin/SeatVBox/CardsLabel,
	},
	"bottom": {
		"panel": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom,
		"name": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom/SeatMargin/SeatVBox/NameLabel,
		"role": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom/SeatMargin/SeatVBox/RoleLabel,
		"chips": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom/SeatMargin/SeatVBox/ChipsLabel,
		"state": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom/SeatMargin/SeatVBox/StateLabel,
		"cards": $HUD/HUDVBox/MainRow/Board/Seats/SeatBottom/SeatMargin/SeatVBox/CardsLabel,
	},
}

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	next_button.pressed.connect(_on_next_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	_render()

func _on_start_pressed() -> void:
	phase = "playing"
	round_index = 1
	active_seat_index = 0
	action_log = ["开局完成：底池归零，进入第一轮。", "轮到你先行动。"]
	_render()

func _on_next_pressed() -> void:
	if phase != "playing":
		return
	active_seat_index = (active_seat_index + 1) % SEATS.size()
	var seat: Dictionary = SEATS[active_seat_index]
	var action: String = "%s 选择过牌。" % seat["name"]
	if seat["name"] == "你":
		action = "你选择看牌，等待下一步。"
	action_log.append(action)
	if action_log.size() > 5:
		action_log.pop_front()
	_render()

func _on_reset_pressed() -> void:
	phase = "lobby"
	round_index = 0
	active_seat_index = -1
	action_log = ["桌面已重置，等待开局。"]
	_render()

func _render() -> void:
	status_label.text = _status_text()
	round_label.text = "回合：%d" % round_index
	phase_label.text = "阶段：%s" % _phase_label()
	start_button.disabled = phase == "playing"
	next_button.disabled = phase != "playing"
	table_title.text = "桌面进行中" if phase == "playing" else "桌面待命"
	table_text.text = _table_text()
	log_text.text = _log_text()
	_update_seats()

func _update_seats() -> void:
	for i in range(SEATS.size()):
		var seat: Dictionary = SEATS[i]
		var slot: String = ["bottom", "left", "top", "right"][i]
		var nodes: Dictionary = seat_panels[slot]
		nodes["name"].text = str(seat["name"])
		nodes["role"].text = str(seat["role"])
		nodes["chips"].text = "筹码：%d" % int(seat["chips"])
		nodes["cards"].text = str(seat["cards"])
		if phase == "playing" and i == active_seat_index:
			nodes["state"].text = "状态：轮到此位"
			nodes["panel"].modulate = Color(1.0, 0.92, 0.55)
		else:
			nodes["state"].text = "状态：%s" % str(seat["state"])
			nodes["panel"].modulate = Color(1, 1, 1)

func _status_text() -> String:
	if phase == "lobby":
		return "已进入 Godot 牌桌原型，等你点 Start。"
	return "第 %d 回合，正在模拟轮次推进。" % round_index

func _phase_label() -> String:
	return "大厅" if phase == "lobby" else "进行中"

func _table_text() -> String:
	return "[center][b]中央牌桌[/b][/center]\n\n底池：0\n当前行动：%s\n\n这版先把布局和状态跑通，下一步再接真实规则层。" % ("未开始" if active_seat_index < 0 else str(SEATS[active_seat_index]["name"]))

func _log_text() -> String:
	var lines := PackedStringArray(["[b]动作日志[/b]"])
	for item in action_log:
		lines.append("• %s" % item)
	return "\n".join(lines)
