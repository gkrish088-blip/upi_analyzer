# UPI Analyzer

> An AI-powered UPI transaction analyzer for Android.
> Parses your bank SMS, categorizes spending, and gives
> you intelligent financial insights — all on-device.
> Your data never leaves your phone.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
[![pub package](https://img.shields.io/pub/v/upi_sms_parser.svg)](https://pub.dev/packages/upi_sms_parser)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)

---

## Features

| Feature | Description |
|---|---|
| **Automatic SMS Parsing** | Reads UPI transaction SMS from your inbox automatically. Supports SBI, HDFC, ICICI, Axis, Kotak, GPay, PhonePe, Paytm, BHIM, Swiggy, Blinkit and more. |
| **Smart Categorization** | Automatically categorizes transactions into Food, Transport, Shopping, Bills, Entertainment, Transfer using merchant keyword matching. Expandable keyword dictionary. |
| **Visual Analytics** | Interactive bar chart showing spending by day of week. Donut chart showing category breakdown. Filter by This Month, Last Month, 3 Months, or custom range. |
| **AI Financial Insights** | Connects to your own OpenAI, Gemini, or Claude API key. Ask natural language questions about your spending. Get detailed financial analysis on the Insights screen. Your API key is stored locally — never sent to any server. |
| **100% On-Device Privacy** | All transaction data stored in local SQLite database. No backend server. No data collection. No ads. Only aggregated summaries sent to AI (never raw SMS). |
| **Export & Backup** | Export all transactions as CSV to Downloads folder. Clear all data with one tap. |

---

## Architecture

### Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x + Dart 3 |
| State Management | BLoC (flutter_bloc) |
| Local Database | SQLite (sqflite) |
| SMS Reading | flutter_sms_inbox |
| Permissions | permission_handler |
| AI Integration | OpenAI / Gemini / Claude REST APIs |
| Storage | SharedPreferences (API keys, settings) |
| Package | upi_sms_parser (pub.dev) |

### BLoC Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                        UI LAYER                          │
│  HomeScreen  TransactionsScreen  InsightsScreen  ChatScreen │
└──────────────────────┬──────────────────────────────────┘
                       │ Events
                       ▼
┌─────────────────────────────────────────────────────────┐
│                     BLOC LAYER                           │
│                                                          │
│   TransactionBloc              ChatBloc                  │
│   ├── SyncRequested        ├── ChatInitialized           │
│   ├── LoadRequested        ├── MessageSent               │
│   ├── FilterChanged        └── ChatCleared               │
│   ├── DateRangeChanged                                   │
│   └── DeleteRequested                                    │
└──────────────────────┬──────────────────────────────────┘
                       │ Calls
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  REPOSITORY LAYER                        │
│              TransactionRepository                       │
│   ├── syncTransactions()    ← SMS → DB pipeline          │
│   ├── getAllTransactions()                               │
│   ├── getTransactionsByDateRange()                       │
│   ├── getTotalSpent()       ← Quant Engine               │
│   ├── getSpendingByCategory()                            │
│   └── getSpendingByDayOfWeek()                           │
└────────┬──────────────────────────┬─────────────────────┘
         │                          │
         ▼                          ▼
┌─────────────────┐    ┌────────────────────────┐
│  SERVICE LAYER  │    │     DATABASE LAYER      │
│                 │    │                         │
│  SmsService     │    │  DatabaseHelper         │
│  ├── readSMS()  │    │  ├── SQLite (sqflite)   │
│  └── filter()   │    │  ├── transactions table │
│                 │    │  └── CRUD operations    │
│  CategoryService│    └────────────────────────┘
│  └── categorize()│
└─────────────────┘
```

---

## Data Flow

### SMS Parsing Pipeline

```
Android SMS Inbox
       │
       ▼
┌──────────────────┐
│   SmsService     │  Reads 200 most recent SMS
│   fetchUPI()     │  using flutter_sms_inbox
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  UpiSmsFilter    │  4-gate filter system:
│  (pub.dev pkg)   │  Gate 0: Block promo senders (AP-)
│                  │  Gate 1: Currency marker check
│                  │  Gate 2: Transaction action word
│                  │  Gate 3: Bank sender OR UPI ref
│                  │  Gate 4: Blocklist (OTP/recharge)
└────────┬─────────┘
         │  Only genuine UPI SMS pass
         ▼
┌──────────────────┐
│  UpiSmsExtractor │  Extracts via regex:
│  (pub.dev pkg)   │  • Amount (5 patterns)
│                  │  • Merchant (4 patterns)
│                  │  • Transaction type
│                  │  • UPI Reference ID
│                  │  • Bank account number
│                  │  • Available balance
│                  │  • Timestamp (8 formats)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ CategoryService  │  Keyword matching:
│                  │  merchant name → category
│                  │  fallback: SMS body scan
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Deduplication   │  Primary: UPI Reference ID
│                  │  Fallback: amount+account+minute
│                  │  fingerprint for null-ref SMS
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ SQLite Database  │  Persisted locally forever
│                  │  Never uploaded anywhere
└──────────────────┘
```

### AI Integration Flow

```
TransactionBloc
       │ Aggregated summary string
       │ (totals, categories, day breakdown)
       │ Never raw SMS or personal details
       ▼
┌──────────────────┐
│   ChatBloc /     │
│ InsightsScreen   │
└────────┬─────────┘
         │ HTTPS POST
         ▼
┌──────────────────────────────────┐
│        AI Provider               │
│  OpenAI  │  Gemini  │  Claude    │
│  (user's own API key)            │
└────────┬─────────────────────────┘
         │ Response text
         ▼
┌──────────────────┐
│   UI renders     │
│   chat bubble /  │
│   insight card   │
└──────────────────┘
```

---

## Project Structure

```
upi_analyzer/                    ← Flutter app
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml  ← SMS + notification permissions
├── lib/
│   ├── main.dart                ← App entry point + BLoC providers
│   ├── bloc/
│   │   ├── transaction_bloc.dart
│   │   ├── transaction_event.dart
│   │   ├── transaction_state.dart
│   │   ├── chat_bloc.dart
│   │   ├── chat_event.dart
│   │   └── chat_state.dart
│   ├── database/
│   │   └── database_helper.dart ← SQLite setup + CRUD
│   ├── models/
│   │   └── transaction_models.dart ← Transaction model + enums
│   ├── repository/
│   │   └── transaction_repository.dart ← Orchestration + Quant Engine
│   ├── services/
│   │   ├── sms_service.dart     ← Android SMS reading + filtering
│   │   └── category_service.dart ← Keyword-based categorization
│   ├── home_screen.dart
│   ├── transactions_screen.dart
│   ├── insights_screen.dart
│   ├── ask_ai_screen.dart
│   ├── settings_drawer.dart
│   └── main_shell.dart
└── pubspec.yaml

upi_sms_parser/                  ← Standalone pub.dev package
├── lib/
│   ├── upi_sms_parser.dart      ← Main export
│   └── src/
│       ├── upi_parser.dart      ← Main public API
│       ├── sms_filter.dart      ← 4-gate filter
│       ├── sms_extractor.dart   ← Regex extraction
│       └── parsed_transaction.dart ← Data class
├── test/
│   └── upi_sms_parser_test.dart ← 40 unit tests
├── example/
│   └── example.dart
├── README.md
├── CHANGELOG.md
├── LICENSE
└── pubspec.yaml
```

---

## Supported Banks & Apps

### Banks

| Bank | Sender ID Format | Status |
|---|---|---|
| State Bank of India | JK-SBIUPI-S | Tested |
| HDFC Bank | AD-HDFCBK | Supported |
| ICICI Bank | JD-ICICIB | Supported |
| Axis Bank | AD-AXISBK | Supported |
| Kotak Mahindra | VM-KOTAK | Supported |
| Punjab National Bank | AD-PNBSMS | Supported |
| Bank of Baroda | AD-BOBSMS | Supported |
| Bank of India | AD-BOISBI | Supported |
| Canara Bank | AD-CANBNK | Supported |
| IndusInd Bank | AD-INDBNK | Supported |

### UPI Apps & Merchants

| App/Merchant | Category |
|---|---|
| Google Pay (GPay) | Transfer |
| PhonePe | Transfer |
| Paytm | Transfer |
| BHIM | Transfer |
| Swiggy | Food |
| Zomato | Food |
| Blinkit | Food |
| Uber / Ola / Rapido | Transport |
| Amazon / Flipkart | Shopping |
| Netflix / Spotify | Entertainment |
| Airtel / Jio / Vi | Bills |

---

## Getting Started

### Prerequisites

- Flutter 3.x
- Android device or emulator (API 21+)
- An API key from OpenAI, Google AI Studio, or Anthropic

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/yourusername/upi_analyzer.git
   cd upi_analyzer
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Run on Android**

   ```bash
   flutter run
   ```

### First Time Setup

1. Open the app
2. Tap the menu icon
3. Select your AI provider (OpenAI / Gemini / Claude)
4. Paste your API key and tap Save
5. Go back to Home and tap the sync button
6. Grant SMS permission when prompted
7. Your transactions will appear automatically

---

## Privacy & Security

| What | Where it goes |
|---|---|
| Raw SMS messages | Never leaves your phone |
| Transaction data | Local SQLite only |
| API key | Local SharedPreferences only |
| AI requests | Only aggregated summaries sent |
| Analytics | None collected |
| Ads | None |

This app was built with privacy as a first principle.
UPI transaction data reveals salary, medical expenses,
relationships, and lifestyle — it should never leave
your device. This app processes everything locally
and only sends anonymized aggregate summaries to the
AI provider of your choice, using your own API key.

---

## upi_sms_parser Package

This app ships a standalone pub.dev package extracted
from the core SMS parsing logic.

https://pub.dev/packages/upi_sms_parser

### What it does

Pure Dart library for parsing Indian UPI transaction SMS.
No Flutter dependency — works in any Dart project.

### Quick usage

```dart
import 'package:upi_sms_parser/upi_sms_parser.dart';

final parser = UpiParser();
final result = parser.parse(smsBody, senderAddress);

if (result != null) {
  print(result.amount);   // 356.0
  print(result.merchant); // "Swiggy"
  print(result.upiRef);   // "260298464000257"
  print(result.type);     // UpiTransactionType.debit
}
```

40 unit tests. Zero Flutter dependencies. MIT License.

---

## Key Technical Decisions

### Why BLoC?

BLoC enforces strict separation between UI and business
logic. Events flow in, states flow out — the UI never
knows how data is fetched. This made the AI integration,
SMS sync, and filtering independently testable.

### Why SQLite over a remote DB?

UPI data is among the most sensitive personal data —
it reveals salary, relationships, and health expenses.
The DPDP Act 2023 classifies financial data as sensitive.
Local SQLite means zero liability, zero backend costs,
and works offline forever.

### Why regex over AI for SMS parsing?

AI parsing would cost money per SMS, require internet,
and be slow. Regex is free, instant, and offline.
AI is reserved for the high-value task it excels at:
synthesizing patterns into human insights from
aggregated data.

### Why user-supplied API keys?

Zero API costs for the developer. Zero liability for
AI outputs. Users control their own AI spend and
choose their preferred provider. Privacy — keys go
directly from the phone to the AI provider.

---

## License

MIT License — see LICENSE file for details.

Built with Flutter, BLoC, and SQLite.
