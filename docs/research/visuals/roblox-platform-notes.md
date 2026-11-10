# Roblox platform notes for visuals

Facts about the engine that constrain UVK. Source ids (P01, L01, F02 ...) are listed in [sources.md](sources.md).

Every row marked **Documented** was read in the Creator Hub documentation source on 2026-11-10 (see the note in sources.md on how those files were retrieved). Rows marked **Not confirmed** are things an implementer will want to know that the documents read did not state; verify them in Studio or the live docs before relying on them. Nothing here was exercised in Studio: all behaviour is `NEEDS MANUAL REVIEW`.

## Particles

| Fact | Evidence | Consequence for UVK |
|---|---|---|
| One emitter creates at most 400 particles per second, 100 per second on mobile | Documented, P01 | Sustained effects must be designed to read at a quarter of the desktop rate. `Quality.scaleCount` should never assume the desktop cap |
| Particle lifetime is capped at 20 seconds; larger values are clamped | Documented, P01 | Long ambient effects need looping emitters, not long lifetimes |
| Large particles cost fill rate: the more pixels they cover, the more GPU cost | Documented, P01 | Full-screen glows and close-up bursts are the expensive ones. Scale size down on Low, not only count |
| Overlapping transparent particles cost overdraw | Documented, P01, P19 | Prefer few, well-shaped particles over many stacked ones |
| Quality of particles changes with the player's graphics setting; test at lowest and highest editor quality | Documented, P01 | Every preset needs a Low check in the manual review list |
| Flipbook layouts: 2x2, 4x4, 8x8 or custom; framerate up to 30 per second; clients deactivate flipbooks when memory is low, likely on older phones | Documented, P01 | A flipbook must never carry meaning. Effects must still read with a static texture |
| Reusing a texture costs less memory than unique textures | Documented, P01 | Supports rule 10 (three built-in textures) |
| `ParticleEmitter:Emit(count)` emits a burst immediately; `Clear()` removes existing particles | Documented, P02 | Bursts use `Emit` on a disabled emitter, which suits pooling |
| Properties available: Acceleration, Brightness, Color, Drag, EmissionDirection, Enabled, Flipbook*, Lifetime, LightEmission, LightInfluence, LockedToPart, Orientation, Rate, Rotation, RotSpeed, Shape, ShapeInOut, ShapePartial, ShapeStyle, Size, Speed, SpreadAngle, Squash, Texture, TimeScale, Transparency, VelocityInheritance, WindAffectsDrag, ZOffset | Documented, P02 | The full parameter surface for the VFX schema |
| `TimeScale` is between 0 and 1 | Documented, P01 | Slow motion is possible per emitter; speeding up is not |
| Changing emitter properties can have a dramatic impact on performance; particles, decals and textures batch poorly | Documented, P19 | Configure an emitter once when it is built or taken from the pool. Do not animate emitter properties every frame |
| Mobile has much lower particle limits than desktop; distant particles may flicker when limits are hit | Documented, P01 | Distance culling and budgets in `Host.effects` are required, not optional |
| The exact global particle budget per device | Not confirmed | Treat budgets as tunable; measure |
| Whether pooled emitters need `Clear()` before reparenting | Not confirmed from docs. A third-party write-up found by search recommends disabling and clearing before reuse | Do it anyway; it is cheap |

## Beams and trails

| Fact | Evidence | Consequence |
|---|---|---|
| A beam is drawn between two attachments as straight segments; `Segments` defaults to 10 | Documented, P03 | Lower segments on Low quality for curved beams |
| Beam properties: Attachment0/1, Brightness, Color, CurveSize0/1, Enabled, FaceCamera, LightEmission, LightInfluence, Segments, Texture, TextureLength, TextureMode, TextureSpeed, Transparency, Width0/1, ZOffset; method `SetTextureOffset` | Documented, P03 | `TextureSpeed` gives a moving rarity beam without any per-frame script |
| Trail properties: Attachment0/1, Brightness, Color, Enabled, FaceCamera, Lifetime, LightEmission, LightInfluence, MaxLength, MinLength, Texture, TextureLength, TextureMode, Transparency, WidthScale; method `Clear` | Documented, P04 | Trails need two attachments on the moving object |
| Trail `Lifetime` defaults to 2 seconds, range 0.01 to 20 | Documented, P04 | Short lifetimes (estimate 0.15 to 0.4 seconds) for fast UI-like streaks |
| `MaxLength` of 0 means no maximum | Documented, P04 | Set a maximum for teleporting objects, or call `Clear()`, to avoid a streak across the map |
| Beam and trail quality varies with graphics setting | Documented, P03, P04 | Review at Low |

