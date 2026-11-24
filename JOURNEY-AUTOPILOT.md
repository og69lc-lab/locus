# Journey Autopilot

This is scheduled GPS simulation, not proof of actual travel. It does not independently retrieve or book flights. No paid API is required for playback. ChatGPT or another planner supplies itinerary times and route geometry.

## Use
Open Journey Autopilot on the map screen. Import or paste the JSON, review and tap Start. Pause holds the last location; the real clock continues. Resume samples the current scheduled location. Imported plans persist across app launches; after force quit reopen and explicitly resume. iOS may suspend background execution or lose the developer tunnel. At the end, Locus attempts to restore real GPS. Do not use simulated location for emergencies or navigation.

## JSON v1
See examples/journey-example.json (fictional test coordinates). Each leg contains title, mode, start/end (ISO-8601 whole seconds, UTC recommended), optional IANA timeZone and notes, and an array of points containing latitude and longitude. Modes: stay, walk, run, cycle, drive, flight, ship, train. Stay has one point; moving legs have two or more. Adjacent times must match exactly and coordinates must connect within 1 meter. Limits: 2 MB, 100,000 points, 10,000 activities, 366 days. Movement is interpolated by path distance over the scheduled duration; it is not live aircraft/traffic data. Supply real road geometry or labeled estimated flight paths, not invented confirmed gates or bookings.
