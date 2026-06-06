import 'package:equatable/equatable.dart';

// ─── ChatMessage ──────────────────────────────────────────────────────────────
//
// A single bubble in the conversation. This is deliberately a *plain* class —
// not Equatable — because every message is unique by nature (its own text, its
// own timestamp), so there's no meaningful sense in which two messages could
// be "the same" the way two identical TransactionLoadRequested events could.
// It lives here (in the state file) because it's purely a piece of UI state —
// it never needs to be compared, only rendered.
class ChatMessage {
  /// What's shown inside the bubble — either what the user typed, or the
  /// text the AI replied with (or a friendly error string).
  final String text;

  /// Which side of the chat this bubble appears on:
  ///   true  → the user's own message (right-aligned, "their" bubble)
  ///   false → the AI's message (left-aligned, "its" bubble)
  /// The UI uses this single flag to pick alignment, color, and avatar.
  final bool isUser;

  /// When this message was created. Lets the UI show "2:45 PM" style
  /// timestamps under each bubble, and is also handy for ordering/debugging.
  final DateTime timestamp;

  /// True only for messages that represent something going wrong (missing
  /// API key, network failure, bad response, ...). The UI uses this to tint
  /// the bubble red/orange instead of the normal AI bubble color, so the user
  /// can immediately tell "this isn't the assistant talking, something broke".
  final bool isError;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    required this.isError,
  });

  /// Builds a bubble for something the *user* typed.
  ///
  /// Always right-aligned, never an error — the user can't "error", they can
  /// only type text. Timestamp defaults to "right now" since user messages are
  /// always created the instant they're sent.
  factory ChatMessage.user(String text) {
    return ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      isError: false,
    );
  }

  /// Builds a bubble for a normal reply from the AI.
  ///
  /// Left-aligned, not an error — this is the "happy path" assistant bubble
  /// the user sees after asking a question like "how much did I spend on
  /// food this month?".
  factory ChatMessage.ai(String text) {
    return ChatMessage(
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
      isError: false,
    );
  }

  /// Builds a bubble that represents a problem — missing API key, a failed
  /// network request, an unexpected response shape, etc.
  ///
  /// Still rendered on the AI's side of the conversation (it's the assistant
  /// "speaking", just badly), but flagged with [isError] so the UI can give it
  /// a distinct red-tinted look that says "this is a system message, not a
  /// real answer to your question".
  factory ChatMessage.error(String text) {
    return ChatMessage(
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
      isError: true,
    );
  }
}

// ─── States ───────────────────────────────────────────────────────────────────
//
// Just like TransactionState, every ChatState is a snapshot of "what the chat
// screen should look like right now". The BLoC emits a new one, the screen
// rebuilds to match — there's no in-between mutation, the UI is always purely
// a reflection of the latest state.
abstract class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

/// The very first state, before the chat screen has finished loading the
/// saved API key/provider and building its greeting message.
///
/// The UI should show a brief loading spinner here — it's the split-second
/// gap between "screen opened" and "we know whether you have an API key yet".
class ChatInitial extends ChatState {
  const ChatInitial();

  @override
  List<Object?> get props => [];
}

/// The chat is up and running — this is the state the screen spends almost
/// all of its time in, the same way TransactionLoaded is the "everything's
/// fine, here's what to draw" state for the transactions screens.
class ChatReady extends ChatState {
  /// The full conversation so far, oldest message first. The UI renders this
  /// directly as a scrolling list of bubbles (typically reversed so the
  /// newest message sits at the bottom, like any chat app).
  final List<ChatMessage> messages;

  /// True while we're waiting on the AI API to respond. The UI shows a
  /// "typing..." indicator bubble while this is true, and disables the send
  /// button so the user can't fire off a second message mid-flight.
  final bool isLoading;

  /// False when SharedPreferences has no saved API key (or it's an empty
  /// string). The UI uses this to show a persistent "please add your API key
  /// in Settings" banner/message instead of pretending the chat will work.
  final bool hasApiKey;

  /// A pre-built textual summary of the user's transaction data (totals,
  /// top categories, etc). Kept here — rather than re-fetched per message —
  /// so it can be resent as context with *every* outgoing message without
  /// hitting the database again. Think of it as a sticky note the AI is
  /// handed at the start of every turn: "by the way, here's what you're
  /// talking about".
  final String transactionSummary;

  /// The user's saved AI API key, loaded once from SharedPreferences.
  /// `null` means "no key saved yet" — which is exactly when [hasApiKey]
  /// is false and the chat can't actually call out to an AI provider.
  final String? apiKey;

  /// Which AI provider to talk to: 'OpenAI', 'Gemini', or 'Claude'.
  /// Defaults to 'Claude' when nothing has been saved yet, so a brand-new
  /// install still has a sensible provider chosen the moment a key is added.
  final String aiProvider;

  const ChatReady({
    required this.messages,
    required this.isLoading,
    required this.hasApiKey,
    required this.transactionSummary,
    required this.apiKey,
    required this.aiProvider,
  });

  // Returns a copy of this state with some fields replaced — same pattern as
  // TransactionLoaded.copyWith. Every parameter is nullable, and `??` falls
  // back to the existing value, so e.g. _onMessageSent can update just
  // `messages` and `isLoading` without having to re-specify the API key,
  // provider, and transaction summary every single time.
  ChatReady copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? hasApiKey,
    String? transactionSummary,
    String? apiKey,
    String? aiProvider,
  }) {
    return ChatReady(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      transactionSummary: transactionSummary ?? this.transactionSummary,
      apiKey: apiKey ?? this.apiKey,
      aiProvider: aiProvider ?? this.aiProvider,
    );
  }

  @override
  List<Object?> get props => [
        messages,
        isLoading,
        hasApiKey,
        transactionSummary,
        apiKey,
        aiProvider,
      ];
}

/// Something went badly enough wrong that the chat screen itself can't be
/// shown — as opposed to a single failed message, which is handled inline as
/// a [ChatMessage.error] bubble inside [ChatReady] without losing the rest of
/// the conversation.
///
/// The UI should show a full-screen error message (and maybe a retry button)
/// while this is active.
class ChatError extends ChatState {
  /// A human-readable description of what went wrong, suitable for showing
  /// directly to the user.
  final String message;

  const ChatError(this.message);

  @override
  List<Object?> get props => [message];
}
