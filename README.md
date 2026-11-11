# Ski Steps

A step counter for iPhone that reads from Apple Health.

- Big progress ring for today's steps (goes past 100% with a gold second lap)
- Daily goals for steps, distance, calories and active time, plus floors climbed
- Today-by-hour chart, this week's goal rings, streak and best day
- History: week, month, 6 months and year charts with your goal line, tap a bar for details
- Workouts tab: record runs with GPS route, pace and spoken splits; all Apple Health workouts (runs, swims, walks, rides, strength) with maps, splits, laps and strokes
- Auto-detects runs from iPhone motion data and offers to save them; Apple Watch auto-detected workouts appear automatically
- Apple Watch app: daily rings and goals on your wrist, and workouts (runs, walks, pool and open-water swims, rides, strength, HIIT) with heart rate, GPS route and swim laps
- Steps by device (iPhone vs Apple Watch) and heart rate on workouts
- Home Screen widgets (small, medium) and Lock Screen widgets
- "Goal reached" notification, even when the app is closed
- Adjustable daily goal, miles or kilometers

## Install

Every push to `main` builds `SkiSteps.ipa` with GitHub Actions and attaches it to the latest release.

Download the IPA and install it with **Sideloadly** (or AltStore) signed in with your **paid Apple Developer account**. That gives you a 1-year install, and keeps HealthKit, background updates and the widget's app group working.

On first launch, tap **Connect Apple Health** and turn on all categories, then allow notifications.

## Project

SwiftUI, iOS 17+. The Xcode project is generated from `project.yml` with XcodeGen:

```
brew install xcodegen
xcodegen generate
open SkiSteps.xcodeproj
```
