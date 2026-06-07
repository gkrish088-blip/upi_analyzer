import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/chat_bloc.dart';
import 'bloc/chat_event.dart';
import 'bloc/chat_state.dart';
import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WHAT THIS SCREEN DOES
// ─────────────────────────────────────────────────────────────────────────────
//
// AskAIScreen is the "chat with your money" screen — a ChatGPT-style
// conversation view where the user can ask plain-English questions about their
// UPI spending ("how much did I spend on food this month?") and get answers
// from an AI provider (Claude / OpenAI / Gemini, whichever the user picked in
// Settings).
//
// IMPORTANT: this screen does NOT talk to the network, SharedPreferences, or
// the AI provider directly. All of that lives inside ChatBloc. This screen's
// only job is to:
//   1. Tell ChatBloc "I just opened, here's a summary of the user's spending"
//      (once, in initState).
//   2. Show whatever ChatState ChatBloc is currently in (loading spinner,
//      the chat itself, or an error).
//   3. Forward user actions ("I typed a message and hit send") to ChatBloc as
//      events, and let ChatBloc decide what happens next.
//
// This is the same BLoC pattern used by TransactionBloc elsewhere in the app:
// the screen is a "dumb" rendering of whatever state the BLoC is in, and the
// BLoC is the only thing that actually knows how to fetch/compute data.
// ─────────────────────────────────────────────────────────────────────────────
class AskAIScreen extends StatefulWidget {
  const AskAIScreen({super.key});

  @override
  State<AskAIScreen> createState() => _AskAIScreenState();
}

class _AskAIScreenState extends State<AskAIScreen> {
  // Holds whatever text the user is currently typing into the message box.
  // We need a controller (rather than just reading the TextField's value)
  // so we can also *clear* the box programmatically once a message is sent.
  final TextEditingController _controller = TextEditingController();

