# Locus Free Real Flights — one-click upgrade

## What is included
- Browse real ADS-B aircraft currently observed near two chosen airports.
- ICAO callsign lookup, aircraft identification, reported heading/altitude/groundspeed and observations age.
- Transient adsbdb callsign route hints, explicitly **unverified**; mismatched route hints are not promoted as confirmed flights.
- Continuous delayed GPS follow using a 180-second ADS-B poll interval and interpolation to prevent sudden jumps.
- Airport runways, taxiways, terminal outlines and mapped gates from OpenStreetMap Overpass; these do NOT identify airline gate assignments.
- Optional real scheduled departure board, terminal and gate details using a free-tier SkyLink RapidAPI key (you obtain it yourself). Key saved in iOS Keychain only.
- Distinct play/stop controls, error messages, source credits and clear limitations.

## How to use
Open **Routes → FREE Real Flights**. Pick departure and arrival airports. Tap **Find real aircraft around both airports** (current positions only) or search a real ICAO callsign such as `UAE515`. Select an observed aircraft and tap **Follow this aircraft in Locus**. Use **Stop live following** to hold the last simulated GPS fix. Use the normal **End spoofing** control to return to real location.

## Pricing and limitations
- Zero payment, signup, or API key necessary for observed aircraft and OpenStreetMap airport maps.
- adsb.lol: **500 requests/day per IP without key**. A poll every 180 seconds uses up to 480 per 24 hours, so scanning and other uses can exhaust quota. The provider can change limits/availability.
- OpenStreetMap Overpass is a community service. Load only on demand; rate limits and missing mapped features may occur.
- There is **no universal, reliable, zero-key free service** that supplies all scheduled future flights, exact assigned airline terminals/gates, runway use and ATC taxi clearance worldwide.
- Optional schedules: SkyLink RapidAPI advertised free plan, around 1,000 calls per month, requires the user's own API key. Not an unlimited free feed.
- ADS-B positions can be delayed or absent and aircraft routes can be mismatched; this is a **simulation and testing tool**, not flight navigation.
- The iPhone location backend injects **coordinates only**, not real aircraft barometric altitude/speed and not Snapchat Actionmoji.
- Background execution and GPS injection are subject to iOS limitations and the connected pairing/tunnel.

## Sources and attributions
- [adsb.lol](https://www.adsb.lol/docs/open-data/api) (ODbL 1.0)
- [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL 1.0), via Overpass
- [adsbdb](https://www.adsbdb.com/) route hints, transient display only; not reproduced into route databases
- [SkyLink Flight Schedules](https://github.com/SkyLink-API/flight-schedules-api) optional free-tier connection

## Build
The GitHub Action creates `feature/free-live-flight-pro` from `feature/airport-intelligence-all-in-one`. Build that branch in Codemagic with its existing `Locus Travel Modes - Unsigned IPA` workflow. This does not alter the working installation until you sideload the new IPA.
