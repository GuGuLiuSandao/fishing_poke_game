class_name RoundSimulator
extends RefCounted

const HandRulesScript = preload("res://scripts/game/hand_rules.gd")
const GameRulesScript = preload("res://scripts/game/game_rules.gd")
const BotContractScript = preload("res://scripts/game/bot_contract.gd")

var phase := "playing"
var round_index := 0
var active_seat := -1
var pot := 0
var seats: Array = []
var structured_action_history: Array = []
var last_bettor_seat := -1
var bet_order := 0
var action_sequence := 0
var next_starter_seat := -1
var winners: Array[int] = []
var payout := 0
var round_result := ""

static func from_observation(observation: Dictionary, determinization_seed: int):
	var simulator = new()
	simulator.round_index = int(observation["round_index"])
	simulator.active_seat = int(observation["active_seat"])
	simulator.pot = int(observation["pot"])
	simulator.last_bettor_seat = int(observation.get("last_bettor_seat", -1))
	simulator.bet_order = int(observation.get("bet_order", 0))
	simulator.structured_action_history = observation["structured_action_history"].duplicate(true)
	simulator.action_sequence = _max_action_sequence(simulator.structured_action_history)
	simulator._build_determinized_seats(observation, determinization_seed)
	return simulator

static func from_snapshot(snapshot: Dictionary):
	var simulator = new()
	simulator.phase = str(snapshot["phase"])
	simulator.round_index = int(snapshot["round_index"])
	simulator.active_seat = int(snapshot["active_seat"])
	simulator.pot = int(snapshot["pot"])
	simulator.seats = snapshot["seats"].duplicate(true)
	simulator.structured_action_history = snapshot["structured_action_history"].duplicate(true)
	simulator.last_bettor_seat = int(snapshot["last_bettor_seat"])
	simulator.bet_order = int(snapshot["bet_order"])
	simulator.action_sequence = int(snapshot.get("action_sequence", 0))
	simulator.next_starter_seat = int(snapshot.get("next_starter_seat", -1))
	simulator.winners.assign(snapshot.get("winners", []))
	simulator.payout = int(snapshot.get("payout", 0))
	simulator.round_result = str(snapshot.get("round_result", ""))
	return simulator

func clone():
	return from_snapshot(snapshot())

func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round_index": round_index,
		"active_seat": active_seat,
		"pot": pot,
		"seats": seats.duplicate(true),
		"structured_action_history": structured_action_history.duplicate(true),
		"last_bettor_seat": last_bettor_seat,
		"bet_order": bet_order,
		"action_sequence": action_sequence,
		"next_starter_seat": next_starter_seat,
		"winners": winners.duplicate(),
		"payout": payout,
		"round_result": round_result
	}

func state_hash() -> int:
	return JSON.stringify(snapshot()).hash()

func legal_actions() -> Array[Dictionary]:
	if phase != "playing" or active_seat < 0:
		return []
	var seat: Dictionary = seats[active_seat]
	return BotContractScript.legal_actions(int(seat["chips"]), pot, bool(seat["has_bet"]))

func build_context(actor_seat: int, decision_seed: int) -> Dictionary:
	assert(phase == "playing" and actor_seat == active_seat)
	var seat: Dictionary = seats[actor_seat]
	var public_seats: Array[Dictionary] = []
	for index in range(seats.size()):
		public_seats.append(BotContractScript.public_seat(seats[index], index))
	var observation := {
		"contract_version": BotContractScript.VERSION,
		"actor_seat": actor_seat,
		"own_cards": seat["cards"].duplicate(true),
		"own_hand_result": seat["hand"].duplicate(true),
		"pot": pot,
		"public_seats": public_seats,
		"active_seat": active_seat,
		"round_index": round_index,
		"structured_action_history": structured_action_history.duplicate(true),
		"last_bettor_seat": last_bettor_seat,
		"bet_order": bet_order
	}
	return {
		"observation": observation,
		"legal_actions": legal_actions(),
		"decision_seed": decision_seed
	}

