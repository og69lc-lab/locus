# Locus Airport Intelligence — all-in-one upgrade

## Included

- Airport picker with 40 curated international airports, IATA/ICAO/city/name search, and worldwide Apple Maps search fallback.
- Favourite/recent airports stored locally.
- Aircraft presets: commercial airliner, private jet, turboprop.
- Optional terminal and gate labels, departure holds, arrival transfer holds.
- Taxi-out, takeoff/climb, cruise, approach/landing, taxi-in, followed by optional airport-to-hotel driving route.
- Optional departure hotel-to-airport road route (Apple Maps).
- Route playback with per-stage movement speeds, stop/hold, status labels and estimated altitude.
- Existing Locus pairing, route playback, GPX export, map and other movement modes retained.

## Usage

Open Routes → Airport Intelligence → choose airports → optionally enter hotel/address transfer points → generate. If **Start immediately** is off, choose **Start route** back in Routes. To use the simulator with your paired device, your existing Locus pairing setup must be functioning.

## Important limitations

Airport coordinates approximate airport centres. Taxiing, takeoff and landing paths are **synthetic** and are not actual runway/taxiway or airport traffic-control routes. Terminal and gate inputs are labels only and do **not** locate real gates. The flight segment is an approximate great-circle route and aircraft speeds are presets, not actual flight tracking. Estimated altitude is shown only inside Locus, and the current backend injects coordinate fixes only. Apple Maps search/routing needs network connectivity. This is not a flight/navigation safety application. Snapchat decides its own map and Actionmoji display.

## Build

Use the existing `codemagic.yaml` workflow on branch `feature/airport-intelligence-all-in-one` and download the resulting unsigned IPA for signing/sideloading using the method you already used.
