Vendored Lottie assets for highlight gift overlay

Files:
- goose_talk.lottie
- goose_talk.json
- red_megaphone.lottie
- red_megaphone.json
- gift_power_flare.json
- gift_shock_pulse.json
- gift_heart_bloom.json
- gift_tear_halo.json
- gift_crown_glow.json
- gift_heal_orbit.json

Source pages:
- Goose Talk by James Gibbs: https://lottiefiles.com/free-animation/goose-talk-DjHspZ1RIC
- Red megaphone by dan hadar: https://lottiefiles.com/free-animation/red-megaphone-hmtoIhNU4g

License:
- Listed on LottieFiles as free to use under the Lottie Simple License.

Local custom assets:
- `gift_*.json` are locally authored lightweight Lottie JSON badge actors used by
	non-goose highlight gift overlays. They are intentionally simple placeholders
	until design delivers final per-emotion `.lottie` / `.riv` packages.

These files are vendored locally so the Flutter client can render the right-top
highlight mascot without relying on runtime network requests.

The JSON files are extracted from the dotLottie packages for maximum Flutter
runtime compatibility. When a final production design package is available
(.lottie / .riv / SVGA / image sequence), replace these files and keep the
widget integration unchanged.