## Highlight

| Fact | Evidence | Consequence |
|---|---|---|
| Only 255 highlights display at once on a client; extra ones are silently ignored | Documented, P05 | Budget highlights centrally |
| A disabled highlight still takes one of the 255 slots; delete rather than disable if permanent | Documented, P05 | Pool size must be counted against the limit |
| Toggling `Enabled` has no performance impact; adding or removing a highlight can cause a geometry rebuild and a spike | Documented, P05 | Keep a small pool and re-adorn; do not create one per event |
| The first highlight on screen carries most of the cost, up to about 1 ms of GPU time on mobile; further ones are cheap | Documented, P05 | Decide per quality level whether highlights are allowed at all. Low may use none |
| On mobile, cost rises with screen coverage | Documented, P05 | Avoid highlighting a pet that fills the screen in a reveal on Low |
| Low-end devices may show more pixelated highlights | Documented, P05 | Do not rely on thin outlines for meaning |
| Nesting highlighted objects inside each other causes ordering problems | Documented, P05 | One highlight per reveal subject |
| Highlights are not rendered inside a ViewportFrame | Not confirmed from docs. A DevForum comparison reports that particle and highlight effects were hidden in a ViewportFrame (F02, summary only) | Assume they do not render there |

## UI appearance modifiers

| Fact | Evidence | Consequence |
|---|---|---|
| `UIGradient` applies colour and transparency gradients; properties Color, Enabled, Offset, Rotation, Scale, TileMode, Transparency, Type | Documented, P08 | A shine sweep is an animated `Offset`; a rotating border is an animated `Rotation` |
| A gradient does not apply to descendants; each object needs its own. Supported on Frame, TextLabel, TextButton, ImageLabel, ImageButton, Path2D, ViewportFrame; not on ScrollingFrame or TextBox | Documented, P08 | Themes must add a gradient per styled object |
| `UIStroke` outlines text or a border; properties ApplyStrokeMode, BorderOffset, BorderStrokePosition, Color, Enabled, LineJoinMode, StrokeSizingMode, Thickness, Transparency, ZIndex. A `UIGradient` can be placed under a stroke | Documented, P07 | Rarity borders can be gradient strokes |
| Some stroke properties require the "Improved UIStrokes" Studio beta | Documented, P07 | UVK should use only Color, Thickness, Transparency, LineJoinMode, ApplyStrokeMode until the beta ships. Mark the rest `NEEDS MANUAL REVIEW` |
| Do not tween `Thickness` of a stroke applied to **text**: it re-renders many glyph sizes and may flicker or hurt performance | Documented, P06 | Text emphasis animates `UIScale` or stroke transparency, never text stroke thickness |
| `UIShadow` renders shape or text shadows; some features are in beta | Documented, P06, P27 | Do not depend on it. Fake depth with a darker offset frame |
| `UICorner` supports a uniform radius and per-corner radii | Documented (property list in the class file) | Rounded cards |
| `CanvasGroup` renders descendants as one flattened texture with `GroupTransparency` and `GroupColor3`; always clips descendants | Documented, P09 | Fading a whole panel is one property. Overshoot animations that extend beyond the group's bounds will be clipped |
| `CanvasGroup` flattening only happens when the ScreenGui uses `ZIndexBehavior.Sibling` | Documented, P09 | UVK screens must set Sibling |
| `CanvasGroup` uses extra texture memory, limited by the client's quality level; over the cap it renders as a blank texture. Static sizes are recommended because a size change needs a new texture | Documented, P09 | Use group fade for short transitions on a small number of panels. Avoid tweening the group's own `Size`. Whether scaling it through `UIScale` also forces a new texture is **Not confirmed** |
| `UIScale` multiplies the parent's absolute size | Documented, P16 | Matches UVK's virtual `Scale` property. Press and pop animations go through it |
| Multiple strokes on one object | Not confirmed. A DevForum thread says only one stroke applies per object (F12, summary only); the newer beta may change this | Use a nested frame for a double outline |

## ViewportFrame

