import 'package:test/test.dart';
import 'package:fivecrowns_core/fivecrowns_core.dart';

void main() {
  // Round 5 means 7 cards dealt, so 7s are wild
  const round = 5;

  group('MeldValidator - Runs', () {
    test('valid run with consecutive ranks same suit', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('valid run with 4 cards', () {
      final cards = [
        Card(Suit.spades, Rank.eight),
        Card(Suit.spades, Rank.nine),
        Card(Suit.spades, Rank.ten),
        Card(Suit.spades, Rank.jack),
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('invalid run - different suits', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.spades, Rank.four),
        Card(Suit.hearts, Rank.five),
      ];
      expect(MeldValidator.isValidRun(cards, round), false);
    });

    test('invalid run - non-consecutive', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
      ];
      expect(MeldValidator.isValidRun(cards, round), false);
    });

    test('invalid run - too few cards', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
      ];
      expect(MeldValidator.isValidRun(cards, round), false);
    });

    test('valid run with wild filling gap', () {
      // 3-4-?-6 where ? is wild (7 in round 5)
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.seven), // wild in round 5
        Card(Suit.hearts, Rank.six),
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('valid run with joker filling gap', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        const Card.joker(),
        Card(Suit.hearts, Rank.five),
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('valid run with multiple adjacent wilds', () {
      // 3-W-W-6 (wilds represent 4 and 5)
      final cards = [
        Card(Suit.hearts, Rank.three),
        const Card.joker(),
        Card(Suit.hearts, Rank.seven), // wild
        Card(Suit.hearts, Rank.six),
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('valid run all wilds', () {
      final cards = [
        const Card.joker(),
        const Card.joker(),
        Card(Suit.hearts, Rank.seven), // wild
      ];
      expect(MeldValidator.isValidRun(cards, round), true);
    });

    test('invalid run - duplicate natural rank', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.three), // duplicate
        Card(Suit.hearts, Rank.four),
      ];
      expect(MeldValidator.isValidRun(cards, round), false);
    });

    test('invalid run - not enough wilds for gaps', () {
      // 3-?-?-6 needs 2 wilds, only have 1
      final cards = [
        Card(Suit.hearts, Rank.three),
        const Card.joker(),
        Card(Suit.hearts, Rank.six),
      ];
      expect(MeldValidator.isValidRun(cards, round), false);
    });
  });

  group('MeldValidator - Books', () {
    test('valid book with same rank different suits', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.queen),
        Card(Suit.diamonds, Rank.queen),
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });

    test('valid book with 4 cards', () {
      final cards = [
        Card(Suit.hearts, Rank.jack),
        Card(Suit.spades, Rank.jack),
        Card(Suit.diamonds, Rank.jack),
        Card(Suit.clubs, Rank.jack),
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });

    test('invalid book - different ranks', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.king),
        Card(Suit.diamonds, Rank.queen),
      ];
      expect(MeldValidator.isValidBook(cards, round), false);
    });

    test('valid book - same suit allowed (two decks)', () {
      // Five Crowns uses two decks, so duplicate suits are valid in books
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.hearts, Rank.queen), // same suit - OK!
        Card(Suit.diamonds, Rank.queen),
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });

    test('invalid book - too few cards', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.queen),
      ];
      expect(MeldValidator.isValidBook(cards, round), false);
    });

    test('valid book with wild', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.queen),
        const Card.joker(),
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });

    test('valid book with multiple wilds', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        const Card.joker(),
        Card(Suit.diamonds, Rank.seven), // wild in round 5
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });

    test('valid book all wilds', () {
      final cards = [
        const Card.joker(),
        const Card.joker(),
        Card(Suit.hearts, Rank.seven), // wild
      ];
      expect(MeldValidator.isValidBook(cards, round), true);
    });
  });

  group('MeldValidator - isValidMeld', () {
    test('accepts valid run', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
      ];
      expect(MeldValidator.isValidMeld(cards, round), true);
      expect(MeldValidator.getMeldType(cards, round), MeldType.run);
    });

    test('accepts valid book', () {
      final cards = [
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.queen),
        Card(Suit.diamonds, Rank.queen),
      ];
      expect(MeldValidator.isValidMeld(cards, round), true);
      expect(MeldValidator.getMeldType(cards, round), MeldType.book);
    });

    test('rejects invalid meld', () {
      final cards = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.spades, Rank.five),
        Card(Suit.diamonds, Rank.queen),
      ];
      expect(MeldValidator.isValidMeld(cards, round), false);
      expect(MeldValidator.getMeldType(cards, round), isNull);
    });
  });

  group('MeldValidator - canGoOut', () {
    test('valid go out with single meld', () {
      // Round 1: 3 cards in hand, need 1 meld of 3 + 1 discard = 4 cards
      // Actually round 1 = 3 cards dealt, so need meld covering 3 cards and discard 1 = need 4 cards
      // Wait, going out means you meld ALL cards except the discard
      // So with 4 cards in hand after drawing: 3 card meld + 1 discard = going out

      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six), // discard
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.hearts, Rank.four),
          Card(Suit.hearts, Rank.five),
        ],
      ];
      final discard = Card(Suit.hearts, Rank.six);

      expect(MeldValidator.canGoOut(hand, melds, discard, round), true);
    });

    test('valid go out with multiple melds', () {
      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
        Card(Suit.spades, Rank.queen),
        Card(Suit.diamonds, Rank.queen),
        Card(Suit.clubs, Rank.queen),
        Card(Suit.hearts, Rank.six), // discard
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.hearts, Rank.four),
          Card(Suit.hearts, Rank.five),
        ],
        [
          Card(Suit.spades, Rank.queen),
          Card(Suit.diamonds, Rank.queen),
          Card(Suit.clubs, Rank.queen),
        ],
      ];
      final discard = Card(Suit.hearts, Rank.six);

      expect(MeldValidator.canGoOut(hand, melds, discard, round), true);
    });

    test('invalid go out - cards left over', () {
      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
        Card(Suit.hearts, Rank.eight), // leftover
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.hearts, Rank.four),
          Card(Suit.hearts, Rank.five),
        ],
      ];
      final discard = Card(Suit.hearts, Rank.six);

      expect(MeldValidator.canGoOut(hand, melds, discard, round), false);
    });

    test('invalid go out - invalid meld', () {
      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.spades, Rank.five), // breaks the run
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.spades, Rank.five),
          Card(Suit.hearts, Rank.five),
        ],
      ];
      final discard = Card(Suit.hearts, Rank.six);

      expect(MeldValidator.canGoOut(hand, melds, discard, round), false);
    });

    test('invalid go out - card not in hand', () {
      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.hearts, Rank.four),
          Card(Suit.spades, Rank.five), // not in hand
        ],
      ];
      final discard = Card(Suit.hearts, Rank.six);

      expect(MeldValidator.canGoOut(hand, melds, discard, round), false);
    });

    test('invalid go out - wrong discard', () {
      final hand = [
        Card(Suit.hearts, Rank.three),
        Card(Suit.hearts, Rank.four),
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
      ];
      final melds = [
        [
          Card(Suit.hearts, Rank.three),
          Card(Suit.hearts, Rank.four),
          Card(Suit.hearts, Rank.five),
        ],
      ];
      final discard = Card(Suit.hearts, Rank.eight); // not in hand

      expect(MeldValidator.canGoOut(hand, melds, discard, round), false);
    });
  });
}
