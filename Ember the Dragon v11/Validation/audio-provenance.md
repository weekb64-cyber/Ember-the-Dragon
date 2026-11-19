# Activity sound provenance

All sounds are original procedural audio created for Ember; no third-party recordings or samples are used. The success sound is the user-selected **Moonlit Shimmer**, option 4 from the preview set (1.18 seconds).

The four companion effects are Scale Pickup (0.28 s), Scale Placement (0.52 s), Paint Colour Dip (0.24 s), and Soft Brush Stroke (0.28 s). Each is mono, 24 kHz, 16-bit PCM. The existing tap, stage-complete and shutter sounds are retained. The separate brushing preview combines three sweeps; gameplay triggers one cue per deliberate directional sweep within the paint target. Continuing in the same direction or holding still cannot retrigger the cue; a deliberate reversal starts the next sweep.

Waveform checks confirm no clipping. New companions have zero-valued endpoints. All eight clips total under 160 KB of PCM and are cached only on first playback. The brush plays at lower volume than confirmations. Actual loudness and timbre still need a headset listening check.

The revised brush uses two-stage low-pass filtered noise and a smooth envelope, with no rapid grain modulation. Its standalone RMS is approximately -34 dBFS and its peak is -20.5 dBFS before the quieter in-game brush multiplier.
