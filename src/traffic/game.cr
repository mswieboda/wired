require "./scene/main_menu"

module Traffic
  class Game < GSDL::Game
    def initialize
      super(
        title: "Traffic",
        logical_width: 1280,
        logical_height: 720,
        fullscreen: true,
      )

      # Configure Cyberpunk Color Scheme
      GSDL::ColorScheme.configure(
        ui_bg:        "#131313", # Blackish
        ui_text:      "#FFFFFF", # Neon Lime
        ui_text_alt:  "#99FF33", # Neon Lime
        ui_hover:     "#99FF33", # white
        main:         "#99FF33", # Neon Lime
      )
    end

    def init
      Game.draw.to_sdl.default_texture_scale_mode = LibSDL3::ScaleMode::Nearest
      GSDL::Game.push(Scene::MainMenu.new)
    end

    def load_default_font
      "fonts/Electrolize-Regular.ttf"
    end

    def load_textures : Array(Tuple(String, String))
      [
        {"tiles", "gfx/tiles.png"}
      ]
    end

    def load_tile_maps : Array(Tuple(String, String))
      [
        {"traffic", "maps/traffic.json"}
      ]
    end
  end
end