func apply_decision(decision: Dictionary) -> bool:
	if phase != "playing" or active_seat < 0:
		return false
	var specs := legal_actions()
	if not BotContractScript.is_legal_decision(specs, decision):
		return false

	var actor := active_seat
	var action := str(decision["action"])
	var amount := int(decision["amount"])
	var pot_before := pot
	var seat: Dictionary = seats[actor]
	var chips_before := int(seat["chips"])
	var has_bet_before := bool(seat["has_bet"])
	var active_count_before := _active_indices().size()

	match action:
		"fold":
			seat["folded"] = true
		"bet":
			seat["chips"] = chips_before - amount
			seat["has_bet"] = true
			seat["last_bet"] = amount
			bet_order += 1
			seat["last_bet_order"] = bet_order
			pot += amount
			last_bettor_seat = actor
		"dai":
			seat["chips"] = chips_before - amount
			seat["last_bet"] = amount
			bet_order += 1
			seat["last_bet_order"] = bet_order
			pot += amount
			last_bettor_seat = actor
		"check":
			pass
	seats[actor] = seat
	_record_action(
		actor,
		action,
		amount,
		pot_before,
		chips_before,
		has_bet_before,
		active_count_before
	)
	_advance_after_action(actor)
	return true

func start_next_round(seed_value: int) -> bool:
	if phase != "round_end":
		return false
	var participants := _eligible_indices()
	if participants.size() <= 1:
		return false
	var starter := GameRulesScript.find_eligible_from(next_starter_seat, seats)

	phase = "playing"
	round_index += 1
	active_seat = -1
	last_bettor_seat = -1
	bet_order = 0
	winners = []
	payout = 0
	round_result = ""
	structured_action_history = []
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		var participating := participants.has(index)
		seat["participating"] = participating
		seat["folded"] = not participating
		seat["has_bet"] = false
		seat["last_bet"] = 0
		seat["last_bet_order"] = 0
		seat["cards"] = []
		seat["hand"] = {}
		seat["revealed"] = false
		seats[index] = seat

	if GameRulesScript.should_collect_ante(pot, participants.size()):
		for index in participants:
			var seat: Dictionary = seats[index]
			seat["chips"] = int(seat["chips"]) - 1
			seats[index] = seat
			pot += 1

	var deck := HandRulesScript.build_deck()
	_shuffle(deck, seed_value)
	for index in participants:
		var seat: Dictionary = seats[index]
		seat["cards"] = [deck.pop_back(), deck.pop_back()]
		seat["hand"] = HandRulesScript.evaluate(seat["cards"])
		seats[index] = seat

	active_seat = starter
	next_starter_seat = -1
	return active_seat >= 0

func _build_determinized_seats(observation: Dictionary, determinization_seed: int) -> void:
	var actor := int(observation["actor_seat"])
	var own_cards: Array = observation["own_cards"]
	var deck := HandRulesScript.build_deck()
	for own_card in own_cards:
		_remove_card(deck, own_card)
	_shuffle(deck, determinization_seed)

	seats = []
	for public_data in observation["public_seats"]:
		var seat: Dictionary = public_data.duplicate(true)
		seat["cards"] = []
		seat["hand"] = {}
		seat["revealed"] = false
		seats.append(seat)

	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		if not bool(seat["participating"]):
			continue
		if index == actor:
			seat["cards"] = own_cards.duplicate(true)
		else:
			seat["cards"] = [deck.pop_back(), deck.pop_back()]
		seat["hand"] = HandRulesScript.evaluate(seat["cards"])
		seats[index] = seat

func _advance_after_action(actor: int) -> void:
	var active := _active_indices()
	if active.size() <= 1:
		_finish_single_player(active)
		return

	var next := _next_active_index(actor)
	if next < 0 or (last_bettor_seat >= 0 and next == last_bettor_seat):
		_finish_showdown()
		return
	active_seat = next