  // Lets us scroll the message list programmatically — specifically, to
  // automatically jump to the bottom every time a new message appears, the
  // same way every chat app keeps the newest message in view.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    // Controllers hold onto resources (like animation tickers and listeners)
    // that won't be cleaned up automatically. Always dispose them when the
    // widget that owns them goes away, or you'll leak memory.
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // initState — runs exactly ONCE, the moment this screen is first created
  // ───────────────────────────────────────────────────────────────────────────
  //
  // This is where we kick off the conversation by telling ChatBloc "the chat
  // screen just opened". We can't do this work inside `build()` because
  // `build()` can be called many times (every time the UI needs to redraw),
  // and we only want to fire this startup event once.
  //
  // Step by step, what happens here:
  //   1. We reach into TransactionBloc (already loaded elsewhere in the app —
  //      see MultiBlocProvider in main.dart) and read its *current* state.
  //      `context.read<T>()` grabs the bloc without subscribing to future
  //      changes — perfect for a one-off read like this.
  //   2. If transactions have finished loading (TransactionLoaded), we build
  //      a plain-text "cheat sheet" describing the user's spending: totals,
  //      savings rate, category breakdown, day-of-week breakdown, etc.
  //   3. We hand that summary to ChatBloc via a ChatInitialized event.
  //      ChatBloc will store it and re-send it as context with *every* future
  //      message — that's how the AI "knows" what "my spending" refers to,
  //      without us ever sending raw SMS messages or transaction rows over
  //      the network (good for privacy AND keeps each request small).
  @override
  void initState() {
    super.initState();

    // Grab whatever state TransactionBloc is currently sitting in. This does
    // NOT rebuild this widget when TransactionBloc changes later — we only
    // need a one-time snapshot to build our opening summary.
    final transactionState = context.read<TransactionBloc>().state;

    // Default text used if transactions haven't finished loading yet (e.g.
    // the user opened the chat screen before the SMS sync completed). The AI
    // will see this exact sentence as its "Transaction Summary" and should
    // nudge the user to sync first instead of guessing at numbers.
    String summary = 'No transaction data available yet. '
        'Ask the user to sync their transactions first.';

    if (transactionState is TransactionLoaded) {
      // .toStringAsFixed(0) rounds these money values to whole rupees so the
      // AI sees clean numbers like "₹12,400" instead of "₹12400.3333333".
      final spent = transactionState.totalSpent.toStringAsFixed(0);
      final income = transactionState.totalIncome.toStringAsFixed(0);
      // Savings rate is a percentage, so one decimal place ("23.4%") reads
      // more naturally than a whole number or a long float.
      final savings = transactionState.savingsRate.toStringAsFixed(1);
      final txCount = transactionState.allTransactions.length;

      // Turn the {category: amount} map into a readable comma-separated
      // string like "food: ₹4200, shopping: ₹3100, bills: ₹1800".
      // `.key.name` converts the TransactionCategory enum value (e.g.
      // TransactionCategory.food) into its plain string name ("food").
      final categoryBreakdown = transactionState.spendingByCategory.entries
          .map((e) => '${e.key.name}: ₹${e.value.toStringAsFixed(0)}')
          .join(', ');

      // Same idea, but for the {dayOfWeek: amount} map — produces something
      // like "Monday: ₹800, Saturday: ₹1840, Sunday: ₹1200".
      final dayBreakdown = transactionState.spendingByDayOfWeek.entries
          .map((e) => '${e.key}: ₹${e.value.toStringAsFixed(0)}')
          .join(', ');

      // Stitch everything into one multi-line block of plain text. ChatBloc
      // wraps this inside its system prompt before sending it to the AI —
      // think of it as a sticky note pinned to the top of every request:
      // "by the way, here's what the user has actually been spending".
      summary = '''
Indian UPI User Transaction Summary:
- Total spent this month: ₹$spent
- Total income this month: ₹$income
- Savings rate: $savings%
- Total transactions analyzed: $txCount
- Spending by category: $categoryBreakdown
- Spending by day of week: $dayBreakdown
''';
    }

    // Fire the startup event. From here on, ChatBloc takes over: it reads the
    // saved API key + provider out of SharedPreferences, builds the greeting
    // bubble, and emits ChatReady — which is what makes our `build()` method
    // below switch from "loading spinner" to "show me the chat".
    context.read<ChatBloc>().add(ChatInitialized(summary));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _sendMessage — called whenever the user wants to send what they've typed
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered from two places: tapping the send button, and pressing the
  // keyboard's "send"/"done" action while the text field is focused.
  //
  // Notice this method does NOT update any local state, add any bubbles, or
  // call the AI directly — it just hands the raw text off to ChatBloc as a
  // ChatMessageSent event. Everything that happens next (showing the user's
  // bubble immediately, flipping on the typing indicator, calling the AI API,
  // appending the reply, handling errors...) is ChatBloc's job. This screen
  // simply reacts to whatever ChatState comes back.
  void _sendMessage(BuildContext context, String text) {
    // Trim whitespace so a message that's just spaces (or empty) doesn't get
    // sent — there's nothing useful for the AI to respond to.
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Clear the input box right away. This makes the UI feel snappy: the user
    // sees their message "leave" immediately, rather than waiting for the
    // network round-trip to finish before the box empties.
    _controller.clear();

    // Hand off to ChatBloc. Internally it will, in order:
    //   1. Add the user's message to the conversation as a bubble.
    //   2. Set isLoading = true → the UI shows a "Thinking..." indicator.
    //   3. Call the configured AI provider's API with this message plus the
    //      transaction summary and recent conversation history.
    //   4. Add the AI's reply (or a friendly error bubble on failure) to the
    //      conversation, and set isLoading back to false.
    context.read<ChatBloc>().add(ChatMessageSent(trimmed));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // build — describes what to draw on screen, given the *current* ChatState
  // ───────────────────────────────────────────────────────────────────────────
  //
  // We use BlocConsumer instead of the simpler BlocBuilder because we need
  // to do two different kinds of things in response to state changes:
  //   • `listener` — run a one-off SIDE EFFECT (auto-scrolling to the
  //     bottom of the chat) that should NOT trigger a rebuild by itself.
  //   • `builder`  — actually decide what widgets to draw for the current
  //     state (this part DOES rebuild the UI).
  // BlocConsumer lets us register both without juggling two separate widgets.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: BlocConsumer<ChatBloc, ChatState>(
          // ── listener: side effects, no rebuild ──────────────────────────
          // Fires every time ChatBloc emits a new state. We use it here to
          // auto-scroll to the newest message — exactly like how WhatsApp or
          // iMessage always keeps the latest bubble in view.
          listener: (context, state) {
            if (state is ChatReady) {
              // We can't scroll to "the bottom" until the ListView has
              // actually finished laying out the new/updated message list —
              // otherwise `maxScrollExtent` would still reflect the OLD
              // (shorter) list. addPostFrameCallback waits until right after
              // the current frame finishes drawing, which is exactly the
              // right moment to measure-and-scroll.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          },
          // ── builder: decide what to draw for the current state ──────────
          // Every possible ChatState maps to a distinct visual:
          //   ChatInitial → "still loading the API key / building the
          //                  greeting" → show a spinner.
          //   ChatReady   → "everything's ready, here's the live chat" →
          //                  show the full chat UI (messages + input bar).
          //   ChatError   → "something went badly wrong" → show a fallback
          //                  message instead of a broken/empty screen.
          builder: (context, state) {
            if (state is ChatInitial) {
              // Brief moment between "screen opened" and "we know whether
              // you have an API key yet" — a centered spinner keeps the
              // screen from looking broken/empty during that gap.
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF7B61FF),
                ),
              );
            }

            if (state is ChatReady) {
              // The "happy path" — render the actual chat interface using
              // the live message list, loading flag, and API-key status that
              // ChatBloc is tracking for us.
              return _buildChatUI(context, state);
            }

            // Anything else (currently just ChatError) — something broke
            // badly enough that we can't show the chat at all. Keep this
            // simple; the conversation itself isn't recoverable from here.
            return const Center(
              child: Text(
                'Something went wrong',
                style: TextStyle(color: Color(0xFF888888)),
              ),
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _buildChatUI — the actual chat screen, shown only while state is ChatReady
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Lays out, top to bottom:
  //   a. A scrolling list of message bubbles (fills all remaining space).
  //   b. An optional warning banner if the user hasn't added an API key yet.
  //   c. A fixed input bar (text field + send button) pinned to the bottom.
  Widget _buildChatUI(BuildContext context, ChatReady state) {
    return Column(
      children: [
        // (a) The message list. `Expanded` makes it fill all the vertical
        // space that isn't taken up by the banner/input bar below it — the
        // same way `flex: 1` works in CSS flexbox.
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            // We add ONE extra slot to the list when isLoading is true, so
            // a "Thinking..." bubble can appear after the last real message
            // without us having to mutate the actual `messages` list.
            itemCount: state.messages.length + (state.isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              // If we're loading AND this is the extra slot at the very end
              // (i.e. one past the last real message), draw the typing
              // indicator instead of a real message bubble.
              if (state.isLoading && index == state.messages.length) {
                return _buildTypingIndicator();
              }
              return _buildMessageBubble(state.messages[index]);
            },
          ),
        ),

        // (b) Warning banner — only shown when ChatBloc tells us there's no
        // usable API key saved. Sits directly above the input bar so it's
        // impossible to miss right as the user is about to try typing.
        if (!state.hasApiKey)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFF5252).withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_outlined,
                  color: Color(0xFFFF5252),
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No API key found. Open the menu (☰) and add your key in '
                    'Settings.',
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // (c) The input bar — always pinned to the bottom of the screen,
        // outside the scrolling list, exactly like every chat app's compose
        // box.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            border: Border(
              top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ask about your spending...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  // Lets the user hit the keyboard's "send"/"done" button
                  // instead of having to tap the on-screen send circle.
                  onSubmitted: (text) => _sendMessage(context, text),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              // The round send button. Tapping it sends whatever is
              // currently typed in `_controller`. While the AI is replying
              // (`state.isLoading`), we swap the send icon for a small
              // spinner so the user gets a clear "your message is on its
              // way, please wait" signal.
              GestureDetector(
                onTap: () => _sendMessage(context, _controller.text),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF7B61FF),
                    shape: BoxShape.circle,
                  ),
                  child: state.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _buildMessageBubble — draws ONE message in the conversation
  // ───────────────────────────────────────────────────────────────────────────
  //
  // `message.isUser` decides almost everything about how a bubble looks:
  //   • Alignment: user messages hug the right edge, AI messages the left —
  //     just like every messaging app distinguishes "you" from "them".
  //   • Color: user bubbles are purple (the app's accent color), AI bubbles
  //     are a dark card color, and error bubbles get a red tint that screams
  //     "something went wrong" rather than "the assistant said this".
  //   • Corner shape: the bubble's "tail" corner (bottom-right for the user,
  //     bottom-left for the AI) is squared off slightly — a common chat-UI
  //     trick that visually "points" toward who's speaking.
  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        // Push user bubbles to the right side of the screen, AI/error
        // bubbles to the left — the universal chat-app convention for "you"
        // vs. "everyone else".
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ConstrainedBox stops a short message from stretching all the way
          // across the screen — bubbles should hug their text, not the
          // screen edges, the same way real chat bubbles do.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                // Three possible looks, in priority order:
                //   1. Error bubble  → soft red background (something broke)
                //   2. User bubble   → solid purple (the app's accent color)
                //   3. AI bubble     → dark card color (the "neutral" look)
                color: message.isError
                    ? const Color(0xFFFF5252).withValues(alpha: 0.15)
                    : isUser
                        ? const Color(0xFF7B61FF)
                        : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  // Squaring off the corner nearest to the speaker's side
                  // is what makes the bubble visually "point" at them.
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                // A subtle red border on error bubbles makes the "something
                // went wrong" look even more obvious at a glance.
                border: message.isError
                    ? Border.all(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                      )
                    : null,
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isError
                      ? const Color(0xFFFF5252)
                      : Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          // Small timestamp underneath each bubble — `message.time` is a
          // simple "HH:MM" string ChatMessage builds from its `timestamp`.
          const SizedBox(height: 4),
          Text(
            message.time,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _buildTypingIndicator — the "Thinking..." bubble shown while waiting on
  // the AI's reply
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Visually it's just another AI-style bubble (left-aligned, dark
  // background) containing the word "Thinking" plus a tiny spinner — a
  // simple, readable stand-in for the animated "..." dots you see in apps
  // like iMessage or WhatsApp while someone is typing. It only ever appears
  // as the LAST item in the list, and only while `state.isLoading` is true
  // (see the `itemCount`/`itemBuilder` logic in `_buildChatUI`).
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Thinking',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Color(0xFF7B61FF),
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