| Fact | Evidence | Consequence |
|---|---|---|
| Renders 3D objects inside a 2D rectangle | Documented, P10 | Used for pet icons and previews |
| No shadows and no post-processing are rendered inside it | Documented, P10 | No bloom on a previewed pet. Glow must be faked with UI behind the frame |
| Neon and Glass materials render at the lowest quality | Documented, P10 | "Glowing" variants look flat in previews. Add a UI glow or tint instead |
| Nested GuiObjects are not supported inside it | Documented, P10 | Labels go beside or over the frame |
| Default lighting behaves as if environment specular and diffuse scales are 0; a `Sky` child can serve as a reflection cubemap | Documented, P10 | Metallic pets may look dull unless a Sky is added |
| Lighting is controlled by `Ambient`, `LightColor`, `LightDirection`; Ambient defaults to RGB 200, 200, 200 | Documented, P10 | Themes can tint previews |
| ParticleEmitters do not render in a ViewportFrame | Not confirmed from the docs read. Reported by developers (F01, F02, summary only) | This is why hatch and reveal cinematics place the model in the world in front of the camera, and why UVK's `Eggs` and `Rewards` do that while `Pets.preview` uses a ViewportFrame |
| Animations play inside a ViewportFrame only with a `WorldModel` | Not confirmed in this session | Verify before animating previews with Animator tracks; UVK's procedural idle (CFrame based) avoids the question |
| Many simultaneous ViewportFrames are expensive | Not confirmed in docs. Community reports that a ViewportFrame is cheaper than a world-space cinematic (F02) but give no per-frame figures | Render inventory icons as images where possible; cap live previews |

## TweenService and animation

| Fact | Evidence | Consequence |
|---|---|---|
| Tweenable types: number, boolean, CFrame, Rect, Color3, UDim, UDim2, Vector2, Vector2int16, Vector3, EnumItem | Documented, P11 | NumberSequence and ColorSequence are not tweenable: emitter sequences cannot be tweened natively |
| Two tweens on the same property: the earlier one is cancelled and overwritten | Documented, P11 | Native tweens have no priority or blending. This is the reason for UVK's engine and its conflict rules |
| Tweening on the server replicates the property every frame and looks jittery; tween on the client | Documented, P19 | All UVK motion is client-side |
| UI can also be animated by style transitions through `StyleRule` | Documented, P12 | Out of scope for UVK; noted for completeness |
| Springs are not built into `TweenService` (EasingStyle has Elastic and Back, which are fixed curves) | Assumed from the absence of springs in P11, P12; open-source spring libraries exist for this reason (L01, L02) | UVK `Core/Springs` |

## Post-processing

| Fact | Evidence | Consequence |
|---|---|---|
| Available effects: BloomEffect, BlurEffect, ColorCorrectionEffect, DepthOfFieldEffect, SunRaysEffect, ColorGradingEffect | Documented, P17 | No custom shaders exist. Rule 9 of the architecture stands |
| Blur applies to the whole 3D view and is suggested for backgrounds behind an open menu | Documented, P17 | Menu and reveal backdrops can blur the world |
| ColorCorrection can provide feedback such as tinting the screen at low health | Documented, P17 | A tint is a legitimate feedback channel and is gentler than a flash |
| DepthOfField can focus the player on an item, for example in a shop | Documented, P17 | Reveal cinematics can use it on High and above |
| Post effects are review-sensitive to the quality level | Documented, P17 (the guide tells authors to raise editor quality to see them) | Assume none of them on Low; never encode meaning in bloom |
| Blur does not affect 2D UI | Assumed (the doc says it blurs the 3D world view) | UI backdrops need a dim frame as well |
| Which effects are disabled at which quality level | Not confirmed | Measure |

## Screen, insets and mobile layout

