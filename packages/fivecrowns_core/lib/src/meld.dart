import 'card.dart';

/// Type of meld.
enum MeldType { run, book }

/// Represents a valid meld (run or book) of cards.
class Meld {
  final MeldType type;
  final List<Card> cards;

  const Meld._(this.type, this.cards);

  /// Creates a run meld (same suit, consecutive ranks).
  factory Meld.run(List<Card> cards) {
    if (cards.length < 3) {
      throw ArgumentError('Run must have at least 3 cards');
    }
    return Meld._(MeldType.run, List.unmodifiable(cards));
  }

  /// Creates a book meld (same rank, different suits).
  factory Meld.book(List<Card> cards) {
    if (cards.length < 3) {
      throw ArgumentError('Book must have at least 3 cards');
    }
    return Meld._(MeldType.book, List.unmodifiable(cards));
  }

  /// Encodes meld to list of card codes.
  List<String> encode() => cards.map((c) => c.encode()).toList();
}

/// Validates melds according to Five Crowns rules.
class MeldValidator {
  /// Validates a proposed run (same suit, consecutive ranks).
  /// Wild cards (jokers + rotating wild) can substitute for any card.
  /// Returns true if valid.
  static bool isValidRun(List<Card> cards, int roundNumber) {
    if (cards.length < 3) return false;

    // Separate wilds from natural cards
    final wilds = <Card>[];
    final naturals = <Card>[];
    for (final card in cards) {
      if (card.isWild(roundNumber)) {
        wilds.add(card);
      } else {
        naturals.add(card);
      }
    }

    // If all wilds, valid if at least 3
    if (naturals.isEmpty) return cards.length >= 3;

    // All natural cards must be same suit
    final suit = naturals.first.suit;
    if (!naturals.every((c) => c.suit == suit)) return false;

    // Sort naturals by rank value
    naturals.sort((a, b) => a.rank!.value.compareTo(b.rank!.value));

    // Check for duplicates in naturals
    for (var i = 0; i < naturals.length - 1; i++) {
      if (naturals[i].rank == naturals[i + 1].rank) return false;
    }

    // Calculate gaps that need to be filled by wilds
    var wildsNeeded = 0;
    for (var i = 0; i < naturals.length - 1; i++) {
      final gap = naturals[i + 1].rank!.value - naturals[i].rank!.value - 1;
      wildsNeeded += gap;
    }

    // We have enough wilds to fill gaps
    return wilds.length >= wildsNeeded;
  }

  /// Validates a proposed book (same rank, different suits for naturals).
  /// Wild cards can substitute for any card of that rank.
  /// Returns true if valid.
  static bool isValidBook(List<Card> cards, int roundNumber) {
    if (cards.length < 3) return false;

    // Separate wilds from natural cards
    final naturals = <Card>[];
    for (final card in cards) {
      if (!card.isWild(roundNumber)) {
        naturals.add(card);
      }
    }

    // If all wilds, valid if at least 3
    if (naturals.isEmpty) return cards.length >= 3;

    // All natural cards must be same rank
    final rank = naturals.first.rank;
    if (!naturals.every((c) => c.rank == rank)) return false;

    // Note: Duplicate suits ARE allowed in books since Five Crowns uses two decks.
    // The only requirement is that all natural cards have the same rank.

    return true;
  }

  /// Validates a meld (either run or book).
  static bool isValidMeld(List<Card> cards, int roundNumber) {
    return isValidRun(cards, roundNumber) || isValidBook(cards, roundNumber);
  }

  /// Determines the type of a valid meld.
  /// Returns null if the meld is invalid.
  static MeldType? getMeldType(List<Card> cards, int roundNumber) {
    if (isValidRun(cards, roundNumber)) return MeldType.run;
    if (isValidBook(cards, roundNumber)) return MeldType.book;
    return null;
  }

  /// Validates that new cards can extend an existing meld.
  /// Returns true if adding the new cards to the meld keeps it valid.
  static bool canExtendMeld(Meld existingMeld, List<Card> newCards, int roundNumber) {
    if (newCards.isEmpty) return false;

    // Combine existing meld cards with new cards
    final combined = [...existingMeld.cards, ...newCards];

    // Check if the combined cards form a valid meld of the same type
    if (existingMeld.type == MeldType.run) {
      return isValidRun(combined, roundNumber);
    } else {
      return isValidBook(combined, roundNumber);
    }
  }

  /// Extends a meld with new cards and returns the new meld.
  /// Throws if the extension is invalid.
  static Meld extendMeld(Meld existingMeld, List<Card> newCards, int roundNumber) {
    if (!canExtendMeld(existingMeld, newCards, roundNumber)) {
      throw StateError('Cannot extend meld with provided cards');
    }

    final combined = [...existingMeld.cards, ...newCards];

    // For runs, sort the cards properly
    if (existingMeld.type == MeldType.run) {
      // Separate wilds and naturals, sort naturals, then interleave
      final wilds = <Card>[];
      final naturals = <Card>[];
      for (final card in combined) {
        if (card.isWild(roundNumber)) {
          wilds.add(card);
        } else {
          naturals.add(card);
        }
      }

      // Sort naturals by rank
      naturals.sort((a, b) => a.rank!.value.compareTo(b.rank!.value));

      // Build sorted run with wilds filling gaps
      final sorted = <Card>[];
      var wildIdx = 0;
      for (var i = 0; i < naturals.length; i++) {
        if (i > 0) {
          // Fill gaps with wilds
          final gap = naturals[i].rank!.value - naturals[i - 1].rank!.value - 1;
          for (var j = 0; j < gap && wildIdx < wilds.length; j++) {
            sorted.add(wilds[wildIdx++]);
          }
        }
        sorted.add(naturals[i]);
      }
      // Add remaining wilds at the end
      while (wildIdx < wilds.length) {
        sorted.add(wilds[wildIdx++]);
      }

      return Meld._(MeldType.run, List.unmodifiable(sorted));
    } else {
      // For books, order doesn't matter
      return Meld._(MeldType.book, List.unmodifiable(combined));
    }
  }

  /// Validates that a collection of melds uses all cards exactly once
  /// and leaves exactly one card for discarding (for going out).
  static bool canGoOut(
    List<Card> hand,
    List<List<Card>> proposedMelds,
    Card discard,
    int roundNumber,
  ) {
    // Count all cards in melds + discard
    final meldCards = <Card>[];
    for (final meld in proposedMelds) {
      meldCards.addAll(meld);
    }

    // Total should equal hand size
    if (meldCards.length + 1 != hand.length) return false;

    // Validate each meld
    for (final meld in proposedMelds) {
      if (!isValidMeld(meld, roundNumber)) return false;
    }

    // Verify all cards come from hand (with proper duplicate handling)
    final handCopy = List<Card>.from(hand);

    for (final card in meldCards) {
      final idx = handCopy.indexWhere((c) => c == card);
      if (idx == -1) return false;
      handCopy.removeAt(idx);
    }

    // Only discard should remain
    if (handCopy.length != 1) return false;
    if (handCopy.first != discard) return false;

    return true;
  }
}
