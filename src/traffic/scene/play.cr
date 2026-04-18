module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection
    @vehicles : Array(Vehicle) = [] of Vehicle

    @spawn_timer : GSDL::Timer
    @spawn_interval_min : Float32 = 0.5
    @spawn_interval_max : Float32 = 2.0

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

      @spawn_timer = GSDL::Timer.new(Random.rand(@spawn_interval_min..@spawn_interval_max).seconds)
      @spawn_timer.start

      # Find intersections in the map (gid 6)
      @map.layers.each do |layer|
        if layer.is_a?(GSDL::TileLayer)
          layer.data.each_with_index do |row, y|
            row.each_with_index do |gid, x|
              if (gid & ~GSDL::TileMap::ALL_FLIP_FLAGS) == 6
                @intersections << Intersection.new(x, y, 15)
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
        camera.zoom = 2_f32 if camera.zoom > 2_f32
      end
      if GSDL::Input.action?(:zoom_out)
        camera.zoom -= 1.0_f32 * dt
        camera.zoom = 0.25_f32 if camera.zoom < 0.25_f32
      end

      # Mouse wheel zoom
      wheel_y = GSDL::Mouse.wheel_y
      if wheel_y != 0
        camera.zoom += wheel_y * 0.1_f32
        camera.zoom = 0.25_f32 if camera.zoom < 0.25_f32
        camera.zoom = 2_f32 if camera.zoom > 2_f32
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

      @vehicles.each(&.update(dt, @intersections, @vehicles))
      @vehicles.reject!(&.off_screen?)

      camera.update(dt)
    end

    private def update_spawner(dt : Float32)
      if @spawn_timer.done?
        spawn_vehicle
        @spawn_timer.duration = Random.rand(@spawn_interval_min..@spawn_interval_max).seconds
        @spawn_timer.restart
      end
    end

    private def spawn_vehicle
      # 4 spawn points based on current map (128x128 tiles):
      # Right-hand traffic.
      # Tile 128px. Two lanes of 64px.
      # Lane center is 32px or 96px from tile edge.
      # Horizontal: Y offset = 32-16=16 or 96-16=80.
      # Vertical: X offset = 32-16=16 or 96-16=80.

      vehicle_type = (Random.rand < 0.1) ? VehicleType::Priority : VehicleType::Civilian
      choice = Random.rand(4)

      new_vehicle = case choice
                    when 0 # Eastbound (Bottom lane of row 3, centered at 96px from top)
                      Vehicle.new(vehicle_type, GSDL::Direction::East, -128, 3*128 + 80)
                    when 1 # Westbound (Top lane of row 3, centered at 32px from top)
                      Vehicle.new(vehicle_type, GSDL::Direction::West, 20*128, 3*128 + 16)
                    when 2 # Southbound (Left lane of col 4, centered at 32px from left)
                      Vehicle.new(vehicle_type, GSDL::Direction::South, 4*128 + 16, -128)
                    when 3 # Northbound (Right lane of col 4, centered at 96px from left)
                      Vehicle.new(vehicle_type, GSDL::Direction::North, 4*128 + 80, 11*128)
                    end

      # Safety check: do not spawn if overlapping another vehicle
      if new_vehicle && @vehicles.none? { |v| v.collides?(new_vehicle) }
        @vehicles << new_vehicle
      end
    end

    def draw(draw : GSDL::Draw)
      @map.draw(draw)
      @intersections.each(&.draw(draw))
      @vehicles.each(&.draw(draw))
    end
  end
end
