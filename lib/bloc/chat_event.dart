import 'package:equatable/equatable.dart';

// ─── Equatable ────────────────────────────────────────────────────────────────
//
// Same idea as TransactionEvent: Equatable lets the BLoC compare two events by
// their field values instead of by identity, so e.g. dispatching the exact
// same ChatMessageSent twice in a row is recognized as "the same thing" rather
// than two unrelated objects that happen to look alike.

// ─── Base class ───────────────────────────────────────────────────────────────
//
// Every event the chat screen can produce "is a" ChatEvent. This is the shared
// contract the BLoC listens for — like every Express route handler receiving
// a `req`, regardless of whether it's a GET or a POST.
abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

// ─── Events ───────────────────────────────────────────────────────────────────
//
// Events describe things that HAPPENED on the chat screen — "the screen just
// opened", "the user hit send", "the user wants a clean slate" — not what the
// screen should look like afterwards. The BLoC decides that part.

/// Fired when: the chat screen first opens.
///
/// Carries: a pre-built summary of the user's transaction data (e.g. "This
/// month: spent ₹12,400, mostly on Food (₹4,200) and Bills (₹3,100)..."). The
/// BLoC hangs onto this and resends it with every message so the AI always has
/// fresh context about the user's spending — without it, the AI would just be
/// a generic chatbot with no idea what "my spending" even refers to.
///
/// This also kicks off loading the saved API key/provider from
/// SharedPreferences and sets up the initial greeting bubble.
class ChatInitialized extends ChatEvent {
  final String transactionSummary;

  const ChatInitialized(this.transactionSummary);

  @override
  List<Object?> get props => [transactionSummary];
}

/// Fired when: the user types a message and taps the send button.
///
/// Carries: the raw text the user typed. The BLoC turns this into a user
/// bubble immediately, then ships it off to the AI provider along with the
/// transaction summary and recent conversation history.
class ChatMessageSent extends ChatEvent {
  final String message;

  const ChatMessageSent(this.message);

  @override
  List<Object?> get props => [message];
}

/// Fired when: the user wants to wipe the conversation and start fresh (e.g.
/// taps a "New chat" / broom icon in the app bar).
///
/// Carries: nothing — it's a blanket "reset back to just the greeting" signal,
/// the same way TransactionAllDeleteRequested carries nothing but means "wipe
/// everything".
class ChatCleared extends ChatEvent {
  const ChatCleared();

  @override
  List<Object?> get props => [];
}
