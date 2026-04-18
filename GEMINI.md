# Project: Traffic (GSDL Game)

`Traffic` is a high-performance chaos management game built using the **GSDL** (GameSDL) library. This project serves as an engine stress-test for GSDL Alpha features, specifically primitives, `FColor` logic, and input handling.

## Core Guidelines
- **Skill Reference:** Always activate and follow the `game-dev-gsdl` skill for expert guidance when building game mechanics, rendering primitives, handling input, or managing scenes with GSDL.
- **Project Structure:** Follow GSDL scene management and entity patterns.
- **Entry Point:** `src/traffic.cr`. All code resides within the `Traffic` namespace.
- **Roadmap:** Current goals and tasks are tracked via Trello as configured in `.gemini/trello_config.json`.

## Game Blueprint: "Greenlit" (Chaos Management)

### 1. Core Concept & Aesthetic
`Traffic` is a fast-paced "Chaos Management" game where you play as a city-wide Traffic Controller. The goal is to manipulate signals to clear paths for priority vehicles while preventing city-wide gridlock.
* **Theme:** Urban/Emergency (High-stakes, neon signals, city hum).
* **Resolution:** 1280 x 720 (Logical Presentation), Borderless Fullscreen.
* **Visual Style:** Top-down grid with color-coded vehicles (Blue/Silver: Civilian, White/Red: Ambulance, Black: Wrecked).

### 2. Key Mechanics
* **Intersection Toggling:** Click intersections to toggle light orientation between North-South Green and East-West Green.
* **Priority Vehicles:** Ambulances and emergency vehicles with "Time to Destination" limits. They lose time rapidly if stopped at red lights.
* **Frustration Meter:** Individual cars have patience levels.
    * **Patient:** Waiting at red light.
    * **Frustrated:** Honking (Audio cues).
    * **Road Rage:** Ignores the signal and drives through, risking a "Gridlock Collision" that blocks the lane.
* **Win Condition:** Safely escort a target number of Priority Vehicles to their destinations.

### 3. Systems Architecture
* **Grid System:** 2D tile-based map representing roads and intersections.
* **Vehicle AI:** Simple path-following logic (Edge A to Edge B).
* **Intersection Logic:** Tracks state (`NS_GREEN` vs `EW_GREEN`) and handles collision detection for vehicles entering the intersection box.
* **Collision Handler:** Detects vehicle overlaps, triggers "Wrecked" state, and halts movement in the affected lane.
* **UI Overlay:** Renders frustration bars above vehicles and a global "Time Remaining" counter for priority tasks.

### 4. Visuals & "Juice" (GSDL Stress Test)
* **Signal Glow:** Use layered `GSDL` primitives for neon bloom effects on active signals.
* **Feedback:**
    * Screen shake on collisions.
    * Dynamic "exclamation point" icons for frustrated drivers.
* **Input:** Primary interaction via `MouseLeft` click to toggle intersections.

## Game Architecture
- **Scenes:** Game logic is encapsulated in scenes (e.g., `Scene::MainMenu`, `Scene::Play`).
- **Entities:** Independent classes for game objects (Vehicles, Intersections) that follow a **State -> Update -> Draw** loop.

## Asset Loading
GSDL uses a hook-based system for loading assets. Define these hooks in your `Game` or `Scene` class to have them loaded automatically.

- **Hook Methods:**
  - `load_textures` : `Array(Tuple(String, String))` — `{"key", "path/to/texture.png"}`
  - `load_tile_maps` : `Array(Tuple(String, String))` — `{"key", "path/to/map.json"}`
  - `load_audio` : `Array(Tuple(String, String))` — `{"key", "path/to/audio.wav"}`
  - `load_fonts` : `Array(Tuple(String, String, Float32))` — `{"key", "path/to/font.ttf", size}`
  - `load_default_font` : `String` — `"path/to/font.ttf"`

- **Accessing Assets:**
  Once defined in a hook, access assets using their manager's `get` method:
  - `GSDL::TextureManager.get("key")`
  - `GSDL::TileMapManager.get("key")`
  - `GSDL::AudioManager.get("key")`
  - `GSDL::FontManager.get("key")`

- **Best Practice:** Load global assets (common UI, main tilemap) in the `Game` class. Load scene-specific assets (unique backgrounds, special effects) in the relevant `Scene` class. Do not load assets manually in `initialize`.

## Coding / Convention Standards
- **Formatting:** Do not run `crystal format`.
- **Whitespace:** Trim all trailing whitespace. Ensure exactly one trailing newline followed by an empty line (double newline total) at the end of every file.
- **Separation of Concerns:** Keep the **Update** logic (physics, collision, state) separated from the **Draw** logic.

## Compiling and Testing
- **Build:** `make build`
- **Run:** `make run`
- **Smoke Test:** `timeout 5s make run || true`

## Development Flow
- **Logic:** Update methods handle physics and input; Draw methods handle rendering.
- **Inputs:**
  - Use `GSDL::Keys` polling for keyboard interaction.
  - Use `GSDL::Mouse` for mouse interaction.

## Constraints & Safety
- **Library Files:** NEVER edit files in `./lib/`. Summarize proposed changes for the user to apply to source repositories.
- **Git:** No write operations (`commit`, `add`, `push`).
- **Dependencies:** Verify usage in `shard.yml` before adding new libraries.

