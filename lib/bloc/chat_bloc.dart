// ─────────────────────────────────────────────────────────────────────────────
// WHAT THIS BLOC DOES
// ─────────────────────────────────────────────────────────────────────────────
//
// ChatBloc is the brain behind the "ask your finances anything" chat screen —
// a ChatGPT-style conversation between the user and an AI assistant that can
// see their transaction summary. Concretely it:
//
//   • Manages the chat message list (the running conversation history)
//   • Sends user messages to the AI API, bundled with transaction context so
//     the AI actually knows what "my spending" refers to
//   • Receives AI responses and appends them to the message list as bubbles
//   • Handles the "loading" state while waiting for the AI to reply (so the
//     UI can show a typing indicator)
//   • Handles a missing API key gracefully — instead of crashing or silently
//     failing, it shows a friendly inline message telling the user to add one
//     in Settings
//
// Like TransactionBloc, this BLoC never talks to the network or to
// SharedPreferences from the UI layer — the screen only ever dispatches
// ChatEvents and listens for ChatStates. That keeps all the "how do I talk to
// OpenAI/Gemini/Claude" plumbing in exactly one place.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_event.dart';
import 'chat_state.dart';

/// The greeting shown the moment the chat screen opens — before the user has
/// typed anything. It doubles as the "starter message" the conversation gets
/// reset back to when the user clears the chat.
const String _kGreetingText =
    'Hi! I am your financial assistant. I can see your transaction data and '
    'answer questions about your spending. Try asking: how much did I spend '
    'on food this month?';

