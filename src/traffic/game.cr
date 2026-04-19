require "./constants"
require "./scene/main_menu"
require "./entity/*"

module Traffic
  class Game < GSDL::Game
    def initialize
      super(
        title: "Traffic",
        logical_width: 1280,
        logical_height: 768,
        fullscreen: true,
      )

      # Configure Cyberpunk Color Scheme
      GSDL::ColorScheme.configure(
        ui_bg: "#131313",       # Blackish
        ui_text: "#FFFFFF",     # Neon Lime
        ui_text_alt: "#99FF33", # Neon Lime
        ui_hover: "#99FF33",    # white
        main: "#99FF33",        # neon Lime
        grass: "#396313",       # darkish olive green
        highlight_alt: GSDL::Color.new(g: 102, b: 255, a: 128), # Transparent Blue
        
        # Car Paint Colors
        car_red: GSDL::Color.from_hex("#f50909"),
        car_green: GSDL::Color.from_hex("#0909f5"),
        car_blue: GSDL::Color.from_hex("#0909f5"),
        car_yellow: GSDL::Color.from_hex("#f5f509"),
        car_silver: GSDL::Color.gray(192),
        car_gray: GSDL::Color.gray(96),
        car_dark_green: GSDL::Color.new(g: 102),
        car_black: GSDL::Color.gray(51),
        car_dark_red: GSDL::Color.new(r: 102),
        car_teal: GSDL::Color.new(g: 102, b: 102),
        car_dark_blue: GSDL::Color.new(b: 102),
        
        # Wrecked Color
        # TODO: uses subtraction, probably should be redone for clarity
        wrecked: GSDL::Color.gray(v: 192, a: 32)
      )
    end

    def init
      Game.draw.to_sdl.default_texture_scale_mode = LibSDL3::ScaleMode::Nearest

      GSDL::Input.set(:camera_up) { GSDL::Keys.pressed?([GSDL::Keys::W, GSDL::Keys::Up]) }
      GSDL::Input.set(:camera_down) { GSDL::Keys.pressed?([GSDL::Keys::S, GSDL::Keys::Down]) }
      GSDL::Input.set(:camera_left) { GSDL::Keys.pressed?([GSDL::Keys::A, GSDL::Keys::Left]) }
      GSDL::Input.set(:camera_right) { GSDL::Keys.pressed?([GSDL::Keys::D, GSDL::Keys::Right]) }
      GSDL::Input.set(:zoom_in) { GSDL::Keys.pressed?(GSDL::Keys::E) }
      GSDL::Input.set(:zoom_out) { GSDL::Keys.pressed?(GSDL::Keys::Q) }

      GSDL::Game.push(Scene::MainMenu.new)
    end

    def load_default_font
      "fonts/Electrolize-Regular.ttf"
    end

    def load_textures : Array(Tuple(String, String))
      [
        {"tiles", "gfx/tiles.png"},
        {"traffic-signal-nb", "gfx/traffic-signal-nb.png"},
        {"traffic-signal-eb", "gfx/traffic-signal-eb.png"},
        {"traffic-signal-sb", "gfx/traffic-signal-sb.png"},
        {"traffic-signal-wb", "gfx/traffic-signal-wb.png"},
        {"car-eb-body", "gfx/car-eb-body.png"},
        {"car-eb-top", "gfx/car-eb-top.png"},
        {"car-nb-body", "gfx/car-nb-body.png"},
        {"car-nb-top", "gfx/car-nb-top.png"},
        {"car-sb-body", "gfx/car-sb-body.png"},
        {"car-sb-top", "gfx/car-sb-top.png"},
        {"ambulance-eb-body", "gfx/ambulance-eb-body.png"},
        {"ambulance-eb-top", "gfx/ambulance-eb-top.png"},
        {"ambulance-nb-body", "gfx/ambulance-nb-body.png"},
        {"ambulance-nb-top", "gfx/ambulance-nb-top.png"},
        {"ambulance-sb-body", "gfx/ambulance-sb-body.png"},
        {"ambulance-sb-top", "gfx/ambulance-sb-top.png"},
      ]
    end

    def load_tile_maps : Array(Tuple(String, String))
      [
        {"traffic", "maps/traffic.json"},
      ]
    end

    def load_audio : Array(Tuple(String, String))
      [
        {"ding", "sfx/ding.wav"},
        {"honk", "sfx/honk.wav"},
        {"crash", "sfx/crash.wav"},
        {"rage_trigger", "sfx/rage_trigger.wav"},
      ]
    end
  end
end
