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
- HealthFit-style charts: active energy and exercise minutes vs your average day, resting energy
- Insights: Fitness (CTL), Fatigue (ATL), Form (TSB), training load ratio, training focus, 7-day goals
- Workouts grouped by month with route maps and place names
- Home Screen widgets (small, medium) and Lock Screen widgets
- "Goal reached" notification, even when the app is closed
- Adjustable daily goal, miles or kilometers

## Install (TestFlight)

Every push to `main` builds, signs (with HealthKit) and uploads the iPhone + Apple Watch app to TestFlight. Install it from the TestFlight app.

One-time setup:
1. App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys › **+** (Access: **Admin**). Note the **Issuer ID** and **Key ID**, and download the `.p8` key.
2. developer.apple.com › Account › Membership details: note your **Team ID**.
3. This repo › Settings › Secrets and variables › Actions › New repository secret:
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (the full text of the .p8 file), `APPLE_TEAM_ID`.
4. After the first TestFlight run registers the app's ID, create the app: App Store Connect › Apps › **+** › New App, bundle ID `com.skistudio.steps`. Then re-run the TestFlight workflow.

Sideloading the unsigned IPA from Releases is not recommended: Apple Health only works when the app is signed with the HealthKit capability.

## Project

SwiftUI, iOS 17+. The Xcode project is generated from `project.yml` with XcodeGen:

```
brew install xcodegen
xcodegen generate
open SkiSteps.xcodeproj
```
