import random
from enum import IntEnum

class Color(IntEnum):
    RED = 1
    BLACK = 2

class Suit(IntEnum):
    HEARTS = 1
    DIAMONDS = 2
    SPADES = 3
    CLUBS = 4
    NONE = 0

    def to_color(self):
        if self in [Suit.HEARTS, Suit.DIAMONDS]:
            return Color.RED
        if self in [Suit.SPADES, Suit.CLUBS]:
            return Color.BLACK
        return None

class Card:
    def __init__(self, name, value, suit, weight_rank=0):
        self.name = name
        self.value = value
        self.suit = suit
        self.color = suit.to_color() if suit != Suit.NONE else Color.RED
        self.weight_rank = weight_rank

    def __repr__(self):
        suit_symbols = {
            Suit.HEARTS: "♥",
            Suit.DIAMONDS: "♦",
            Suit.SPADES: "♠",
            Suit.CLUBS: "♣",
            Suit.NONE: ""
        }
        symbol = suit_symbols.get(self.suit, "")
        if self.name == "大王":
            return "大王"
        return f"{symbol}{self.name}"

class HandRank(IntEnum):
    POINT_0 = 0
    POINT_1 = 1
    POINT_2 = 2
    POINT_3 = 3
    POINT_4 = 4
    POINT_5 = 5
    POINT_6 = 6
    POINT_7 = 7
    POINT_8 = 8
    POINT_9 = 9
    SPECIAL_2_8 = 10
    SPECIAL_Q_8 = 11
    SPECIAL_Q_9 = 12
    PAIR = 13
    SUPREME = 14

class Hand:
    def __init__(self, cards):
        self.cards = cards
        self.rank, self.sub_rank, self.max_weight = self._evaluate()

    def _evaluate(self):
        c1, c2 = self.cards
        names = {c1.name, c2.name}
        if "大王" in names and "3" in names:
            return HandRank.SUPREME, 0, 0
        if c1.name == c2.name and c1.color == c2.color:
            sub_rank = 0
            if c1.name == "Q": sub_rank = 100
            elif c1.name == "2": sub_rank = 80
            elif c1.name == "8" and c1.color == Color.RED: sub_rank = 60
            elif c1.name == "4" and c1.color == Color.RED: sub_rank = 40
            elif c1.name == "10" and c1.color == Color.BLACK: sub_rank = 20
            else: sub_rank = 1
            return HandRank.PAIR, sub_rank, 0
        if "Q" in names and "9" in names:
            return HandRank.SPECIAL_Q_9, 0, 0
        if "Q" in names and "8" in names:
            return HandRank.SPECIAL_Q_8, 0, 0
        if "2" in names and "8" in names:
            return HandRank.SPECIAL_2_8, 0, 0
        total_points = (c1.value + c2.value) % 10
        max_weight = max(c1.weight_rank, c2.weight_rank)
        return HandRank(total_points), 0, max_weight

    def __repr__(self):
        return f"{self.cards}"

    def __gt__(self, other):
        if self.rank != other.rank:
            return self.rank > other.rank
        if self.rank == HandRank.PAIR:
            return self.sub_rank > other.sub_rank
        return self.max_weight > other.max_weight

    def __eq__(self, other):
        return (self.rank == other.rank and 
                self.sub_rank == other.sub_rank and 
                self.max_weight == other.max_weight)

def build_deck():
    deck = []
    deck.append(Card("大王", 6, Suit.NONE))
    deck.append(Card("3", 3, Suit.HEARTS))
    red_suits = [Suit.HEARTS, Suit.DIAMONDS]
    for s in red_suits: deck.append(Card("Q", 12, s, 5))
    for s in red_suits: deck.append(Card("J", 11, s))
    for s in red_suits: deck.append(Card("9", 9, s))
    for s in red_suits: deck.append(Card("5", 5, s))
    for s in red_suits: deck.append(Card("2", 2, s, 4))
    mixed_names = ["10", "8", "7", "6", "4"]
    for name in mixed_names:
        val = int(name)
        red_weight = 3 if name == "8" else (2 if name == "4" else 0)
        black_weight = 1 if name == "10" else 0
        deck.append(Card(name, val, Suit.HEARTS, red_weight))
        deck.append(Card(name, val, Suit.DIAMONDS, red_weight))
        deck.append(Card(name, val, Suit.SPADES, black_weight))
        deck.append(Card(name, val, Suit.CLUBS, black_weight))
    return deck

def deal_hands(player_names, rng=None):
    rng = rng or random.Random()
    deck = build_deck()
    rng.shuffle(deck)
    hands = []
    for name in player_names:
        hand_cards = [deck.pop(), deck.pop()]
        hands.append((name, Hand(hand_cards)))
    return hands

def rank_hands(hands):
    return sorted(hands, key=lambda x: (x[1].rank, x[1].sub_rank, x[1].max_weight), reverse=True)

def point_value(hand):
    if hand.rank <= HandRank.POINT_9:
        return hand.rank.value
    return 9
