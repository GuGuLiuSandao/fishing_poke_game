class_name GameRules
extends RefCounted

const MIN_CHIPS := -1

static func should_collect_ante(pot: int, participant_count: int) -> bool:
	return pot <= floori(float(participant_count) / 2.0)

static func max_initial_bet(chips: int, pot: int) -> int:
	return maxi(0, mini(pot, chips - MIN_CHIPS))

static func can_dai(chips: int, pot: int) -> bool:
	return pot > 0 and chips - pot >= MIN_CHIPS

static func winner_payout(pot: int, last_bet: int) -> int:
	return mini(pot, last_bet * 2)

static func find_eligible_from(start_index: int, seats: Array) -> int:
	if seats.is_empty():
		return -1
	for offset in range(seats.size()):
		var index := posmod(start_index + offset, seats.size())
		if int(seats[index]["chips"]) > 0:
			return index
	return -1
