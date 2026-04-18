module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection
    @vehicles : Array(Vehicle) = [] of Vehicle
    @selected_vehicle : Vehicle? = nil

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
      camera.speed = 1000.0_f32

      @spawn_timer = GSDL::Timer.new(Random.rand(@spawn_interval_min..@spawn_interval_max).seconds)
      @spawn_timer.start

      # Find intersections in the map (gid 5 is top-left of intersection)
      @map.layers.each do |layer|
        if layer.is_a?(GSDL::TileLayer)
          layer.data.each_with_index do |row, y|
            row.each_with_index do |gid, x|
              if (gid & ~GSDL::TileMap::ALL_FLIP_FLAGS) == 5
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

      # Toggle intersections or select vehicles on click
      if GSDL::Mouse.just_pressed?(GSDL::Mouse::ButtonLeft)
        mx, my = GSDL::Mouse.position
        world_mx = (mx / camera.zoom) + camera.x
        world_my = (my / camera.zoom) + camera.y

        clicked_vehicle = @vehicles.find(&.clicked?(world_mx, world_my))

        if clicked_vehicle
          @selected_vehicle = clicked_vehicle
        else
          clicked_intersection = @intersections.find(&.clicked?(world_mx, world_my))
          if clicked_intersection
            clicked_intersection.toggle
          else
            @selected_vehicle = nil
          end
        end
      end

      @map.update(dt)
      @intersections.each(&.update(dt))

      @vehicles.each(&.update(dt, @intersections, @vehicles))
      @vehicles.reject!(&.off_screen?)

      # Deselect if selected vehicle is gone or wrecked
      if selected = @selected_vehicle
        unless @vehicles.includes?(selected) && !selected.wrecked?
          @selected_vehicle = nil
        end
      end

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
      # Adjusted based on traffic.json: Row 6,7 is road. Col 7,8 is road.
      vehicle_type = (Random.rand < 0.1) ? VehicleType::Priority : VehicleType::Civilian
      choice = Random.rand(4)

      # For initial spawn, we don't know if we need to switch yet.
      # Pathfinding is done AFTER creation.
      new_vehicle = case choice
                    when 0 # Eastbound (Horizontal road at row 6,7)
                      Vehicle.new(vehicle_type, GSDL::Direction::East, -IntersectionSize, 6 * TileSize + Lane4)
                    when 1 # Westbound
                      Vehicle.new(vehicle_type, GSDL::Direction::West, 14 * TileSize + IntersectionSize, 6 * TileSize + Lane1)
                    when 2 # Southbound (Vertical road at col 7,8)
                      Vehicle.new(vehicle_type, GSDL::Direction::South, 7 * TileSize + Lane1, -IntersectionSize)
                    when 3 # Northbound
                      Vehicle.new(vehicle_type, GSDL::Direction::North, 7 * TileSize + Lane4, 13 * TileSize + IntersectionSize)
                    end

      if new_vehicle
        new_vehicle.calculate_path(@intersections)

        # Safety check: do not spawn if overlapping another vehicle
        if @vehicles.none? { |v| v.collides?(new_vehicle) }
          @vehicles << new_vehicle
        end
      end
    end

    def draw(draw : GSDL::Draw)
      @map.draw(draw)
      @intersections.each(&.draw(draw))

      # Detailed Magenta Debug Lines
      old_scale_x, old_scale_y = draw.current_scale_x, draw.current_scale_y
      draw.scale = camera.zoom
      cam_x, cam_y = camera.x, camera.y
      debug_color = GSDL::Color.new(255, 0, 255, 180)
      thickness = 4.0_f32

      # Horizontal lanes (Row 6, 7)
      [{"L1", Lane1}, {"L2", Lane2}, {"L3", Lane3}, {"L4", Lane4}].each do |label, offset|
        ly = 6 * TileSize + offset - cam_y
        draw.rect_fill(GSDL::FRect.new(0 - cam_x, ly - thickness/2, 14 * TileSize, thickness), debug_color, 10)
      end

      # Vertical lanes (Col 7, 8)
      [{"L1", Lane1}, {"L2", Lane2}, {"L3", Lane3}, {"L4", Lane4}].each do |label, offset|
        lx = 7 * TileSize + offset - cam_x
        draw.rect_fill(GSDL::FRect.new(lx - thickness/2, 0 - cam_y, thickness, 13 * TileSize), debug_color, 10)
      end

      draw.scale = {old_scale_x, old_scale_y}

      if selected = @selected_vehicle
        old_sx, old_sy = draw.current_scale_x, draw.current_scale_y
        draw.scale = camera.zoom
        segments = selected.project_path_segments(@intersections)
        segments.each do |seg|
          draw.rect_fill(GSDL::FRect.new(seg.x - camera.x, seg.y - camera.y, seg.w, seg.h), GSDL::Color.new(0, 100, 255, 128), -5)
        end
        draw.scale = {old_sx, old_sy}
      end

      @vehicles.each(&.draw(draw))
    end
  end
end
