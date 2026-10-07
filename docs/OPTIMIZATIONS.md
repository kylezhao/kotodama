# Kotodama · Optimizations

## Implemented

- **Streaming recognition with volatile results**: text appears while speaking; finalised segments are appended, so the UI never waits for the whole utterance.
- **Format conversion once per buffer** with a reused `AVAudioConverter`, deep-copying tap buffers so the audio thread is never blocked by downstream work.
- **Frame-rate-independent metering**: RMS level is computed per buffer and smoothed on the main actor for the orb and spirit field; Canvas drawing runs at 30 Hz.
- **Engine fallback chains** (`RefinementPipeline`, `TranslationPipeline`) try on-device first, then cloud, then rules, so the app always produces polished text and never blocks on a missing model or key.
- **Guided generation** for polishing (typed `{text, title, summary}`) avoids JSON parsing and retries; cloud polishing uses structured output for the same reason.
- **Prompt caching** on the cloud system prompt; `effort: low` for latency.
- **Serial Vision-free pipeline**: speech, polish and translation run sequentially per utterance with per-stage timing recorded, keeping the UI state machine simple and the metrics honest.
- **On-demand assets**: speech models and translation packs download only for the languages in use.

## Candidates not yet done

- Custom vocabulary (names, product terms) for both recognisers.
- Translate targets in parallel instead of sequentially.
- Cloud TTS option for higher-quality voices where the user accepts network use.
- Cache polished results per (text, style, scenario) so switching chips back and forth is instant.
- Background audio session handling for long dictation with the screen locked.
