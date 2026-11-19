# Ember v11 — interface and activity refinement

Open **Ember the Dragon.xcodeproj** in this folder, choose your signing team and Apple Vision Pro, then Run. Version **1.11 (11)**. This updates v11; v10 remains separate.

## Latest changes

- **Repositioning bar visibility (28 October):** the white bar now sits just ahead of the actual nest/garden front edge and slightly above the rim. Its position is recalculated from rendered bounds when scene size changes. A larger grab area stays clear of the garden. Horn behaviour is unchanged in this update. All 452 gameplay/calibration checks and both visionOS source checks pass; headset visibility remains to be tested.

- **Backward horn finish:** completing both forearm-turn exercises eases the movable horns back over 1.25 seconds. Both bases stay seated on the tilted head throughout. Continue becomes available after the transition. Painting retains the backward pose, including when skipping ahead; restarting horn turning restores the upright starting pose. The later complete model retains its existing sculpted backward horns. The movable meshes approximate that silhouette rather than changing their shape.
- **Live, centred scale supply:** the preview is centred in a reserved slot between the Scales title and pickup caption. Shape and rotation choices refresh the model immediately. Pickup restores the normal placement size, and release or a cancelled drag restores the preview. The supply card shares the toolbar plane; Pause has additional clearance above it.
- **Clear activity instructions:** horn turning now explains grip, forearm rotation, hold and return without tracking help replacing the task. Painting explains choosing a colour, picking up the brush, horizontal sweeps and progress. Four back-and-forth sweeps (eight directional strokes) complete one region.

- **One stroke, one brush sound:** each deliberate left-to-right or right-to-left sweep triggers exactly one softened brush cue. More distance or time in the same direction does not replay it. A small reversal threshold rejects hand jitter. Release, leaving the target and pause reset the detector.

- **Softer brushing:** reduced the scratchy high-frequency noise, removed rapid grain modulation, and lowered the brush level by roughly 4–5 dB. Each sweep now uses a smoother envelope. Movement/contact triggers are unchanged.

- **Moonlit activity audio:** the user-selected Moonlit Shimmer (option 4, 1.18 s) now replaces the success sound. Scale pickup uses a short glass lift; valid scale placement uses a soft clink/sparkle. Selecting a paint swatch makes a quiet dab. Horizontal brush travel within a paint target triggers soft bristle sweeps; stationary holds, tracking jitter and off-target motion do not trigger them. Release, pause and stage cleanup stop the brush cue. Completed paint regions retain Moonlit Shimmer. Four new mono clips total about 63 KB of PCM, loaded only when first used, and all respect the sound toggle.

- **Head tilt and horn rest angles (27 October):** the sockets now retain the sculpted head’s resting roll, with outward splay matching the marked front/rear screenshots. The left horn leans outward and the right is nearly upright. Bases are reseated for those angles. Loose horns, placement outlines, attached horns, and forearm-turn targets share the same rest frame. Returning from an individual forearm repetition returns to the tilted starting pose; completing both exercises now settles the horns backward.
- **Sound selection:** the original two-note success tone has been replaced with the selected Moonlit Shimmer. The earlier 0.86-second audition has been superseded. All effects are original synthesized audio without third-party recordings.

- **Crown alignment:** both horn bases now share a fore/aft line just beyond the first beige pair toward the crown, at equal 5 cm offsets from that pair’s measured centreline. Seating depth follows the sculpted scalp. Actual horns and translucent destinations share these points and follow breathing, including after skipping placement.
- **Scale toolbar:** the supply card is directly above the full-width shape selector, with matching visible width. Rotate and Undo share an equal-width row below it; Continue appears underneath without moving the existing controls. The supply model and card use the same layout position.
- **Horn-turn guides:** translucent fists now follow their horns at crown height, in front of the body. The automatic grip target follows the displayed guide. If outside the measured reach, the prompt offers repositioning or the existing Grip button, rather than moving the guides down toward the nest.
- **Photo composition:** a 1–3× zoom slider sits below Left/Right. Drag the picture to compose; Reset restores the original crop. Save and Gallery are adjacent and left aligned. Saved images and refreshed portraits retain the same zoom and framing. Older gallery entries remain readable. Framing uses the existing flat preview without keeping another 3D renderer alive.

- **Matching activity and Pause controls:** the right-side activity buttons and the Pause/close button now reuse the text panel’s charcoal glass material, including its contrast/transparency accessibility adjustments. Controls retain their own proportionate rounded corners, gaze highlight, press feedback and disabled state.

- **Begin/loading fix:** Simulator placement now has an explicit fixed-view fallback after session reset and when recentering. It no longer waits for an unavailable ARKit head anchor. Asset completion publishes scene readiness immediately, without requiring another rendering frame. Physical headsets still wait for a real head pose. Asset load failures show a Retry action on the launcher.
- **Home Gallery:** text and gallery symbol only, without any background, capsule or stroke. The corner inset and accessible hit area remain.

