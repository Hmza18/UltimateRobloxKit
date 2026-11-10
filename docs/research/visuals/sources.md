# Sources

Access date for every entry: 2026-11-10.

Three retrieval classes are used. They matter, so read this before trusting a citation.

| Class | Meaning |
|---|---|
| **Full** | The document was downloaded and read in this session |
| **Summary** | The URL came back from a web search and the search tool returned a short summary of it. The page itself was **not** opened (the session's network policy blocked every game wiki, news site, DevForum and Creator Hub host). Claims citing these are only as good as that summary |
| **Listed** | The URL came back in search results but nothing from it was used beyond its existence |

Counts: 52 documents retrieved in full (46 Creator Hub documentation sources, 6 open-source repository files), 30 web searches, 7 direct page fetches attempted and refused by the network policy (see the end of this file).

## P: Roblox platform documentation (Full)

`create.roblox.com` was not reachable. The same documentation is published as source in the public repository `Roblox/creator-docs` (prose under CC BY 4.0, code samples under MIT, per its README), and that is what was read, at `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/<path>`. The Creator Hub URLs below are the published locations that correspond to those repository paths; they were derived from the path, not opened.

| Id | Creator Hub URL | Repository path read | Used for |
|---|---|---|---|
| P01 | https://create.roblox.com/docs/effects/particle-emitters | `effects/particle-emitters.md` | Rate cap, lifetime cap, overdraw, flipbooks |
| P02 | https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter | `reference/engine/classes/ParticleEmitter.yaml` | Property list, `Emit`, `Clear` |
| P03 | https://create.roblox.com/docs/effects/beams and https://create.roblox.com/docs/reference/engine/classes/Beam | `effects/beams.md`, `reference/engine/classes/Beam.yaml` | Beam properties, segments |
| P04 | https://create.roblox.com/docs/effects/trails and https://create.roblox.com/docs/reference/engine/classes/Trail | `effects/trails.md`, `reference/engine/classes/Trail.yaml` | Trail properties, lifetime range |
| P05 | https://create.roblox.com/docs/effects/highlighting and https://create.roblox.com/docs/reference/engine/classes/Highlight | `effects/highlighting.md`, `reference/engine/classes/Highlight.yaml` | 255 limit, mobile cost |
| P06 | https://create.roblox.com/docs/ui/appearance-modifiers | `ui/appearance-modifiers.md` | Gradient, stroke, corner, shadow guidance |
| P07 | https://create.roblox.com/docs/reference/engine/classes/UIStroke | `reference/engine/classes/UIStroke.yaml` | Stroke properties |
| P08 | https://create.roblox.com/docs/reference/engine/classes/UIGradient | `reference/engine/classes/UIGradient.yaml` | Gradient properties and supported objects |
| P09 | https://create.roblox.com/docs/reference/engine/classes/CanvasGroup | `reference/engine/classes/CanvasGroup.yaml` | Group fade caveats |
| P10 | https://create.roblox.com/docs/reference/engine/classes/ViewportFrame and https://create.roblox.com/docs/ui/viewport-frames | `reference/engine/classes/ViewportFrame.yaml`, `ui/viewport-frames.md` | ViewportFrame caveats |
| P11 | https://create.roblox.com/docs/reference/engine/classes/TweenService | `reference/engine/classes/TweenService.yaml` | Tweenable types, conflict rule |
| P12 | https://create.roblox.com/docs/ui/animation | `ui/animation.md` | UI tween guidance |
| P13 | https://create.roblox.com/docs/reference/engine/classes/GuiService | `reference/engine/classes/GuiService.yaml` | ReducedMotionEnabled, PreferredTransparency, PreferredTextSize, TopbarInset, ViewportDisplaySize, GetGuiInset |
| P14 | https://create.roblox.com/docs/reference/engine/classes/ScreenGui | `reference/engine/classes/ScreenGui.yaml` | ScreenInsets, SafeAreaCompatibility, ClipToDeviceSafeArea |
| P15 | https://create.roblox.com/docs/ui/position-and-size | `ui/position-and-size.md` | Scale/offset, reserved zones, thumb zones, context-based UI |
| P16 | https://create.roblox.com/docs/ui/size-modifiers and https://create.roblox.com/docs/reference/engine/classes/UIScale | `ui/size-modifiers.md`, `reference/engine/classes/UIScale.yaml` | UIScale, constraints |
| P17 | https://create.roblox.com/docs/environment/post-processing-effects | `environment/post-processing-effects.md` plus the six effect class files | Available post-processing effects |
| P18 | https://create.roblox.com/docs/production/publishing/accessibility | `production/publishing/accessibility.md` | Reduced motion, transparency, text size, contrast, colour non-reliance |
| P19 | https://create.roblox.com/docs/performance-optimization/improve | `performance-optimization/improve.md` | Draw calls, overdraw, client-side tweening |
| P20 | https://create.roblox.com/docs/performance-optimization/design | `performance-optimization/design.md` | Low-end device guidance |
| P21 | https://create.roblox.com/docs/production/game-design/ui-ux-design | `production/game-design/ui-ux-design.md` | Prioritisation, attention, conventions |
| P22 | https://create.roblox.com/docs/production/game-design/onboarding-techniques | `production/game-design/onboarding-techniques.md` | Arrows, highlights, spotlighting |
| P23 | https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/wireframe-your-layouts | `tutorials/curriculums/user-interface-design/wireframe-your-layouts.md` | Visual hierarchy by screen region |
| P24 | https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/choose-an-art-style | `tutorials/curriculums/user-interface-design/choose-an-art-style.md` | Art style, icon and colour rules |
| P25 | https://create.roblox.com/docs/reference/engine/classes/UserGameSettings | `reference/engine/classes/UserGameSettings.yaml` | Quality level properties |
| P26 | https://create.roblox.com/docs/reference/engine/classes/HapticService and https://create.roblox.com/docs/reference/engine/classes/HapticEffect | the two class files | Haptics |
| P27 | https://create.roblox.com/docs/reference/engine/classes/UIShadow | `reference/engine/classes/UIShadow.yaml` | Shadow modifier (beta) |

Also downloaded but used only to confirm that the class exists: `UICorner`, `BloomEffect`, `BlurEffect`, `ColorCorrectionEffect`, `DepthOfFieldEffect`, `SunRaysEffect`, `ColorGradingEffect`, `Atmosphere`, `ContentProvider`, `Camera`, `ui/frames.md`, `ui/ui-drag-detectors.md`, `tutorials/curriculums/user-interface-design/index.md`.

Four repository paths returned 404 and are therefore not cited: `ui/styling.md`, `ui/best-practices.md`, `effects/custom-particle-effects.md`, `tutorials/curriculums/vfx/index.md`.

## L: Open-source libraries (Full)

| Id | URL | Note |
|---|---|---|
| L01 | https://github.com/Fraktality/spr | README and LICENSE read. Spring motion library, MIT. Motion defined by damping ratio and frequency |
| L02 | https://github.com/Reselim/Flipper | README read. Motor-and-goal animation library |
| L03 | https://github.com/Sleitnick/RbxCameraShaker | README read. Port of a Unity camera shake asset, made with the original authors' written permission |
| L04 | https://github.com/Roblox/creator-docs | README and LICENSE read. States the CC BY 4.0 (prose) and MIT (code samples) licences |

## F: DevForum threads (Summary)

| Id | URL | Note |
|---|---|---|
| F01 | https://devforum.roblox.com/t/how-to-achieve-egg-hatch-animation-without-the-use-of-viewportframes/2568503 | Camera-relative egg instead of ViewportFrame, to keep particles |
| F02 | https://devforum.roblox.com/t/is-it-better-to-use-viewportframe-or-camera-position-to-open-egg/2861023 | Particles and highlights hidden in ViewportFrame; ViewportFrame cheaper |
| F03 | https://devforum.roblox.com/t/how-to-keep-an-egg-in-front-of-the-camera-during-hatch-animations/3637194 | Egg CFrame computed from the camera each frame |
| F04 | https://devforum.roblox.com/t/making-an-egg-hatching-animation/950756 | Invisible root plus Motor6D animation approach |
| F05 | https://devforum.roblox.com/t/client-replication-101-the-guide-to-replicating-effects-to-clients | Initiating client plays first, server relays to others |
| F06 | https://devforum.roblox.com/t/should-my-vfx-scripts-be-on-the-client-or-server/1608975 | Server decides, clients render |
| F07 | https://devforum.roblox.com/t/fireallclients-limitations/933839 | Late joiners miss one-shot events |
| F08 | https://devforum.roblox.com/t/billboard-gui-causing-fps-lag/3542255 | Text and billboards are not low impact; cap and merge indicators |
| F09 | https://devforum.roblox.com/t/damage-numbers-best-approach/3889210 | Damage number approaches |
| F10 | https://devforum.roblox.com/t/whats-the-practical-limit-for-billboardguis-how-many-can-there-be-in-a-scene-before-i-have-to-worry/3958385 | Frequent content edits cost performance |
| F11 | https://devforum.roblox.com/t/free-cartoon-themed-guis/1754465 | Gradient buttons, Back easing praised |
| F12 | https://devforum.roblox.com/t/how-to-recreate-such-ui-style/1943553 | Darker gradient toward button bottom; one stroke per object |
| F13 | https://devforum.roblox.com/t/ez-camera-shake-ported-to-roblox/98482 | Shake bound at camera render priority |
| F14 | https://devforum.roblox.com/t/gg-camera-shake-screenshake-that-doesnt-suck/4731267 | Kick, Perlin and Bounce shake algorithms; positional falloff |
| F15 | https://devforum.roblox.com/t/shakerservice-the-sequal-to-camerashaker/3964127 | A poster speculates the module ignored reduced-motion settings (unconfirmed) |
| F16 | https://devforum.roblox.com/t/spring-driven-motion-spr/714728 | Announcement thread for L01 |
| F17 | https://devforum.roblox.com/t/bring-ui-animations-to-life-with-roact-spring-a-modern-spring-based-animation-library/1670138 | Spring UI library announcement |
| F18 | https://devforum.roblox.com/t/studio-beta-uistroke-improvements-scaling-offsets-and-more/3958036 | Linked from the UIStroke class page (P07); not opened |
| F19 | https://devforum.roblox.com/t/how-would-i-make-a-gui-animation-similar-to-this/538960 | Hover tween on stroke and background |

## G: Game guides, wikis and news (Summary)

### Blox Fruits

| Id | URL | Note |
|---|---|---|
| G01 | https://gamesfuze.com/how-to/roblox-how-to-play-blox-fruits-beginners-guide/ | Bars bottom left, compass on the left, energy drains on dash |
| G02 | https://gamertweak.com/blox-fruits-trello-link-discord-server | Relays the developers' Trello description of bars, level bar, menu button |
| G03 | https://bloxredeem.pages.dev/wiki/blox-fruits/controls | Z X C V and F skill mapping, mobile skill buttons, no rebinding |
| G04 | https://www.wepc.com/gaming/blox-fruits-how-to-awaken-fruits/ | Awakening adds new visual effects |
| G05 | https://bloxredeem.pages.dev/wiki/blox-fruits/awakening | Awakening overview (sources conflict on details) |

### Throw Food For Animals

| Id | URL | Note |
|---|---|---|
| G10 | https://www.sportskeeda.com/roblox-news/throw-food-for-animals-a-beginner-s-guide | Core loop |
| G11 | https://games.gg/roblox/guides/roblox-throw-food-for-animals-beginners-guide/ | Loop: throw, collect, place, upgrade; throw meter |
| G12 | https://www.sportskeeda.com/roblox-news/throw-food-for-animals-mutations-guide | Five mutations, Details button shows chances |
| G13 | https://games.gg/roblox/guides/roblox-throw-food-for-animals-mutations-sizes-guide/ | Mutations and sizes |
| G14 | https://www.sportskeeda.com/roblox-news/how-get-luck-throw-food-for-animals | Luck sets rarity |
| G15 | https://gamerant.com/roblox-throw-food-for-animals-all-food-list-how-to-get/ | Food list |
| G16 | https://www.throwfoodforanimals.wiki/ | Community wiki (Listed) |
| G17 | https://robloxdatabase.com/games/throw-food-for-animals/ | Throw Power overview |
| G18 | https://www.rotrends.com/game/10766972131/Throw-Food-For-Animals | Stats page; developer name and visit count came from summaries of pages like this |
| G19 | https://bloxodes.com/wiki/throw-food-for-animals | Luck builds as the food travels down the lane (fetch refused; summary only) |

### Pet Simulator 99

| Id | URL | Note |
|---|---|---|
| G21 | https://sportskeeda.com/roblox-news/pet-simulator-99-how-hatch-gargantuan-pet-winter-world | Top rarity has its own dedicated hatch animation |
| G22 | https://roblox.fandom.com/wiki/BIG_Games_Pets/Pet_Simulator_99 | Developer and release date |
| G23 | https://sportskeeda.com/roblox-news/roblox-pet-simulator-99-release-date-features | Core loop |
| G24 | https://twinfinite.net/guides/rainbow-pets-pet-simulator-99/ | Gold and rainbow crafting |
| G25 | https://biggames.io/post/pet-simulator-99-update-79 | Official update post (Listed; fetch refused) |

### Pet Simulator X and predecessor

| Id | URL | Note |
|---|---|---|
| G30 | https://www.biggames.io/post/pet-simulator-x-shiny-update | Shiny pets shine in world and in inventory |
| G31 | https://www.gfinityesports.com/article/make-golden-pets-pet-simulator-x | Variant tiers |
| G32 | https://www.gfinityesports.com/article/rainbow-pets-pet-simulator-x | Rainbow machine |
| G33 | https://progameguides.com/roblox/what-does-dark-matter-do-in-roblox-pet-simulator-x/ | Dark Matter tier |
| G34 | https://biggames.io/post/pet-simulator-update-12 | 2018 notes for the first Pet Simulator: triple egg pass; shop UI hidden during the open animation |
| G35 | https://stealthygaming.com/auto-hatch-in-pet-simulator-x/ | Auto hatch |

### Tapping and clicker simulators

| Id | URL | Note |
|---|---|---|
| G40 | https://www.pockettactics.com/tap-simulator-guide | Tap, hatch, rebirth loop |
| G41 | https://allthings.how/roblox-clicker-simulator-how-to-play-from-first-click-to-first-rebirth/ | Loop and naming caution |
| G42 | https://tapsimulator-info.pages.dev/faq | 13 pet rarity tiers (unofficial) |
| G43 | https://bloxodes.com/wiki/tap-simulator-reborn | Clicking anywhere earns coins |
| G44 | https://progameguides.com/roblox/how-to-get-more-rebirths-in-clicker-simulator/ | Rebirth |

### Adopt Me!

| Id | URL | Note |
|---|---|---|
| G50 | https://www.playadopt.me/news/pet-needs-revamp | Official: needs shown above the pet's head, freeing UI space |
| G51 | https://www.ginx.tv/en/?p=69169 | Old needs menu can be restored in Settings |
| G52 | https://thenerdstash.com/?p=493924 | Backpack categories became icons, second page removed |
| G53 | https://allthings.how/adopt-me-backpack-storage-and-releaser-refresh-patch-notes/ | Storage space beside the Backpack |
| G54 | https://progameguides.com/roblox/how-to-use-the-journal-in-roblox-adopt-me/ | Journal shows collection and ages |
| G55 | https://progameguides.com/roblox/how-to-make-a-neon-pet-in-adopt-me | Neon fusion on four circles |
| G56 | https://www.sportskeeda.com/roblox-news/how-make-mega-neon-pet-roblox-adopt-me | Mega Neon |
| G57 | https://gamerjournalist.com/adopt-me-pet-ages-and-all-neon-stages/ | Named neon age stages |
| G58 | https://www.sportskeeda.com/roblox-news/all-mega-neon-paints-adopt-me | Paints change the glow palette |

### Bee Swarm Simulator

| Id | URL | Note |
|---|---|---|
| G60 | https://bee-swarm-simulator.fandom.com/wiki/Ability_Tokens | Tokens spawn from bees, are collected by touch, have a lifespan |
| G61 | https://bee-swarm-simulator.fandom.com/wiki/Bees | Bees follow the player and gather |
| G62 | https://bee-swarm-simulator.fandom.com/wiki/Honey | Main currency |
| G63 | https://bee-swarm-simulator.fandom.com/wiki/Pollen | Pollen converted to honey at the hive |
| G64 | https://bee-swarm-simulator.fandom.com/wiki/Passive_Abilities | Counted token triggers |
| G65 | https://bee-swarm-simulator.fandom.com/wiki/Egg | Egg types, gifted guarantee |
| G66 | https://bee-swarm-simulator.fandom.com/wiki/Diamond_Bee | Rarity plus colour class per bee |
| G67 | https://techwiser.com/bee-swarm-simulator-ability-tokens-how-get/ | Token overview |

### Grow a Garden

| Id | URL | Note |
|---|---|---|
| G70 | https://deltiasgaming.com/grow-a-garden-roblox-complete-mutations-guide | Mutations add visual effects and multipliers |
| G71 | https://deltiasgaming.com/?p=333830 | One mutation: semi-transparent, flashing colours |
| G72 | https://www.sportskeeda.com/roblox-news/grow-garden-radioactive-mutation-guide | Neon green versus darker green variants |
| G73 | https://growagardenwiki.pages.dev/mutations | Golden glow, rainbow pulse, purple glow descriptions (unofficial) |
| G74 | https://gamezebo.com/walkthroughs/grow-a-garden-seeds | Seed rarities |
| G75 | https://deltiasgaming.com/?p=207402 | Shop stock refreshes every 5 minutes for everyone |
| G76 | https://beebom.com/roblox-grow-a-garden-mutation-guide/ | Gold and rainbow screenshots |
| G77 | https://www.pockettactics.com/grow-a-garden-mutations | Multipliers |
| G78 | https://www.sportskeeda.com/roblox-news/all-mutations-grow-garden | Weather as mutation source |

### Steal a Brainrot

| Id | URL | Note |
|---|---|---|
| G80 | https://stealabrainrot.fandom.com/wiki/Base | Lock timer, laser colours per base skin |
| G81 | https://roblox.fandom.com/wiki/BRAZILIAN_SPYDER/Steal_a_Brainrot | Overview |
| G82 | https://games.gg/roblox/guides/steal-a-brainrot-ultimate-beginners-guide/ | Loop, rarities |
| G83 | https://www.u7buy.com/blog/steal-a-brainrot-game-mechanics/ | Mechanics, rebirth |
| G84 | https://poki.com/en/g/steal-a-brainrot | Lock time figure (conflicts with others) |
| G85 | https://www.sportskeeda.com/roblox-news/all-mutations-effects-steal-brainrot | Mutation recolours |
| G86 | https://beebom.com/steal-a-brainrot-mutations-and-traits-list | Mutations (one per unit) and traits (stackable) |
| G87 | https://rblxguide.com/games/steal-a-brainrot/mutations | Mutations |
| G88 | https://op.gg/fr/roblox/wiki/steal-a-brainrot/mutations | Neon purple variant |
| G89 | https://deltiasgaming.com/?p=299967 | Mutations guide |

### Anime simulators and tower defence

| Id | URL | Note |
|---|---|---|
| G90 | https://www.droidgamers.com/guides/anime-vanguards-banner/ | Summon odds per rarity |
| G91 | https://www.gamezebo.com/walkthroughs/anime-defenders-banner/ | Secret unit shown as a silhouette on the banner; 1 and 10 pulls |
| G92 | https://sportskeeda.com/roblox-news/what-secret-units-anime-defenders | Secret tier above Mythic |
| G93 | https://www.sportskeeda.com/roblox-news/how-get-shiny-secret-units-anime-vanguards | Shiny and Secret unlock |
| G94 | https://www.ifanzine.com/anime-defenders-limited-banner-guide/ | Limited banners |
| G95 | https://bloxodes.com/wiki/anime-vanguards/banners | Pity counters |

## Excluded

- Search results that were mirror or content-farm pages (unrelated domains hosting "guides") were ignored.
- Search results advertising exploit scripts ("auto hatch script", "instant hatch hack") were ignored and are not listed. Nothing in this research derives from them.
- No decompiled, leaked or private material was used.

## Fetches refused by the network policy

`bee-swarm-simulator.fandom.com`, `bloxodes.com` (twice), `progameguides.com`, `growagardenwiki.pages.dev`, `biggames.io`, `create.roblox.com`. `devforum.roblox.com` also refused a connection test. To deepen this research, those hosts must be allowed and the pages read in full.
