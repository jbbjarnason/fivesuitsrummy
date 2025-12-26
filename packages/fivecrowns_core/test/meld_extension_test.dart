import 'package:fivecrowns_core/fivecrowns_core.dart';
import 'package:test/test.dart';

void main() {
  group('MeldValidator.canExtendMeld', () {
    group('Extending Runs', () {
      test('can extend run at the back with consecutive card', () {
        // Round 1: wild is 3
        final run = Meld.run([
          Card(Suit.hearts, Rank.four),
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
        ]);

        final newCards = [Card(Suit.hearts, Rank.seven)];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isTrue);
      });

      test('can extend run at the front with consecutive card', () {
        final run = Meld.run([
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
          Card(Suit.hearts, Rank.seven),
        ]);

        final newCards = [Card(Suit.hearts, Rank.four)];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isTrue);
      });

      test('can extend run with multiple consecutive cards', () {
        final run = Meld.run([
          Card(Suit.spades, Rank.five),
          Card(Suit.spades, Rank.six),
          Card(Suit.spades, Rank.seven),
        ]);

        final newCards = [
          Card(Suit.spades, Rank.eight),
          Card(Suit.spades, Rank.nine),
        ];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isTrue);
      });

      test('cannot extend run with wrong suit', () {
        final run = Meld.run([
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
          Card(Suit.hearts, Rank.seven),
        ]);

        final newCards = [Card(Suit.spades, Rank.eight)];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isFalse);
      });

      test('cannot extend run with non-consecutive rank', () {
        final run = Meld.run([
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
          Card(Suit.hearts, Rank.seven),
        ]);

        final newCards = [Card(Suit.hearts, Rank.nine)];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isFalse);
      });

      test('can extend run with wild card filling gap', () {
        final run = Meld.run([
          Card(Suit.clubs, Rank.five),
          Card(Suit.clubs, Rank.six),
          Card(Suit.clubs, Rank.seven),
        ]);

        // Wild (3 in round 1) + 9 fills the gap to 8
        final newCards = [
          Card(Suit.clubs, Rank.three), // wild in round 1
          Card(Suit.clubs, Rank.nine),
        ];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isTrue);
      });

      test('can extend run with joker', () {
        final run = Meld.run([
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
          Card(Suit.hearts, Rank.seven),
        ]);

        final newCards = [Card.joker()];

        expect(MeldValidator.canExtendMeld(run, newCards, 1), isTrue);
      });
    });

    group('Extending Books', () {
      test('can extend book with card of same rank different suit', () {
        final book = Meld.book([
          Card(Suit.hearts, Rank.seven),
          Card(Suit.spades, Rank.seven),
          Card(Suit.clubs, Rank.seven),
        ]);

        final newCards = [Card(Suit.diamonds, Rank.seven)];

        expect(MeldValidator.canExtendMeld(book, newCards, 1), isTrue);
      });

      test('can extend book with wild card', () {
        final book = Meld.book([
          Card(Suit.hearts, Rank.seven),
          Card(Suit.spades, Rank.seven),
          Card(Suit.clubs, Rank.seven),
        ]);

        // Round 1: 3 is wild
        final newCards = [Card(Suit.hearts, Rank.three)];

        expect(MeldValidator.canExtendMeld(book, newCards, 1), isTrue);
      });

      test('cannot extend book with different rank', () {
        final book = Meld.book([
          Card(Suit.hearts, Rank.seven),
          Card(Suit.spades, Rank.seven),
          Card(Suit.clubs, Rank.seven),
        ]);

        final newCards = [Card(Suit.diamonds, Rank.eight)];

        expect(MeldValidator.canExtendMeld(book, newCards, 1), isFalse);
      });

      test('CAN extend book with duplicate suit (two decks)', () {
        // Five Crowns uses two decks, so duplicate suits are allowed
        final book = Meld.book([
          Card(Suit.hearts, Rank.seven),
          Card(Suit.spades, Rank.seven),
          Card(Suit.clubs, Rank.seven),
        ]);

        // hearts is already in the book - but that's OK with two decks!
        final newCards = [Card(Suit.hearts, Rank.seven)];

        expect(MeldValidator.canExtendMeld(book, newCards, 1), isTrue);
      });

      test('can extend book with star suit (5th suit)', () {
        final book = Meld.book([
          Card(Suit.hearts, Rank.king),
          Card(Suit.spades, Rank.king),
          Card(Suit.clubs, Rank.king),
        ]);

        final newCards = [Card(Suit.stars, Rank.king)];

        expect(MeldValidator.canExtendMeld(book, newCards, 1), isTrue);
      });
    });

    group('Edge Cases', () {
      test('cannot extend with empty cards', () {
        final run = Meld.run([
          Card(Suit.hearts, Rank.five),
          Card(Suit.hearts, Rank.six),
          Card(Suit.hearts, Rank.seven),
        ]);

        expect(MeldValidator.canExtendMeld(run, [], 1), isFalse);
      });
    });
  });

  group('MeldValidator.extendMeld', () {
    test('extends run and returns sorted meld', () {
      final run = Meld.run([
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
        Card(Suit.hearts, Rank.seven),
      ]);

      final newCards = [Card(Suit.hearts, Rank.four)];
      final extended = MeldValidator.extendMeld(run, newCards, 1);

      expect(extended.type, equals(MeldType.run));
      expect(extended.cards.length, equals(4));
      // Should be sorted: 4, 5, 6, 7
      expect(extended.cards[0].rank, equals(Rank.four));
      expect(extended.cards[1].rank, equals(Rank.five));
      expect(extended.cards[2].rank, equals(Rank.six));
      expect(extended.cards[3].rank, equals(Rank.seven));
    });

    test('extends book and maintains all cards', () {
      final book = Meld.book([
        Card(Suit.hearts, Rank.queen),
        Card(Suit.spades, Rank.queen),
        Card(Suit.clubs, Rank.queen),
      ]);

      final newCards = [Card(Suit.diamonds, Rank.queen)];
      final extended = MeldValidator.extendMeld(book, newCards, 1);

      expect(extended.type, equals(MeldType.book));
      expect(extended.cards.length, equals(4));
    });

    test('throws on invalid extension', () {
      final run = Meld.run([
        Card(Suit.hearts, Rank.five),
        Card(Suit.hearts, Rank.six),
        Card(Suit.hearts, Rank.seven),
      ]);

      final newCards = [Card(Suit.spades, Rank.ten)];

      expect(
        () => MeldValidator.extendMeld(run, newCards, 1),
        throwsStateError,
      );
    });
  });
}