- **Viewing height:** Simulator placement now uses a 1.60 m reference camera, positioning Ember’s centre at 1.57 m and 1.10 m ahead. Physical headsets use the actual tracked view, with Ember only 3 cm below its forward ray. This also applies to Recenter. The Simulator reference assumes its default camera; if its camera has been moved, use the scene bar to adjust.
- **Readability:** a single charcoal tint over glass, primary vibrant text, stronger headings and brighter enabled controls. The calibration track is taller and dark, with a bright mint fill and a visible track edge. Increase Contrast and Reduce Transparency strengthen the panel backing.
- A shared neutral glass style: white typography, 28-point panel corners, 20-point control corners, consistent padding and gaze highlighting. Removed painted white outlines, nested panel borders and the extra Wake button container. The home Gallery action is more subdued.
- Pause now opens a focused menu: Resume first, Restart activity, Settings, Activity controls, and Return to start. Sound, movement and size controls have their own page; previous/skip/start-over controls have a separate testing page. No version/debug caption remains.
- Initial placement waits for a tracked head pose and uses the viewing direction, including a reclined view, while keeping Ember and the nest upright. Recenter remains available in Settings.
- Sleeping Ember fades out, the awake model loads, then fades in. This is a transition between static assets, not a newly rigged wake animation. The two full models are not kept resident together.
- A 2.2-second preparation period precedes calibration capture. Hold progress eases from slow to fast and takes 0.9 seconds of valid holding. Directional captures still require time to reach. Dynamic instruction changes are debounced by 350 ms to reduce flicker.
- Transparent hand edges are discarded by the material to prevent an invisible rectangular plane occluding nearby UI. Guides use neutral grey artwork. The calibration demonstration is kept clear of the instruction panel.
- Environment props use larger sizes with modest random variation and rotation. Their footprints stay within the moss nest and their bases are grounded on it. One bush sits at the front-left and one stone at the front-right. Rocks are approximately 20% larger, and the remaining props are spread around the perimeter rather than grouped together. Activity floor calculations use the nest itself, so taller decorations do not push task guides upward.
- **Horn seating:** horn visuals now use the measured centre of their flat base cap rather than an edge of the mesh. Sockets are equally spaced from the beige-pair centreline, with individual seating depth for the sculpted head. Socket poses follow the body’s breathing transform. Stage boundaries restore the complete control transform and parent, including when horn placement is skipped before wings. Loose horns, destination outlines and attached horns share the corrected pivot. The USDZ models are unchanged.
- The scale supply has a translucent glass panel. Alternating grey hand demonstrations show picking up/placing a scale and turning Ember with two pinches. Demonstrations hide during active manipulation.
- Forearm instructions retain the core task explanation and append one relevant tracking or reach prompt.
- Removed the palette’s white highlight box. The painting square sits forward of the relevant body/wing bounds to avoid intersecting Ember’s head. Region painting and horizontal brush repetitions remain.
- Photobooth has an adjacent Save to gallery / Gallery row. Capture is immediate, with a short flash and a new lightweight shutter sound. Saved portraits show the capture date and time instead of slogans. Export appears beside the status message after saving.

## Previous v11 improvements retained

The approved clay-style sunset home artwork, matching sleeping/awake presentation anchor, calibrated six-stop horn routes, ten concurrent wing repetitions, freeform body scales and two-hand rotation, forearm-turn exercise, regional painting, local gallery, stage-specific asset loading and three existing sound effects remain.

## Validation and limits

415 model/calibration/placement checks pass. Active Swift files pass source typechecks for visionOS 26.5 device and Simulator. The source checks use a temporary RealityKitContent accessor stub outside the delivered project. These checks are not a full Xcode resource build or a headset runtime test; earlier full builds were blocked by package-cache/CoreSimulator access.

Home, pause, instruction, activity-control and photobooth layouts were rendered for review on macOS. macOS ImageRenderer does not render native text fields, pickers, sliders or switches and shows yellow placeholders for them; native visionOS glass must be assessed on the headset. The provided previews are layout references, not headset screenshots. The photobooth preview uses an older placeholder dragon portrait solely to check spacing; the delivered game retains the current USDZ assets. Both hand textures passed transparent-edge pixel checks. Horn fitting was checked with front/rear/elevated rear software geometry previews and 64 cap-to-head surface samples per horn, including five poses along the new backward transition. The cached preview meshes were verified against the shipped USDZ mesh payloads. These are geometry checks, not RealityKit lighting or on-device checks. All eight audio clips were checked for valid PCM data and clipping. Existing USDZ files are unchanged.

## Next AVP playthrough

1. Start while seated and reclined. Confirm Ember appears in front and upright, with the instruction card readable. Test Recenter and the white movement bar.
2. Wake Ember. Check the fade, preparation message, calibration pacing and stable instructions. Compare short and longer comfortable reaches in later activities.
3. Skip horn placement from Pause, then inspect both horns in wings from front, rear and above against the red-marked screenshots. Check the outward lean rather than an upright pair. Also complete placement normally and compare. Watch the bases during breathing, then go back/restart to confirm the fitted pose is restored.
4. Change the scale shape and rotation before pickup: confirm the centred preview changes immediately. Drag, cancel and place scales; confirm the preview resets and the toolbar remains aligned.
5. Complete both horn-turn exercises and watch the 1.25-second backward transition. Pause midway, then resume. Confirm painting keeps the backward pose. Also test skip, back and restart. Confirm tracking help does not hide the task instructions.
6. Select a palette colour and paint each region. Inspect the head square from normal viewing angles. Check the paint-dab and brushing sounds: hold still, move outside the square, release and pause; each should stop producing new brush cues. Check scale pickup versus valid placement feedback. Confirm Sound off silences all effects.
7. In the photobooth, zoom and drag to frame a detail, take a photo, save, and compare the gallery image with the preview. Refresh portrait lighting and verify that composition remains. Check Reset, then turn Ember and reframe. Hear the shutter if sound is enabled and verify the timestamp.

The app cannot guarantee hand visibility outside the headset cameras’ tracking range. Actual comfort, depth, tracking and frame rate still require this device test.
