require "./constants"
require "./node_graph"
require "./pathfinder"
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

      neon_lime = "#99ff33"
      neon_red = "#f50909"
      neon_green = "#0909f5"
      neon_blue = "#0909f5"
      neon_yellow = "#f5f509"

      # Configure Cyberpunk Color Scheme
      GSDL::ColorScheme.configure(
        ui_bg: "#131313",       # Blackish
        ui_text: "#FFFFFF",     # white
        ui_text_alt: neon_lime, # Neon Lime
        ui_hover: neon_lime,    # neon
        hud_main: "#FFFFFF",    # white
        main: neon_lime,        # neon Lime
        grass: "#396313",       # darkish olive green
        highlight_alt: GSDL::Color.new(g: 102, b: 255, a: 128), # Transparent Blue

        # Car Paint Colors
        car_red: neon_red,
        car_green: neon_green, # neon green
        car_blue: neon_blue, # neon blue
        car_yellow: neon_yellow, # neon yellow
        car_silver: GSDL::Color.gray(192),
        car_gray: GSDL::Color.gray(96),
        car_dark_green: GSDL::Color.new(g: 102),
        car_black: GSDL::Color.gray(51),
        car_dark_red: GSDL::Color.new(r: 102),
        car_teal: GSDL::Color.new(g: 102, b: 102),
        car_dark_blue: GSDL::Color.new(b: 102),
        # TODO: uses subtraction, probably should be redone for clarity
        wrecked: GSDL::Color.gray(v: 192, a: 32),

        # target neon colors
        target_hospital: neon_red, # neon red
        target_police: neon_blue, # neon red
        target_vip: neon_yellow, # neon red
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

        # traffic intersection
        {"traffic-signal-nb", "gfx/traffic-signal-nb.png"},
        {"traffic-signal-eb", "gfx/traffic-signal-eb.png"},
        {"traffic-signal-sb", "gfx/traffic-signal-sb.png"},
        {"traffic-signal-wb", "gfx/traffic-signal-wb.png"},
        {"traffic-signal-hud", "gfx/traffic-signal-hud.png"},

        # vehicle - civ
        {"car-eb-body", "gfx/car-eb-body.png"},
        {"car-eb-top", "gfx/car-eb-top.png"},
        {"car-nb-body", "gfx/car-nb-body.png"},
        {"car-nb-top", "gfx/car-nb-top.png"},
        {"car-sb-body", "gfx/car-sb-body.png"},
        {"car-sb-top", "gfx/car-sb-top.png"},

        # vehicle - ambulance
        {"ambulance-eb-body", "gfx/ambulance-eb-body.png"},
        {"ambulance-eb-sirens", "gfx/ambulance-eb-top.png"},
        {"ambulance-nb-body", "gfx/ambulance-nb-body.png"},
        {"ambulance-nb-sirens", "gfx/ambulance-nb-top.png"},
        {"ambulance-sb-body", "gfx/ambulance-sb-body.png"},
        {"ambulance-sb-sirens", "gfx/ambulance-sb-top.png"},

        # vehicle - police
        # TODO: copy to gfx dir
        {"cop-eb-body", "gfx/cop-eb-body.png"},
        {"cop-eb-top", "gfx/cop-eb-top.png"},
        {"cop-eb-sirens", "gfx/cop-eb-sirens.png"},
        {"cop-nb-body", "gfx/cop-nb-body.png"},
        {"cop-nb-top", "gfx/cop-nb-top.png"},
        {"cop-nb-sirens", "gfx/cop-nb-sirens.png"},
        {"cop-sb-body", "gfx/cop-sb-body.png"},
        {"cop-sb-top", "gfx/cop-sb-top.png"},
        {"cop-sb-sirens", "gfx/cop-sb-sirens.png"},

        # target destinations
        {"hospital", "gfx/hospital.png"},
        {"police-station", "gfx/police-station.png"},
        # (using placeholders)
        {"penthouse", "gfx/traffic-signal-sb.png"},
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
