module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection
    @vehicles : Array(Vehicle) = [] of Vehicle
    
    @spawn_timer : Float32 = 0.0
    @spawn_interval : Float32 = 0.5 # Faster spawn for testing

    def initialize
      super(:main_menu)
      
      # Assets are loaded automatically via Traffic::Game hooks
      @map = GSDL::TileMapManager.get("traffic")
      @map.z_index = -10
      
      # Camera configuration
      camera.type = GSDL::Camera::Type::Manual
      camera.zoom = 0.5_f32
      camera.set_boundary(@map)
      camera.speed = 1000.0_f32 # Faster camera for larger map
      
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
      
      update_spawner(dt)
      
      # Zoom controls
      if GSDL::Input.action?(:zoom_in)
        camera.zoom += 1.0_f32 * dt
      end
      if GSDL::Input.action?(:zoom_out)
        camera.zoom -= 1.0_f32 * dt
        camera.zoom = 0.1_f32 if camera.zoom < 0.1_f32
      end
      
      # Toggle intersections on click
      if GSDL::Mouse.just_pressed?(GSDL::Mouse::ButtonLeft)
        mx, my = GSDL::Mouse.position
        world_mx = (mx / camera.zoom) + camera.x
        world_my = (my / camera.zoom) + camera.y
        
        @intersections.each do |intersection|
          if intersection.clicked?(world_mx, world_my)
            intersection.toggle
          end
        end
      end
      
      @map.update(dt)
      @intersections.each(&.update(dt))
      
      @vehicles.each(&.update(dt, @intersections))
      @vehicles.reject!(&.off_screen?)
      
      camera.update(dt)
    end

    private def update_spawner(dt : Float32)
      @spawn_timer -= dt
      if @spawn_timer <= 0
        spawn_vehicle
        @spawn_timer = @spawn_interval
      end
    end

    private def spawn_vehicle
      # 4 spawn points based on current map (128x128 tiles):
      # Right-hand traffic.
      # Tile 128px. Two lanes of 64px.
      # Lane center is 32px or 96px from tile edge.
      # Vehicle is 64x32. If we want it "centered" in 64px lane:
      # Horizontal: Y offset = 32 - 16 = 16.
      # Vertical: X offset = 32 - 32 = 0? (since car is 64 wide).
      
      vehicle_type = (Random.rand < 0.1) ? VehicleType::Priority : VehicleType::Civilian
      choice = Random.rand(4)
      
      case choice
      when 0 # Eastbound (Bottom lane of row 3)
        # Shift up 8px closer to center
        @vehicles << Vehicle.new(vehicle_type, GSDL::Direction::East, -128, 3*128 + 72)
      when 1 # Westbound (Top lane of row 3)
        # Shift down 8px closer to center
        @vehicles << Vehicle.new(vehicle_type, GSDL::Direction::West, 20*128, 3*128 + 24)
      when 2 # Southbound (Left lane of col 4)
        # Shift right 8px closer to center
        @vehicles << Vehicle.new(vehicle_type, GSDL::Direction::South, 4*128 + 8, -128)
      when 3 # Northbound (Right lane of col 4)
        # Shift left 8px closer to center
        @vehicles << Vehicle.new(vehicle_type, GSDL::Direction::North, 4*128 + 56, 11*128)
      end
    end

    def draw(draw : GSDL::Draw)
      @map.draw(draw)
      @intersections.each(&.draw(draw))
      @vehicles.each(&.draw(draw))
    end
  end
end