func _finish_single_player(active: Array) -> void:
	active_seat = -1
	winners = []
	if active.is_empty():
		round_result = "empty"
		phase = "round_end"
		return

	var winner_index: int = active[0]
	var winner: Dictionary = seats[winner_index]
	winners = [winner_index]
	next_starter_seat = winner_index
	if bool(winner["has_bet"]):
		payout = GameRulesScript.winner_payout(pot, int(winner["last_bet"]))
		winner["chips"] = int(winner["chips"]) + payout
		pot -= payout
		round_result = "single_bet"
	else:
		winner["revealed"] = true
		if HandRulesScript.is_natural(winner["hand"]):
			payout = pot
			winner["chips"] = int(winner["chips"]) + payout
			pot = 0
			round_result = "natural_success"
		else:
			payout = 0
			round_result = "natural_failure"
	seats[winner_index] = winner
	phase = "round_end"

func _finish_showdown() -> void:
	active_seat = -1
	var active := _active_indices()
	if active.is_empty():
		winners = []
		round_result = "empty"
		phase = "round_end"
		return

	for index in active:
		var seat: Dictionary = seats[index]
		seat["revealed"] = true
		seats[index] = seat

	winners = [active[0]]
	for position in range(1, active.size()):
		var index: int = active[position]
		var comparison := HandRulesScript.compare(seats[index]["hand"], seats[winners[0]]["hand"])
		if comparison > 0:
			winners = [index]
		elif comparison == 0:
			winners.append(index)

	if winners.size() == 1:
		var winner_index := winners[0]
		var winner: Dictionary = seats[winner_index]
		payout = GameRulesScript.winner_payout(pot, int(winner["last_bet"]))
		winner["chips"] = int(winner["chips"]) + payout
		seats[winner_index] = winner
		pot -= payout
		next_starter_seat = winner_index
		round_result = "showdown_win"
	else:
		var starter := winners[0]
		for index in winners:
			if int(seats[index]["last_bet_order"]) > int(seats[starter]["last_bet_order"]):
				starter = index
		next_starter_seat = starter
		payout = 0
		round_result = "tie"
	phase = "round_end"

func _active_indices() -> Array:
	var result: Array = []
	for index in range(seats.size()):
		var seat: Dictionary = seats[index]
		if bool(seat["participating"]) and not bool(seat["folded"]):
			result.append(index)
	return result

func _eligible_indices() -> Array:
	var result: Array = []
	for index in range(seats.size()):
		if int(seats[index]["chips"]) > 0:
			result.append(index)
	return result

func _next_active_index(from_index: int) -> int:
	for offset in range(1, seats.size() + 1):
		var index := posmod(from_index + offset, seats.size())
		var seat: Dictionary = seats[index]
		if bool(seat["participating"]) and not bool(seat["folded"]):
			return index
	return -1

func _record_action(
	actor: int,
	action: String,
	amount: int,
	pot_before: int,
	chips_before: int,
	has_bet_before: bool,
	active_count_before: int
) -> void:
	action_sequence += 1
	structured_action_history.append({
		"round_index": round_index,
		"sequence": action_sequence,
		"type": "action",
		"actor_seat": actor,
		"action": action,
		"bet_kind": "eat" if action == "bet" and amount == pot_before else action,
		"amount": amount,
		"pot_before": pot_before,
		"pot_after": pot,
		"chips_before": chips_before,
		"chips_after": int(seats[actor]["chips"]),
		"has_bet_before": has_bet_before,
		"active_player_count_before": active_count_before
	})

static func _remove_card(deck: Array, target: Dictionary) -> void:
	for index in range(deck.size()):
		var card: Dictionary = deck[index]
		if str(card["rank"]) == str(target["rank"]) and str(card["suit"]) == str(target["suit"]):
			deck.remove_at(index)
			return
	assert(false, "观察中的手牌不属于当前牌组")

static func _max_action_sequence(history: Array) -> int:
	var result := 0
	for event in history:
		result = maxi(result, int(event.get("sequence", 0)))
	return result

static func _shuffle(deck: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(deck.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = deck[index]
		deck[index] = deck[swap_index]
		deck[swap_index] = temporary
