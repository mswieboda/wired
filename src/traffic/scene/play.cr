module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection

    def initialize
      super(:main_menu)
      
      # Assets are loaded automatically via Traffic::Game hooks
      @map = GSDL::TileMapManager.get("traffic")
      @map.z_index = -10
      
      # Zoom out 2x
      GSDL::Game.camera.zoom = 0.5_f32

      # Find intersections in the map (gid 6)
      @map.layers.each do |layer|
        if layer.is_a?(GSDL::TileLayer)
          layer.data.each_with_index do |row, y|
            row.each_with_index do |gid, x|
              if (gid & ~GSDL::TileMap::ALL_FLIP_FLAGS) == 6
                @intersections << Intersection.new(x, y)
              end
            end
          end
        end
      end
    end

    def update(dt : Float32)
      if GSDL::Keys.just_pressed?(GSDL::Keys::Escape)
        exit_with_transition
      end
      
      # Toggle intersections on click
      if GSDL::Mouse.just_pressed?(GSDL::Mouse::ButtonLeft)
        mx, my = GSDL::Mouse.position
        @intersections.each do |intersection|
          if intersection.clicked?(mx, my)
            intersection.toggle
          end
        end
      end
      
      @map.update(dt)
      @intersections.each(&.update(dt))
    end

    def draw(draw : GSDL::Draw)
      # Disable culling to ensure everything is drawn regardless of camera bounds
      # draw.culling_enabled = false

      @map.draw(draw)
      @intersections.each(&.draw(draw))
    end
  end
end