/// The "job description" we hand the AI at the start of every request. It's
/// the same idea as a cover letter pinned to the top of every email thread:
/// it tells the AI who it's pretending to be, what data it has access to, and
/// the ground rules to follow (currency, tone, length) — so we don't have to
/// repeat those instructions inside every single user message.
String _buildSystemPrompt(String transactionSummary) {
  return 'You are a personal financial assistant for an Indian UPI user.\n'
      'You have access to the user\'s transaction data summary below.\n'
      'Answer questions about their spending clearly and concisely.\n'
      'Always refer to amounts in Indian Rupees (₹).\n'
      'Keep responses under 100 words unless more detail is needed.\n'
      '\n'
      'Transaction Summary:\n'
      '$transactionSummary';
}

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc() : super(const ChatInitial()) {
    // Wiring: "whenever an event of this type arrives, run this handler".
    // Same registration pattern as TransactionBloc — one line per event type.
    on<ChatInitialized>(_onInitialized);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatCleared>(_onCleared);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: ChatInitialized
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the chat screen opening for the first time.
  //
  // What it does, step by step:
  //   1. Reads the saved API key and provider out of SharedPreferences — this
  //      is the same idea as reading a value out of localStorage in a web app:
  //      a small synchronous-feeling key/value store that survives app
  //      restarts. The provider falls back to 'Claude' if nothing was saved.
  //   2. Builds the initial greeting bubble as an AI message, so the chat
  //      never opens to a totally empty screen.
  //   3. Emits ChatReady with everything the screen needs to render: the
  //      starter message list, "not loading", whether we actually *have* a
  //      usable key, the transaction summary (kept around for later use on
  //      every send), the raw key, and the provider name.
  //
  // Edge case handled: an empty-string key counts the same as "no key" —
  // `apiKey.isNotEmpty` guards against a stray saved empty string making the
  // UI think everything's fine when it isn't.
  Future<void> _onInitialized(
    ChatInitialized event,
    Emitter<ChatState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('ai_api_key');
    final provider = prefs.getString('ai_provider') ?? 'Claude';

    final greeting = ChatMessage.ai(_kGreetingText);

    emit(ChatReady(
      messages: [greeting],
      isLoading: false,
      hasApiKey: apiKey != null && apiKey.isNotEmpty,
      transactionSummary: event.transactionSummary,
      apiKey: apiKey,
      aiProvider: provider,
    ));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: ChatMessageSent
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user typing a message and tapping send.
  //
  // What it does, step by step:
  //   a. Bails out if we're not actually in ChatReady yet — there's no
  //      conversation to add to if the screen hasn't finished loading.
  //   b. If there's no usable API key, we can't call any AI provider at all —
  //      so instead of attempting (and failing) a network request, we just
  //      drop a friendly error bubble into the conversation telling the user
  //      where to go fix it, and stop right there.
  //   c. Otherwise, immediately add the user's own message as a bubble — this
  //      makes the UI feel instant, the user sees their message appear the
  //      moment they hit send, well before any network round-trip finishes.
  //   d. Flip `isLoading` to true so the UI can show a "typing..." indicator
  //      bubble while we wait on the AI.
  //   e. Actually call out to the AI provider via _getAiResponse.
  //   f. On success, append the AI's reply as a normal AI bubble and turn
  //      `isLoading` back off.
  //   g. On failure (network error, bad response, timeout, ...), append an
  //      error bubble describing what went wrong instead — the conversation
  //      isn't lost, the user just sees "that one didn't work" and can retry.
  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ChatReady) return;

    if (!currentState.hasApiKey) {
      final errorMessage = ChatMessage.error(
        'No API key found. Please add your API key in Settings.',
      );
      emit(currentState.copyWith(
        messages: [...currentState.messages, errorMessage],
      ));
      return;
    }

    final userMessage = ChatMessage.user(event.message);
    final updatedMessages = [...currentState.messages, userMessage];

    // Show the user's bubble immediately and switch on the typing indicator.
    emit(currentState.copyWith(messages: updatedMessages, isLoading: true));

    try {
      final response = await _getAiResponse(
        userMessage: event.message,
        transactionSummary: currentState.transactionSummary,
        apiKey: currentState.apiKey!,
        provider: currentState.aiProvider,
        history: currentState.messages,
      );

      final aiMessage = ChatMessage.ai(response);
      emit(currentState.copyWith(
        messages: [...updatedMessages, aiMessage],
        isLoading: false,
      ));
    } catch (e) {
      final errorMessage = ChatMessage.error(e.toString());
      emit(currentState.copyWith(
        messages: [...updatedMessages, errorMessage],
        isLoading: false,
      ));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Handler: ChatCleared
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Triggered by: the user wanting a fresh conversation (e.g. tapping a
  // "new chat" icon).
  //
  // What it does: throws away the entire message history and replaces it with
  // a brand new greeting bubble — exactly what the screen looked like the
  // first time it opened. Everything else (API key, provider, transaction
  // summary) is left untouched via copyWith, since clearing the chat doesn't
  // change any of that.
  void _onCleared(ChatCleared event, Emitter<ChatState> emit) {
    final currentState = state;
    if (currentState is! ChatReady) return;

    final greeting = ChatMessage.ai(_kGreetingText);
    emit(currentState.copyWith(messages: [greeting], isLoading: false));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper: _getAiResponse
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Does the actual work of talking to whichever AI provider the user has
  // configured, and returns just the plain text reply.
  //
  // Step by step:
  //   1. Build the system prompt — the AI's "job description" — by stitching
  //      the transaction summary into a fixed template (see
  //      _buildSystemPrompt above).
  //   2. Trim the conversation history down to the last 10 messages. This is
  //      like session memory for the AI: enough for it to follow the thread
  //      of the conversation ("you said X, now I'm asking about Y"), but
  //      capped so we don't blow through the provider's token limits (and
  //      cost) by replaying the entire chat history on every single message.
  //      We also drop the very first greeting/error bubbles where relevant —
  //      each provider's loop below filters to just user/AI exchanges.
  //   3. Route to the right provider's HTTP API based on a simple if/else
  //      "switch" on the provider name — exactly like a delivery app picking
  //      which courier service to call based on what the user selected at
  //      checkout: same parcel (the user's question + context), different
  //      courier-specific paperwork (request shape, headers, response format).
  //   4. Parse out just the text of the reply from that provider's
  //      differently-shaped JSON response.
  //
  // Edge cases handled:
  //   • A non-200/non-ok HTTP status is treated as a failure and turned into
  //     an Exception carrying the status code, so the caller sees something
  //     useful ("AI request failed: Exception: OpenAI request failed (401)")
  //     rather than a confusing parse error on an error payload.
  //   • The whole thing is wrapped in try/catch — any problem (network
  //     failure, malformed JSON, missing fields, timeouts, ...) is normalized
  //     into a single `Exception('AI request failed: $e')` so _onMessageSent
  //     can show one consistent error bubble regardless of what went wrong.
  Future<String> _getAiResponse({
    required String userMessage,
    required String transactionSummary,
    required String apiKey,
    required String provider,
    required List<ChatMessage> history,
  }) async {
    try {
      final systemPrompt = _buildSystemPrompt(transactionSummary);

      // Only the most recent messages are sent — older ones are dropped to
      // keep the request small. `history` already includes the user's latest
      // message (it was added to the list before this method was called), so
      // we exclude it here and pass it separately as `userMessage` instead —
      // each provider's body appends it as the final turn.
      final recentHistory = history.length > 10
          ? history.sublist(history.length - 10)
          : history;
      final conversationHistory =
          recentHistory.where((m) => m.text != userMessage || m.isUser != true)
              .toList();

      if (provider == 'OpenAI') {
        return await _callOpenAi(
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          history: conversationHistory,
          userMessage: userMessage,
        );
      } else if (provider == 'Gemini') {
        return await _callGemini(
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          history: conversationHistory,
          userMessage: userMessage,
        );
      } else {
        // 'Claude' (and anything unrecognized) — Claude is our default.
        return await _callClaude(
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          history: conversationHistory,
          userMessage: userMessage,
        );
      }
    } catch (e) {
      throw Exception('AI request failed: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Provider: OpenAI (https://api.openai.com/v1/chat/completions)
  // ───────────────────────────────────────────────────────────────────────────
  //
  // OpenAI's chat format is a single flat `messages` array where the system
  // prompt, history, and the new user message all live side by side, each
  // tagged with a `role` of 'system', 'user', or 'assistant'.
  Future<String> _callOpenAi({
    required String apiKey,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...history.map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              }),
          {'role': 'user', 'content': userMessage},
        ],
        'max_tokens': 300,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Provider: Gemini (generativelanguage.googleapis.com)
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Gemini's format is shaped quite differently from OpenAI's: instead of a
  // flat `messages` array with role names 'user'/'assistant', it wants
  // `contents` with role names 'user'/'model', each turn's text wrapped in a
  // `parts` array, and the system prompt passed entirely separately as
  // `systemInstruction` rather than as just another message in the list.
  Future<String> _callGemini({
    required String apiKey,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$apiKey',
    );

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          ...history.map((m) => {
                'role': m.isUser ? 'user' : 'model',
                'parts': [
                  {'text': m.text}
                ],
              }),
          {
            'role': 'user',
            'parts': [
              {'text': userMessage}
            ],
          },
        ],
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ],
        },
        'generationConfig': {'maxOutputTokens': 300},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body);
    return data['candidates'][0]['content']['parts'][0]['text'] as String;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Provider: Claude (https://api.anthropic.com/v1/messages) — our default
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Claude's Messages API looks the most like OpenAI's (a flat `messages`
  // array of 'user'/'assistant' turns), but two things are different: the
  // system prompt is its own top-level `system` field rather than a message in
  // the array, and authentication is via an `x-api-key` header plus a required
  // `anthropic-version` header instead of a Bearer token.
  Future<String> _callClaude({
    required String apiKey,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String userMessage,
  }) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'claude-haiku-4-5-20251001',
        'max_tokens': 300,
        'system': systemPrompt,
        'messages': [
          ...history.map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              }),
          {'role': 'user', 'content': userMessage},
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Claude request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body);
    return data['content'][0]['text'] as String;
  }
}
