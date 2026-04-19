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

      GSDL::Data.increment("total_escorted", 0)
      GSDL::Data.increment("ambulances", 0)
      GSDL::Data.increment("police", 0)
      GSDL::Data.increment("vips", 0)

      hud = GSDL::HUD.new

      text_data_template = "Total: {total_escorted}\n" \
        "<c:red>A</c>: {ambulances} " \
        "<c:blue>P</c>: {police} " \
        "<c:gold>V</c>: {vips}"
      hud << GSDL::HUDText.new(
        text_data_template: text_data_template,
        anchor: GSDL::Anchor::TopRight,
        offset_x: 8,
        offset_y: 8,
        origin: {1_f32, 0_f32},
        color: GSDL::ColorScheme.get(:hud_main),
        align: GSDL::Font::Align::Right
      )
      self.hud = hud
    end

    def update(dt : Float32)
      if GSDL::Keys.just_pressed?(GSDL::Keys::Escape)
        exit_with_transition
      end

      update_spawner(dt)

      # Zoom controls
      if GSDL::Input.action?(:zoom_in)
        zoom = camera.zoom + 1.0_f32 * dt
        zoom = 2_f32 if zoom > 2_f32
        camera.zoom = zoom
      end
      if GSDL::Input.action?(:zoom_out)
        zoom = camera.zoom - 1.0_f32 * dt
        zoom = 0.25_f32 if zoom < 0.25_f32
        camera.zoom = zoom
      end

      # Mouse wheel zoom
      wheel_y = GSDL::Mouse.wheel_y
      if wheel_y != 0
        zoom = camera.zoom + wheel_y * 0.1_f32
        zoom = 2_f32 if zoom > 2_f32
        zoom = 0.25_f32 if zoom < 0.25_f32
        camera.zoom = zoom
      end

      # Toggle intersections or select vehicles on click
      if GSDL::Mouse.just_pressed?(GSDL::Mouse::ButtonLeft)
        mx, my = GSDL::Mouse.position
        world_mx = (mx / camera.zoom) + camera.x
        world_my = (my / camera.zoom) + camera.y

        clicked_vehicle = @vehicles.find(&.clicked?(world_mx, world_my))

        if clicked_vehicle
          if clicked_vehicle.wrecked?
            @vehicles.delete(clicked_vehicle)
            @selected_vehicle = nil if @selected_vehicle == clicked_vehicle
            GSDL::AudioManager.get("ding").play
          else
            @selected_vehicle = clicked_vehicle
          end
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
      @vehicles.reject! do |vehicle|
        if vehicle.off_screen?(@map.width, @map.height)
          if vehicle.is_a?(VehiclePriority)
            GSDL::Data.increment("total_escorted", 1)
            GSDL::Data.increment("ambulances", 1)
          end
          true
        else
          false
        end
      end

      # Deselect if selected vehicle is gone or wrecked
      if selected = @selected_vehicle
        unless @vehicles.includes?(selected) && !selected.wrecked?
          @selected_vehicle = nil
        end
      end

      camera.update(dt)

      # manually update HUD
      hud.try &.update(dt)
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
      is_priority = Random.rand < 0.1
      choice = Random.rand(4)

      # For initial spawn, we don't know if we need to switch yet.
      # Pathfinding is done AFTER creation.
      kclass = is_priority ? VehiclePriority : VehicleCivilian
      new_vehicle = kclass.new(GSDL::Direction::East, -IntersectionSize, 6 * TileSize + Lane4)

      case choice
      when 0 # Eastbound (Horizontal road at row 6,7)
        new_vehicle = kclass.new(GSDL::Direction::East, -IntersectionSize, 6 * TileSize + Lane4)
      when 1 # Westbound
        new_vehicle = kclass.new(GSDL::Direction::West, @map.width + IntersectionSize, 6 * TileSize + Lane1)
      when 2 # Southbound (Vertical road at col 7,8)
        new_vehicle = kclass.new(GSDL::Direction::South, 7 * TileSize + Lane1, -IntersectionSize)
      when 3 # Northbound
        new_vehicle = kclass.new(GSDL::Direction::North, 7 * TileSize + Lane4, @map.height + IntersectionSize)
      end

      new_vehicle.calculate_path(@intersections)

      # Safety check: do not spawn if overlapping another vehicle
      @vehicles << new_vehicle if @vehicles.none?(&.collides?(new_vehicle))
    end

    def draw(draw : GSDL::Draw)
      # 1. Clear to black to ensure out-of-bounds/menu-bar areas are clean
      draw.color = GSDL::Color::Black
      draw.clear

      # 2. Draw grass background ONLY where the map and viewport intersect
      draw_grass_on_map(draw)

      @map.draw(draw)
      @intersections.each(&.draw(draw))

      if selected = @selected_vehicle
        segments = selected.project_path_segments(@intersections)
        segments.each do |seg|
          GSDL::Box.new(
            width: seg.w,
            height: seg.h,
            x: seg.x,
            y: seg.y,
            color: GSDL::ColorScheme.get(:highlight_alt),
            z_index: -5
          ).draw(draw)
        end
      end

      @vehicles.each(&.draw(draw))

      draw_black_border_past_map(draw)

      # manually draw HUD
      hud.try &.draw(draw)
    end

    def draw_grass_on_map(draw : GSDL::Draw)
      view = camera.viewport_rect
      mw, mh = @map.width.to_f32, @map.height.to_f32

      # Calculate intersection
      ix = Math.max(0_f32, view.x)
      iy = Math.max(0_f32, view.y)
      iw = Math.min(mw, view.x + view.w) - ix
      ih = Math.min(mh, view.y + view.h) - iy

      if iw > 0 && ih > 0
        GSDL::Box.new(
          width: iw,
          height: ih,
          x: ix,
          y: iy,
          color: GSDL::ColorScheme.get(:grass),
          z_index: -20
        ).draw(draw)
      end
    end

    def draw_black_border_past_map(draw : GSDL::Draw)
      # Since the global background is now black, we only need to draw enough of a
      # black border to hide vehicles spawning/despawning just outside the map.
      # Spawn distance is IntersectionSize (2 tiles), so 3 tiles (384px) is plenty.
      bw = TileSize * 2.5_f32
      mw, mh = @map.width.to_f32, @map.height.to_f32

      # Top
      GSDL::Box.new(width: mw + bw * 2, height: bw, x: -bw, y: -bw, color: GSDL::Color::Black, z_index: 50).draw(draw)
      # Bottom
      GSDL::Box.new(width: mw + bw * 2, height: bw, x: -bw, y: mh, color: GSDL::Color::Black, z_index: 50).draw(draw)
      # Left
      GSDL::Box.new(width: bw, height: mh, x: -bw, y: 0, color: GSDL::Color::Black, z_index: 50).draw(draw)
      # Right
      GSDL::Box.new(width: bw, height: mh, x: mw, y: 0, color: GSDL::Color::Black, z_index: 50).draw(draw)
    end
  end
end

