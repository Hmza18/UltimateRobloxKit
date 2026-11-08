# Lighting presets

Starting values only. Tune by eye on the target devices. Colours are RGB 0-255.

| Property | Day (outdoor) | Night | Interior | Horror | Stylized bright |
|---|---|---|---|---|---|
| Technology | ShadowMap | Future | Future | Future | ShadowMap |
| ClockTime | 14 | 0 | 14 (unused indoors) | 1 | 13 |
| Brightness | 2.5 | 0.5 | 1 | 0.2 | 3 |
| Ambient | 70,70,70 | 20,22,40 | 40,36,32 | 8,8,12 | 110,110,120 |
| OutdoorAmbient | 128,128,140 | 45,50,90 | 60,60,60 | 15,15,25 | 160,160,175 |
| EnvironmentDiffuseScale | 1 | 0.5 | 0.6 | 0.2 | 0.3 |
| EnvironmentSpecularScale | 1 | 0.6 | 0.6 | 0.4 | 0.2 |
| ExposureCompensation | 0 | 0.2 | 0.2 | -0.3 | 0.1 |
| ShadowSoftness | 0.2 | 0.3 | 0.4 | 0.1 | 0.6 |
| Atmosphere Density | 0.3 | 0.35 | 0 (or remove) | 0.55 | 0.2 |
| Atmosphere Color | 199,210,225 | 60,70,110 | - | 30,30,40 | 220,235,255 |
| Atmosphere Haze | 1 | 1.5 | - | 2.5 | 0 |
| Atmosphere Glare | 0 | 0 | - | 0 | 0.3 |
| Bloom Intensity / Size / Threshold | 0.4 / 24 / 0.95 | 0.8 / 30 / 0.9 | 0.5 / 24 / 0.95 | 0.3 / 40 / 0.9 | 0.6 / 28 / 0.9 |
| ColorCorrection Saturation | 0.05 | -0.1 | 0 | -0.4 | 0.3 |
| ColorCorrection Contrast | 0.05 | 0.1 | 0.05 | 0.25 | 0.1 |
| ColorCorrection TintColor | 255,255,255 | 210,220,255 | 255,245,230 | 220,230,220 | 255,250,240 |
| SunRays Intensity | 0.05 | 0 | 0 | 0 | 0.1 |
| Shadow-casting local lights in view | 0-2 | 4-6 | 4-8 | 2-4 (flashlight counts) | 0-2 |

Notes:

- **Night:** keep it navigable. Moonlit `OutdoorAmbient` plus warm local lights at points of interest.
- **Interior:** zone-swap from the outdoor preset on entry; turn Atmosphere density down rather than deleting it at runtime.
- **Horror:** contrast and pools of light, a player flashlight `SpotLight` with Shadows, and a brightness slider in settings.
- **Stylized bright:** low environment specular and soft shadows give a clean toy-like look; strong accent colours on interactives.
