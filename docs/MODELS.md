# Kotodama · Models, parameters and metrics

## Speech recognition

| Mode | Model | Parameters |
| --- | --- | --- |
| On-device | `SpeechAnalyzer` + `SpeechTranscriber` (Apple's on-device speech model, iOS 26) | `reportingOptions: [.volatileResults, .fastResults]`, `attributeOptions: [.audioTimeRange]`, assets installed on demand via `AssetInventory`; audio converted to `bestAvailableAudioFormat` per module |
| On-device fallback | `DictationTranscriber` (broader locale coverage, more dialects) | `transcriptionOptions: [.punctuation]`, `reportingOptions: [.volatileResults]` |
| Cloud | `SFSpeechRecognizer` server-based (Apple speech servers) | `requiresOnDeviceRecognition = false`, `shouldReportPartialResults = true`, `addsPunctuation = true`, `taskHint = .dictation`; ~1 minute per request limit |

Fifteen recognisable varieties are offered (Mandarin mainland/Taiwan, Cantonese Hong Kong/mainland, Shanghainese, five Englishes, Japanese, Korean, Spanish, French, German); the on-device module is chosen per locale at runtime.

## Polishing

| Mode | Model | Parameters |
| --- | --- | --- |
| On-device | Apple `SystemLanguageModel` (Apple Intelligence, ~3B, 4,096-token context) | `useCase: .general`, `guardrails: .permissiveContentTransformations`, temperature 0.3, `maximumResponseTokens: 900`, guided generation into `{text, title, summary}`; transcript framed as quoted material so instructions inside it are not followed |
| Cloud | `claude-opus-5-5` (default), `claude-sonnet-5-5`, `claude-haiku-4-5` | `max_tokens: 2048`, `output_config.format` JSON schema, `effort: low`, adaptive thinking, `fallbacks: "default"`, cached system prompt |
| Fallback | rule-based | filler removal per language (en/zh/ja lists), repeat collapsing, capitalisation, terminal punctuation, contraction expansion for formal styles |

Six styles × seven scenarios are expressed as instruction fragments appended to the system prompt.

## Translation

| Mode | Model | Parameters |
| --- | --- | --- |
| On-device | Apple `Translation` framework (`TranslationSession` via `translationTask`) | language packs downloaded on first use; pair availability checked with `LanguageAvailability` |
| Cloud | Claude (same models as above) | one structured request per target |

## Text to speech

`AVSpeechSynthesizer` with the best installed system voice per language (Premium > Enhanced > Default), user-selectable per language in Settings; rate 0.9× default for Chinese, Japanese and Korean.

## Measured metrics

Every transcript stores recogniser, audio length, recognition time, first-result latency, refiner and translator latencies, shown in the detail view and the Markdown export.

| Stage | Environment | Result |
| --- | --- | --- |
| On-device recognition, Mandarin, 8.3 s audio | iPhone 16e, iOS 26 (Kyle's device, 2026-10-06) | recognition 8.9 s (real-time factor 1.07), first result 2.55 s |
| Apple Intelligence polish, Mandarin | iPhone 16e | 2.12 s |
| Apple Translate zh → en, zh → ja | iPhone 16e | completed on device (latency shown per translation in History) |
| Cloud recognition (Apple servers), English 4.9 s sample | iPhone 16e simulator on Mac | recognition 1.2 s, first result 0.32 s, real-time factor 0.24 |
| Apple Intelligence polish, English | simulator | 3.2–9.3 s (first call includes model load) |
| Apple Intelligence polish, Mandarin | simulator | 1.7 s |

Simulator limits: no on-device speech assets, no Translation framework; both paths were validated on the device.
