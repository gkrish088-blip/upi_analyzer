import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'bloc/transaction_bloc.dart';
import 'bloc/transaction_event.dart';
import 'bloc/transaction_state.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _selectedRangeIndex = 0;
  int _selectedBarIndex = 3;

  static const List<String> _timeRanges = ['This month', 'Last month', '3 months'];

  // ── AI insight state ──────────────────────────────────────────────────────
  //
  // These two fields hold the result of the one-shot "summarize my spending"
  // call we make to the AI. They live here (on the State object) — not in a
  // BLoC — because this screen only ever needs to ask the AI once per visit;
  // it isn't a back-and-forth conversation like the chat screen, so a full
  // ChatBloc would be overkill.
  //
  // _aiInsightText:
  //   * null  → we haven't asked the AI yet (so we should kick off the call)
  //   * ''    → the AI was asked but came back with nothing useful
  //   * 'Add your API key...' or any other String → text to actually show
  //
  // _isLoadingInsight:
  //   true while the HTTP request to the AI provider is in flight, so the
  //   card can show a small spinner instead of pretending we already have
  //   an answer.
  String? _aiInsightText;
  bool _isLoadingInsight = false;

  // ── FIX 3: scope the screen to "This month" the moment it opens ───────────
  //
  // TransactionBloc is a single, shared source of truth for "what date range
  // is currently loaded" — both the Transactions screen's date-range selector
  // and this Insights screen's time-range tabs read from (and write to) the
  // exact same bloc. That's normally a feature (switch ranges in one place,
  // see it reflected everywhere) but it has a sharp edge here: if the user
  // last picked "All time" (or any other range) on the Transactions screen
  // and then navigates to Insights, this screen would silently render
  // *that* leftover range's histogram and AI summary — even though
  // `_selectedRangeIndex` defaults to 0 ("This month") and the tab UI claims
  // "This month" is selected. The visual selection and the underlying data
  // would disagree.
  //
  // The fix: as soon as this screen mounts, explicitly dispatch
  // `TransactionDateRangeChanged` for "This month" — the same event the
  // selector itself dispatches when the user taps that tab (see
  // `onRangeSelected` in `_buildInsightsContent`). That guarantees the data
  // backing the histogram/AI summary always starts out matching what the
  // tabs visually show as selected, regardless of whatever range was active
  // when the user arrived here.
  @override
  void initState() {
    super.initState();

    // We can't safely dispatch a bloc event directly inside `initState` —
    // `context.read<TransactionBloc>()` needs an `InheritedWidget` lookup
    // that isn't guaranteed to be ready during the very first build, and
    // dispatching here could trigger a rebuild while this widget is still
    // being constructed. `addPostFrameCallback` defers the dispatch until
    // *after* the first frame has finished drawing — the same safe-side-
    // effect-from-build pattern already used in `_buildInsightsContent` for
    // kicking off `_fetchAiInsight`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Guard against the screen having already been popped before this
      // deferred callback runs (e.g. the user navigated back immediately) —
      // dispatching to a bloc tied to an unmounted widget's context would be
      // wasted work at best and a dangling reference at worst.
      if (!mounted) return;

      final now = DateTime.now();

      // "This month" = from the 1st of the current month through right now —
      // identical to the `index == 0` branch inside `onRangeSelected` below,
      // so opening the screen and tapping the "This month" tab both resolve
      // to the exact same date window.
      context.read<TransactionBloc>().add(
            TransactionDateRangeChanged(
              start: DateTime(now.year, now.month, 1),
              end: now,
              label: 'This month',
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      // BlocBuilder<TransactionBloc, TransactionState> means: "watch
      // TransactionBloc, and rebuild this part of the UI every time it emits
      // a new TransactionState". This is the same Provider/BLoC wiring used
      // on the Home and Transactions screens — the bloc itself is supplied
      // higher up the widget tree by the MultiBlocProvider, so we can just
      // reach for it here with BlocBuilder/context.read.
      body: SafeArea(
        child: BlocBuilder<TransactionBloc, TransactionState>(
          builder: (context, state) {
            // We only know the user's real spending numbers once the bloc has
            // finished loading them. Until then (or if something went wrong),
            // show a simple spinner rather than a half-built screen — the
            // insights card needs `state.totalSpent`, `state.spendingByCategory`
            // etc., which only exist on TransactionLoaded.
            if (state is TransactionLoaded) {
              return _buildInsightsContent(context, state);
            }

            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF7B61FF),
              ),
            );
          },
        ),
      ),
    );
  }

  // The "real" body of the screen, only ever built once we have a
  // TransactionLoaded state (i.e. real transaction data) to work with.
  Widget _buildInsightsContent(BuildContext context, TransactionLoaded state) {
    // Kick off the AI call the first time we have data to summarize.
    //
    // We guard with `_aiInsightText == null` so this only fires once (not on
    // every rebuild), and with `!_isLoadingInsight` so we don't start a
    // second request while the first one is still running.
    //
    // We can't just call `_fetchAiInsight` directly here, because this method
    // runs *during* `build()`, and `_fetchAiInsight` eventually calls
    // `setState` (to store the AI's reply). Calling `setState` while Flutter
    // is in the middle of building widgets throws an error ("setState() or
    // markNeedsBuild() called during build"). `addPostFrameCallback` tells
    // Flutter "wait until you've finished drawing this frame, *then* run this"
    // — which is the standard, safe way to trigger a side effect from build().
    //
    // ── FIX 4: this same check now also covers "the user changed time range" ──
    //
    // `_aiInsightText == null` originally only meant "we've never fetched an
    // insight yet". Now it does double duty: in `_buildTimeRangeSelector`'s
    // `onRangeSelected` (FIX 1), we deliberately reset `_aiInsightText` and
    // `_isLoadingInsight` back to `null`/`false` whenever the user taps a
    // different time-range tab. That makes this exact same `if` fire again on
    // the next build — so switching from "This month" to "Last month"
    // automatically triggers a brand-new AI summary for the newly selected
    // range, without us needing any separate "did the range change?" check.
    //
    // The added `if (mounted)` is a safety check: `addPostFrameCallback` runs
    // its callback *after* the current frame finishes drawing, which could
    // be after this screen has already been removed from the widget tree
    // (e.g. the user navigated away while the AI request was queued up).
    // `mounted` is `true` only while this State object is still attached to
    // the tree — calling `setState` (inside `_fetchAiInsight`) on an
    // unmounted State would throw an error, so we simply skip the fetch if
    // we're no longer there to show the result.
    if (_aiInsightText == null && !_isLoadingInsight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchAiInsight(state);
      });
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTimeRangeSelector(
              ranges: _timeRanges,
              selectedIndex: _selectedRangeIndex,
              // ── FIX 1: make the time-range tabs actually reload data ──────
              //
              // Before this fix, tapping "Last month" / "3 months" only
              // changed which tab *looked* selected (`_selectedRangeIndex`)
              // — the histogram and AI summary kept showing the same data as
              // "This month". To make the tabs do something real, we now also
              // tell TransactionBloc which date range the user wants, so it
              // can go fetch the right slice of data from the database.
              onRangeSelected: (index) {
                setState(() {
                  _selectedRangeIndex = index;
                  // The AI summary was generated for the *old* date range —
                  // it would be misleading to keep showing it once the user
                  // switches ranges. Setting these back to their "not fetched
                  // yet" values makes `_buildInsightsContent` notice
                  // (`_aiInsightText == null`) and kick off a fresh AI call
                  // for the newly selected range (see FIX 4 below).
                  _aiInsightText = null;
                  _isLoadingInsight = false;
                });

                final now = DateTime.now();

                // Work out the actual start/end dates for whichever tab was
                // tapped. `DateTime(year, month, day)` builds a date — note
                // that `now.month - 1` or `now.month - 3` can go below 1
                // (e.g. January minus 1 = month 0); Dart's DateTime
                // constructor automatically "rolls back" into the previous
                // year for us, so this still produces a correct date.
                DateTime start;
                DateTime end;
                String label;

                if (index == 0) {
                  // This month: from the 1st of the current month up to now.
                  start = DateTime(now.year, now.month, 1);
                  end = now;
                  label = 'This month';
                } else if (index == 1) {
                  // Last month: the *whole* previous month — from its 1st to
                  // the 1st of the current month (i.e. up to, but not
                  // including, today's month).
                  start = DateTime(now.year, now.month - 1, 1);
                  end = DateTime(now.year, now.month, 1);
                  label = 'Last month';
                } else {
                  // Last 3 months: from the 1st of the month three months
                  // ago, up through today.
                  start = DateTime(now.year, now.month - 3, 1);
                  end = now;
                  label = 'Last 3 months';
                }

                // Send the chosen range to TransactionBloc. This is the same
                // "dispatch an event, the bloc reacts" pattern used
                // everywhere else in the app (see TransactionSyncRequested on
                // the Home screen). Concretely, TransactionBloc will:
                //   1. Query the local SQLite database for transactions that
                //      fall inside [start, end).
                //   2. Recompute every aggregate derived from that list —
                //      totals, savings rate, category/day-of-week breakdowns,
                //      etc.
                //   3. Emit a brand-new TransactionLoaded state carrying all
                //      of that freshly-computed data.
                //   4. Our BlocBuilder in build() notices the new state and
                //      rebuilds this screen — so the histogram and (after
                //      FIX 4 re-triggers it) the AI summary both reflect the
                //      newly selected time range.
                context.read<TransactionBloc>().add(
                  TransactionDateRangeChanged(
                    start: start,
                    end: end,
                    label: label,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // ── FIX 2: histogram now reflects the user's real spending ──────
            //
            // Previously this passed the hardcoded `_dailyData` sample list,
            // so the bars never matched the user's actual transactions. Now
            // we build the bar data straight from `state.spendingByDayOfWeek`
            // — the Map<String, double> the bloc computed from the user's
            // real transactions for the selected date range.
            _buildHistogram(
              dailyData: () {
                // We always want to show all 7 days, Monday through Sunday,
                // in that fixed order — regardless of which days the user
                // actually spent money on. A day with no spending should
                // still appear as a (zero-height) bar in its rightful spot,
                // not just disappear, so the chart's shape stays readable
                // and consistent week to week.
                //
                // `state.spendingByDayOfWeek` is already pre-seeded with all
                // 7 day keys by TransactionRepository.getSpendingByDayOfWeek()
                // — but we still look values up with `?? 0.0` as a safe
                // default in case a key is ever missing.
                const dayOrder = [
                  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                ];

                // `.map(...)` walks the fixed day order and turns each day
                // name into the same {'day': ..., 'amount': ...} map shape
                // that `_buildHistogram` already knows how to draw — so the
                // histogram widget itself doesn't need to change at all.
                return dayOrder.map((day) => {
                  'day': day,
                  'amount': state.spendingByDayOfWeek[day] ?? 0.0,
                }).toList();
              }(),
              selectedBarIndex: _selectedBarIndex,
              onBarSelected: (index) {
                setState(() => _selectedBarIndex = index);
              },
            ),
            const SizedBox(height: 20),
            // The AI summary card now shows one of three things, depending on
            // where we are in the fetch:
            //   1. While the request is in flight: a "thinking" placeholder
            //      plus a small spinner (handled by `isLoading: true` below).
            //   2. Once the AI replies: its actual generated text.
            //   3. If we never got a reply (no key, request failed, etc.):
            //      a locally-generated fallback built straight from the
            //      user's real numbers, via `_buildInsightText`.
            _buildAIInsightsCard(
              insightText: _isLoadingInsight
                  ? 'Analyzing your transactions...'
                  : (_aiInsightText ?? _buildInsightText(state)),
              isLoading: _isLoadingInsight,
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // _fetchAiInsight — the one-shot "summarize my spending" AI call
  // ───────────────────────────────────────────────────────────────────────────
  //
  // Unlike the chat screen (which uses ChatBloc to hold a back-and-forth
  // conversation), this screen just needs a single "here's my data, give me a
  // short summary" round trip. So instead of going through the bloc, we make
  // the HTTP call directly from the screen and store the result in
  // `_aiInsightText` via `setState`.
  //
  // Step by step, this method:
  //   1. Reads the user's saved API key + provider out of SharedPreferences
  //      (the same storage `settings_drawer.dart` writes to when the user
  //      saves their key).
  //   2. Bails out early with a friendly message if there's no key — there's
  //      no point making a network call we know will fail.
  //   3. Builds a compact, *aggregated-numbers-only* description of the
  //      user's spending (totals, category breakdown, busiest day, etc.).
  //      We deliberately never send raw SMS text or anything personally
  //      identifying — just the numbers needed to write a useful summary.
  //   4. Sends that description to whichever provider the user picked
  //      (Gemini / OpenAI / Claude), using the same request shapes that
  //      already work in `ChatBloc`.
  //   5. Stores the resulting text (or an error message) in `_aiInsightText`
  //      and flips `_isLoadingInsight` back off, which makes the card
  //      rebuild with the final answer.
  Future<void> _fetchAiInsight(TransactionLoaded state) async {
    // Guard against firing multiple requests at once — e.g. if the widget
    // happens to rebuild again before the first call finishes.
    if (_isLoadingInsight) return;

    setState(() => _isLoadingInsight = true);

    try {
      // SharedPreferences is Flutter's simple on-device key/value store —
      // think of it like `localStorage` in a web app. The Settings screen
      // (`settings_drawer.dart`) is what actually saves these two values
      // when the user types in their API key and picks a provider.
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('ai_api_key') ?? '';
      final provider = prefs.getString('ai_provider') ?? 'Gemini';

      // No key saved yet → there's nothing we can call. Show a friendly
      // nudge towards Settings instead of attempting (and failing) a
      // network request.
      if (apiKey.isEmpty) {
        setState(() {
          _aiInsightText = 'Add your API key in Settings to get AI insights.';
          _isLoadingInsight = false;
        });
        return;
      }

      // ── Turn the raw TransactionLoaded numbers into plain-English-ish
      // summary fragments we can drop into the prompt below. Everything here
      // is an aggregated number or category label — never a raw SMS string,
      // phone number, UPI ID, or anything else personal — which keeps what we
      // send to the AI provider privacy-respecting by construction.
      final spent = state.totalSpent.toStringAsFixed(0);
      final income = state.totalIncome.toStringAsFixed(0);
      final savings = state.savingsRate.toStringAsFixed(1);
      final txCount = state.allTransactions.length;

      // `spendingByCategory` is a Map<TransactionCategory, double>. We turn
      // each entry into a "categoryName: ₹amount" string and join them with
      // commas, e.g. "food: ₹5800, travel: ₹1200".
      final categoryBreakdown = state.spendingByCategory.entries
          .map((e) => '${e.key.name}: ₹${e.value.toStringAsFixed(0)}')
          .join(', ');

      // Same idea, but for spending grouped by day of the week
      // (Map<String, double>), e.g. "Monday: ₹800, Tuesday: ₹1200".
      final dayBreakdown = state.spendingByDayOfWeek.entries
          .map((e) => '${e.key}: ₹${e.value.toStringAsFixed(0)}')
          .join(', ');

      // Walk the day-of-week map by hand to find the single biggest spending
      // day. `forEach` just lets us look at every (day, amount) pair once;
      // we keep track of the largest amount we've seen so far and remember
      // which day it belonged to.
      String topDay = 'Saturday';
      double topDayAmount = 0;
      state.spendingByDayOfWeek.forEach((day, amount) {
        if (amount > topDayAmount) {
          topDayAmount = amount;
          topDay = day;
        }
      });

      // Same "find the biggest" walk, but over the category map this time.
      String topCategory = 'food';
      double topCategoryAmount = 0;
      state.spendingByCategory.forEach((cat, amount) {
        if (amount > topCategoryAmount) {
          topCategoryAmount = amount;
          topCategory = cat.name;
        }
      });

      // ── FIX 3: a richer prompt that asks for real analysis ────────────────
      //
      // The original prompt only asked for a short "here are your numbers"
      // blurb. This version spells out exactly what kind of analysis we want
      // — a numbered list of angles to cover (overall health, top category,
      // top day, a concrete savings tip, and a verdict on the savings rate)
      // — so the AI produces something that actually reads like advice from
      // a person who looked at the numbers, not just a restatement of them.
      //
      // Triple-quoted strings (''' ... ''') let us write this multi-line
      // block of text without needing '\n' everywhere — handy for prompts.
      final prompt = '''
You are a personal finance advisor analyzing Indian UPI
transaction data. Give a detailed but concise financial
analysis in 4-5 sentences covering:
1. Overall spending summary and whether it is healthy
2. Which category is consuming the most budget and why
   that might be concerning or acceptable
3. Which day of the week has highest spending and what
   that pattern suggests about behavior
4. One specific actionable recommendation to save money
   based on the actual numbers
5. Savings rate assessment — is $savings% good or bad
   for someone in India

Be specific — use the exact ₹ amounts from the data.
Sound like a friendly advisor, not a robot.
Keep total response under 100 words.

Transaction data:
- Period: selected time range
- Total spent: ₹$spent across $txCount transactions
- Total income detected: ₹$income
- Savings rate: $savings%
- Spending breakdown by category: $categoryBreakdown
- Spending by day of week: $dayBreakdown
- Highest spending day: $topDay (₹${topDayAmount.toStringAsFixed(0)})
- Highest spending category: $topCategory
  (₹${topCategoryAmount.toStringAsFixed(0)})
- Average transaction size: ₹${txCount > 0 ? (state.totalSpent / txCount).toStringAsFixed(0) : '0'}
''';

      // Will hold whatever text the AI provider sends back. Starts empty —
      // each branch below fills it in (or leaves it empty if something fails,
      // which the `if (insight.trim().isEmpty)` fallback further down handles
      // implicitly via the static fallback text).
      String insight = '';

      if (provider == 'Gemini') {
        // Same Gemini request shape that already works inside ChatBloc:
        // the v1beta endpoint, the gemini-2.5-flash model, and a
        // camelCase `systemInstruction` field for the "who are you" framing.
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-2.5-flash:generateContent?key=$apiKey'
        );

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [{'text': 'You are a concise financial advisor for Indian UPI users.'}]
            },
            // For a one-shot summary we only need a single 'user' turn —
            // there's no conversation history to thread through, unlike the
            // chat screen.
            'contents': [
              {
                'role': 'user',
                'parts': [{'text': prompt}],
              }
            ],
            // ── maxOutputTokens raised from 300 → 8192 ────────────────────────
            // Gemini 2.5 Flash burns "thinking tokens" internally before it
            // writes out the actual reply, and those thinking tokens are
            // deducted from this SAME maxOutputTokens budget. At 300, almost
            // all of the budget was being eaten by invisible chain-of-thought,
            // so the model kept hitting finishReason: MAX_TOKENS partway
            // through the 4-5 sentence analysis the prompt asks for. 8192
            // leaves plenty of headroom for a complete response.
            // ── generationConfig only — no thinkingConfig ───────────────────
            // We previously also sent a top-level `thinkingConfig: { thinkingBudget: 0 }`
            // alongside `contents`/`generationConfig`, trying to disable
            // Gemini's internal "thinking" phase so the whole token budget
            // went to the visible summary. That extra field isn't needed:
            // raising `maxOutputTokens` to 8192 alone already leaves plenty
            // of room for both some thinking AND a complete 4-5 sentence
            // analysis. Dropping `thinkingConfig` keeps the request body
            // simpler and sidesteps any chance of the field being
            // rejected/ignored by a future API version.
            'generationConfig': {
              'maxOutputTokens': 8192,
              'temperature': 0.7,
            },
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          insight = data['candidates'][0]['content']['parts'][0]['text']
              as String;
        } else {
          insight = 'Could not load AI insights. Check your API key.';
        }
      } else if (provider == 'OpenAI') {
        final response = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            // Same reasoning as the Gemini branch above: the longer-form
            // prompt needs more room to complete its answer than the old
            // short-summary version did, so we raised this from 150 to 300.
            'max_tokens': 300,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          insight = data['choices'][0]['message']['content'] as String;
        } else {
          insight = 'Could not load AI insights. Check your API key.';
        }
      } else if (provider == 'Claude') {
        final response = await http.post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'claude-haiku-4-5-20251001',
            // Same reasoning as the other two providers: more tokens means
            // more room for the fuller 4-5 sentence analysis the new prompt
            // (FIX 3) asks for, instead of getting cut off mid-sentence.
            'max_tokens': 300,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          insight = data['content'][0]['text'] as String;
        } else {
          insight = 'Could not load AI insights. Check your API key.';
        }
      }

      // `setState` is what tells Flutter "some of the data your widgets
      // depend on has changed — please rebuild". Storing the trimmed text
      // here makes `_buildInsightsContent` re-run, which now sees
      // `_aiInsightText != null` and renders the real answer instead of the
      // "Analyzing..." placeholder.
      setState(() {
        _aiInsightText = insight.trim();
        _isLoadingInsight = false;
      });
    } catch (e) {
      // Network hiccups, malformed JSON, timeouts, missing fields — anything
      // that goes wrong lands here. We still want the card to show *something*
      // useful rather than getting stuck on "Analyzing...", so we store a
      // readable error message as the insight text.
      setState(() {
        _aiInsightText = 'Could not load AI insights: $e';
        _isLoadingInsight = false;
      });
    }
  }

  // A locally-computed, no-network-required summary built straight from the
  // real TransactionLoaded numbers. This is what the card falls back to if
  // the AI call hasn't produced anything yet (e.g. no API key saved) — it's
  // the safety net under `_aiInsightText`, written in the same "You spent
  // ₹X..." voice as the original hardcoded placeholder text used to be.
  String _buildInsightText(TransactionLoaded state) {
    final spent = state.totalSpent.toStringAsFixed(0);

    // No category data yet (e.g. a brand new account with no transactions) —
    // there isn't enough to build a "your top category is..." sentence, so
    // keep it simple.
    if (state.spendingByCategory.isEmpty) {
      return 'You spent ₹$spent this month. Keep tracking to see more insights!';
    }

    // Same "walk the map and remember the biggest" pattern used inside
    // `_fetchAiInsight` above — find which category the user spent the most
    // in, so we can call it out by name.
    var topCategoryName = '';
    var topCategoryAmount = 0.0;
    state.spendingByCategory.forEach((category, amount) {
      if (amount > topCategoryAmount) {
        topCategoryAmount = amount;
        topCategoryName = category.name;
      }
    });

    return 'You spent ₹$spent this month.\n'
        'Your $topCategoryName spend is the highest category at '
        '₹${topCategoryAmount.toStringAsFixed(0)}.';
  }

  // ── FIX 2: underline indicator now tracks `_selectedRangeIndex` directly ───
  //
  // The previous version computed each underline's width from the *label's
  // text length* (`_textWidth`). That made the underline look like it was
  // "selecting" whichever tab happened to render widest, instead of the tab
  // the user actually tapped — e.g. "This month" (10 chars) vs "3 months"
  // (8 chars) would each get a different-width bar regardless of which one
  // was selected, so the highlight didn't visually line up with the active
  // tab/content.
  //
  // The fix: every tab's underline is now a FIXED width (60) and its color
  // is the only thing that changes — purple when `selectedIndex == index`,
  // transparent otherwise. That ties the visible "which tab is active"
  // indicator directly and unambiguously to `_selectedRangeIndex`/
  // `selectedIndex`, the same value that drives the date-range fetch in
  // `onRangeSelected` — so the underline, the label styling, and the data
  // shown below are always all in sync.
  Widget _buildTimeRangeSelector({
    required List<String> ranges,
    required int selectedIndex,
    required Function(int) onRangeSelected,
  }) {
    return Row(
      // `start` (rather than the default `spaceBetween`/`center`) packs the
      // tabs against the left edge with explicit gaps between them — matching
      // how this kind of segmented selector usually sits flush with the
      // screen's leading edge instead of spreading out to fill the row.
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(ranges.length, (index) {
        return Row(
          children: [
            GestureDetector(
              // Tapping a tab reports its index back up to
              // `_buildInsightsContent`'s `onRangeSelected` callback, which
              // both updates `_selectedRangeIndex` (so this selector
              // re-renders with the new tab highlighted) and dispatches
              // `TransactionDateRangeChanged` (so the histogram/AI summary
              // reload for the newly chosen date range).
              onTap: () => onRangeSelected(index),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ranges[index],
                    style: TextStyle(
                      // Selected tab: white and bold, so it visually "pops"
                      // as the active choice.
                      // Unselected tab: muted gray, fading into the
                      // background so the eye is drawn to the active one.
                      color: selectedIndex == index
                          ? Colors.white
                          : const Color(0xFF888888),
                      fontSize: 14,
                      fontWeight: selectedIndex == index
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Underline indicator — only visible (purple) on the
                  // currently selected tab. Using a fixed width for every
                  // tab (rather than sizing it to the label's text length)
                  // is what keeps this bar visually anchored under whichever
                  // tab is *actually* selected, instead of appearing to
                  // drift toward whichever label happens to be widest.
                  Container(
                    height: 2,
                    width: 60,
                    decoration: BoxDecoration(
                      color: selectedIndex == index
                          ? const Color(0xFF7B61FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
            // Gap between tabs — skipped after the last one so the row
            // doesn't end with trailing empty space.
            if (index < ranges.length - 1) const SizedBox(width: 24),
          ],
        );
      }),
    );
  }

  // ── Bug fix: histogram NaN crash when every transaction lands on one day ──
  //
  // `barHeight = (amount / maxAmount) * maxHeight` divides by `maxAmount`,
  // the single largest day's spend across the whole week. That's fine when
  // spending is spread across multiple days — but if every transaction in
  // the selected range happened on the same day, `maxAmount` is still a
  // normal positive number for THAT day... the real failure mode is the
  // opposite: when there is NO spending at all in range (a brand new account,
  // or a date range with zero transactions), every `amount` is 0, so
  // `maxAmount` is also 0, and `0 / 0` produces `NaN`. Flutter cannot lay out
  // a `Container` with a `NaN` height — it renders the infamous red
  // "RenderBox was not laid out" error box instead of the chart.
  //
  // `_safeBarHeight` guards both halves of that division: if there's no
  // "biggest day" to scale against (`maxAmount <= 0`) or this particular bar
  // has nothing to show (`amount <= 0`), we skip the division entirely and
  // return a flat `0.0` rather than ever computing `0/0`.
  double _safeBarHeight(double amount, double maxAmount, double maxHeight) {
    if (maxAmount <= 0) return 0.0;
    if (amount <= 0) return 0.0;
    return (amount / maxAmount) * maxHeight;
  }

  Widget _buildHistogram({
    required List<Map<String, dynamic>> dailyData,
    required int selectedBarIndex,
    required Function(int) onBarSelected,
  }) {
    const double maxHeight = 200;

    // Compute the largest single-day amount via `fold` instead of `reduce`.
    // `reduce` throws on an empty list and (more importantly for us) doesn't
    // change the NaN risk — but `fold` lets us start from a known `0.0`
    // seed, so an empty `dailyData` list safely yields `maxAmount == 0.0`
    // instead of throwing, and we never need to special-case "is the list
    // empty?" before reaching for the max.
    final double maxAmount = dailyData
        .map((d) => (d['amount'] as num).toDouble())
        .fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      height: maxHeight + 28, // extra room for labels
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(dailyData.length, (index) {
          final item = dailyData[index];
          final amount = item['amount'] as double;

          // Days with zero spending get a small 4px "stub" bar instead of a
          // real scaled height — that keeps the bar visibly present (so the
          // day still reads as "part of the chart") while making it
          // unmistakably distinct from days that actually have spending.
          // Days with spending go through `_safeBarHeight`, which returns
          // `0.0` (never `NaN`) if `maxAmount` happens to be zero too.
          final barHeight = amount > 0
              ? _safeBarHeight(amount, maxAmount, 180)
              : 4.0; // minimum stub so the bar is visible but clearly empty

          // Final belt-and-braces guard right before this number reaches a
          // `Container`'s `height`: Flutter's layout cannot handle `NaN` or
          // `infinity` (it throws/renders the red error box), and a negative
          // height is meaningless for a bar chart. `clamp(4.0, 180.0)` also
          // doubles as the "never smaller than the empty-day stub, never
          // taller than the chart's drawable area" bound.
          final safeHeight = barHeight.isNaN || barHeight.isInfinite
              ? 4.0
              : barHeight.clamp(4.0, 180.0);

          final isSelected = index == selectedBarIndex;

          return GestureDetector(
            onTap: () => onBarSelected(index),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 38,
              height: maxHeight + 28,
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 38,
                        height: safeHeight,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF7B61FF)
                              : const Color(0xFF7B61FF).withValues(alpha: 0.3),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['day'] as String,
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // The "AI summary" card at the bottom of the screen.
  //
  // `insightText` is whatever message we currently want to show — the
  // "Analyzing..." placeholder, the AI's real reply, or the local fallback —
  // decided by the caller in `_buildInsightsContent`.
  //
  // `isLoading` additionally tells this card to show a small spinner under
  // the text while we're waiting on the AI's response, so the user can see
  // that something is actively happening rather than wondering if the app
  // is stuck.
  Widget _buildAIInsightsCard({
    required String insightText,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7B61FF).withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7B61FF)),
              SizedBox(width: 8),
              Text(
                'AI summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insightText,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          // Only takes up space while we're actually waiting on the AI —
          // once `isLoading` flips back to false this widget disappears
          // entirely (an `if` inside a children list either includes the
          // widget or skips it, there's no "invisible placeholder" left
          // behind).
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Color(0xFF7B61FF),
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