| Fact | Evidence | Consequence |
|---|---|---|
| `ScreenGui.ScreenInsets` defaults to `CoreUISafeInsets`, keeping content clear of the top bar and device cutouts. `None` should only be used for non-interactive backgrounds | Documented, P14 | HUD and screens use the default. Full-screen dimmers and flashes use a separate ScreenGui with `None` |
| `ClipToDeviceSafeArea` defaults to true | Documented, P14 | Slide-in panels parked off-screen stay hidden |
| `SafeAreaCompatibility` defaults to a fullscreen extension mode for objects that cover the safe area | Documented, P14 | Backgrounds extend under notches automatically |
| `GuiService.TopbarInset` is a Rect of the free top-bar area and changes at runtime; `GetGuiInset` returns top-left and bottom-right insets | Documented, P13 | Top-edge currency bars must listen for changes |
| `GuiService.ViewportDisplaySize` is Small (most phones, tablets, handhelds), Medium (laptops, monitors) or Large (TVs) | Documented, P13 | Use it to select the layout and the default quality, not `TouchEnabled` alone |
| On mobile the default controls occupy the bottom-left and bottom-right corners: avoid placing important UI there | Documented, P15 | The reserved zones for every HUD template |
| Thumb zones: frequently used buttons belong near the bottom corners; a position that is comfortable on a phone can be unreachable on a tablet; position custom buttons relative to the jump button | Documented, P15 | The main action button anchors beside the jump button |
| Show only vital information during play; reveal contextual actions when relevant | Documented, P15, P21 | HUD density rules in [design-principles.md](design-principles.md) |
| Scale values are a fraction of the container; offsets are pixels | Documented, P15 | Layout in scale, strokes and padding in offset corrected by `UIScale` |
| Minimum touch target size | Not confirmed in the docs read | UVK uses 44 px as a working minimum (industry convention, an assumption here) |

## Accessibility settings

| Fact | Evidence | Consequence |
|---|---|---|
| `GuiService.ReducedMotionEnabled` is true when the player enabled Reduce Motion in the Roblox or in-experience settings | Documented, P13, P18 | `Host.settings().reducedMotion` must default to this property and follow its changed signal |
| Recommended handling: set tween time to 0 (snap), or replace positional motion with a fade using a `CanvasGroup` | Documented, P18 | UVK: travel becomes a fade or a jump, loops stop, shake is off |
| `GuiService.PreferredTransparency` is 0 to 1; multiply background transparency by it so backgrounds become opaque as it approaches 0 | Documented, P13, P18 | Themes apply it to panel backgrounds |
| `GuiService.PreferredTextSize` is Medium, Large, Larger or Largest | Documented, P13 | Text containers must tolerate growth; avoid fixed-height single-line labels for body text |
| Choose text and background colours with sufficient contrast | Documented, P18 | Checklist item |
| Over 5 percent of people have some colour blindness; do not rely on colour alone, pair it with symbols | Documented, P18 | Rarity needs a text label or icon as well as a colour |
| Do not rely on sound alone | Documented, P18 | Every audio cue has a visual counterpart |
| A platform setting for reduced flashing or photosensitivity | Not confirmed. None appears in P13 or P18 | UVK's `reducedFlashing` is a kit-level setting the game exposes. When `ReducedMotionEnabled` is true, treating flashes as reduced too is a safe default (assumption) |
| Haptics: `HapticService` is client-only and superseded by `HapticEffect`, which supports waveforms on phones and gamepads; output is scaled by the user's haptic preference | Documented, P26 | An optional feedback channel. Out of UVK's current module list; `Feedback` recipes could add a `haptic` step later |

## Quality detection

| Fact | Evidence | Consequence |
|---|---|---|
| `UserGameSettings.SavedQualityLevel` is the level the client set; `GraphicsQualityLevel` exists but its read security is restricted to Roblox scripts | Documented, P25 | Read `SavedQualityLevel` via `UserSettings():GetService("UserGameSettings")`. Automatic mode handling is **Not confirmed**: verify what value "Automatic" reports |
| Low-end devices, especially phones, have severe memory limits; test on a baseline device; the Studio emulator is not accurate for memory | Documented, P20 | Manual review must include a real low-end phone |
| Render stats (Shift F2) show draw calls | Documented, P19 | Use alongside UVK's `Debug` overlay |

## Client and server

| Fact | Evidence | Consequence |
|---|---|---|
| Tween on the client, not the server | Documented, P19 | Architecture rule: visuals are client-side |
| Community practice: server decides and notifies; clients render effects; the acting client may play its own effect immediately and the server relays to others | Documented by forum guides only (F05, F06; summary only) | `Feedback.fire` is called from client handlers of server events; local input feedback fires before the round trip |
| A one-shot broadcast is not seen by players who join later | Documented by a forum thread (F07; summary only) | Persistent states (an aura on a pet) must come from replicated state, not a past event |
| Text and billboard rendering are not cheap; cap the number of indicators and merge hits | Documented by a forum reply the search summary attributes to Roblox staff (F08; summary only, attribution unverified) | `UI.popup` needs a cap, pooling and merging |
