# Kotodama（言霊）

> Word spirits. An AI speech-to-text app for iOS where spoken words carry the
> magic to transcribe, refine and translate thought into text.

In Japanese folklore *kotodama* is the spirit that dwells in words. Kotodama
the app listens to you speak, writes it down, polishes it and translates it.

Built for the Metanomaly iOS programming assignment (AI Speech-to-Text App).

## Status

Skeleton only. This is the stock Xcode SwiftUI + SwiftData template with
naming and file headers set up. Feature work has not started yet.

## Planned features

- Speech recognition for Chinese, English and dialects
- Automatic translation, showing results in other languages
- Switching between language styles and usage scenarios
- Automatically polished output text
- Bonus: switching between on-device and cloud recognition models

## Tech stack

- Swift 5, SwiftUI, SwiftData, Swift Testing
- iOS 26.5+, Xcode 26.6
- Planned: Speech framework (on-device recognition), Translation framework,
  Foundation Models for on-device polishing, a cloud model for the online mode

## Getting started

```sh
open Kotodama.xcodeproj
```

Select the `Kotodama` scheme and run on a device or simulator. Microphone and
speech-recognition permission are requested on first use.

## Project layout

```
Kotodama/            App target (SwiftUI + SwiftData)
KotodamaTests/       Unit tests (Swift Testing)
KotodamaUITests/     UI tests (XCTest)
```

## License

Copyright © 2026 Kyle Zhao. All rights reserved.
