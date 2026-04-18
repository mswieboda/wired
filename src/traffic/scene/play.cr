module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap

    def initialize
      super(:main_menu)
      
      # Assets are loaded automatically via Traffic::Game hooks
      @map = GSDL::TileMapManager.get("traffic")
    end

    def update(dt : Float32)
      if GSDL::Keys.just_pressed?(GSDL::Keys::Escape)
        exit_with_transition
      end
      
      @map.update(dt)
    end

    def draw(draw : GSDL::Draw)
      @map.draw(draw)
    end
  end
end
