class_name HandRules
extends RefCounted

const COLOR_RED := "red"
const COLOR_BLACK := "black"

const CATEGORY_PAIR := 13
const CATEGORY_SUPREME := 14

static func build_deck() -> Array:
	var deck: Array = []
	deck.append(_make_card("JOKER", "JOKER"))
	deck.append(_make_card("3", "H"))

	for rank in ["Q", "J", "9", "5", "2"]:
		for suit in ["H", "D"]:
			deck.append(_make_card(rank, suit))

	for rank in ["10", "8", "7", "6", "4"]:
		for suit in ["H", "D", "S", "C"]:
			deck.append(_make_card(rank, suit))

	return deck

static func evaluate(cards: Array) -> Dictionary:
	assert(cards.size() == 2, "每手牌必须正好包含两张牌")
	var first: Dictionary = cards[0]
	var second: Dictionary = cards[1]
	var ranks: Array = [str(first["rank"]), str(second["rank"])]

	if ranks.has("JOKER") and ranks.has("3"):
		return _result(CATEGORY_SUPREME, 0, 0, 9, "至尊")

	if first["rank"] == second["rank"] and first["color"] == second["color"]:
		var pair_rank := _pair_rank(first)
		return _result(CATEGORY_PAIR, pair_rank, 0, 9, _pair_name(first, pair_rank))

	if _contains_both(ranks, "Q", "9"):
		return _result(12, 0, 0, 9, "Q九")
	if _contains_both(ranks, "Q", "8"):
		return _result(11, 0, 0, 9, "Q八")
	if _contains_both(ranks, "2", "8"):
		return _result(10, 0, 0, 9, "二八")

	var points := (int(first["value"]) + int(second["value"])) % 10
	var weight := maxi(_card_weight(first), _card_weight(second))
	return _result(points, 0, weight, points, "%d点" % points)

static func compare(first: Dictionary, second: Dictionary) -> int:
	for key in ["category", "sub_rank", "weight"]:
		var difference := int(first[key]) - int(second[key])
		if difference != 0:
			return 1 if difference > 0 else -1
	return 0

static func is_natural(hand_result: Dictionary) -> bool:
	return int(hand_result["category"]) >= 8

static func cards_text(cards: Array) -> String:
	var labels: PackedStringArray = []
	for card in cards:
		labels.append(str(card["label"]))
	return " ".join(labels)

static func _make_card(rank: String, suit: String) -> Dictionary:
	var color := COLOR_RED if suit in ["H", "D", "JOKER"] else COLOR_BLACK
	var label := "大王" if rank == "JOKER" else "%s%s" % [_suit_symbol(suit), rank]
	return {
		"rank": rank,
		"suit": suit,
		"color": color,
		"value": _card_value(rank),
		"label": label
	}

static func _card_value(rank: String) -> int:
	match rank:
		"JOKER":
			return 6
		"Q":
			return 12
		"J":
			return 11
		_:
			return int(rank)

static func _suit_symbol(suit: String) -> String:
	match suit:
		"H":
			return "♥"
		"D":
			return "♦"
		"S":
			return "♠"
		"C":
			return "♣"
	return ""

static func _contains_both(ranks: Array, first: String, second: String) -> bool:
	return ranks.has(first) and ranks.has(second)

static func _pair_rank(card: Dictionary) -> int:
	var rank := str(card["rank"])
	var color := str(card["color"])
	if rank == "Q":
		return 100
	if rank == "2":
		return 80
	if rank == "8" and color == COLOR_RED:
		return 60
	if rank == "4" and color == COLOR_RED:
		return 40
	if rank == "10" and color == COLOR_BLACK:
		return 20
	return 1

static func _pair_name(card: Dictionary, pair_rank: int) -> String:
	match pair_rank:
		100:
			return "Q对"
		80:
			return "2对"
		60:
			return "红8对"
		40:
			return "红4对"
		20:
			return "黑10对"
	return "普通对子"

static func _card_weight(card: Dictionary) -> int:
	var rank := str(card["rank"])
	var color := str(card["color"])
	if rank == "Q":
		return 5
	if rank == "2":
		return 4
	if rank == "8" and color == COLOR_RED:
		return 3
	if rank == "4" and color == COLOR_RED:
		return 2
	if rank == "10" and color == COLOR_BLACK:
		return 1
	return 0

static func _result(
	category: int,
	sub_rank: int,
	weight: int,
	points: int,
	display_name: String
) -> Dictionary:
	return {
		"category": category,
		"sub_rank": sub_rank,
		"weight": weight,
		"points": points,
		"name": display_name
	}
