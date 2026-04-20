module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection
    @vehicles : Array(Vehicle) = [] of Vehicle
    @target_areas : Array(TargetArea) = [] of TargetArea
    @selected_vehicle : Vehicle? = nil
    @node_graph : NodeGraph = NodeGraph.new

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

      # Build Node Graph
      @node_graph.build(@map, @intersections)

      # Create Target Areas from Graph Nodes
      @node_graph.nodes.each do |node|
        if node.type.target_ambulance? || node.type.target_police? || node.type.target_vip?
          area = TargetArea.new(node.type, node.x, node.y, node.sprite_offset_x, node.sprite_offset_y)
          @target_areas << area
          add_child(area)
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

      @intersections.each(&.update(dt))

      # Toggle intersections or select vehicles on click
      if GSDL::Mouse.just_pressed?(GSDL::Mouse::ButtonLeft)
        mx, my = GSDL::Mouse.position
        world_mx = (mx / camera.zoom) + camera.x
        world_my = (my / camera.zoom) + camera.y

        clicked_vehicle = @vehicles.find(&.clicked?(world_mx, world_my))

        # Check if any HUD button consumed the click
        if @intersections.any?(&.input_consumed?)
          # HUD Button handled it
        elsif clicked_vehicle
          if clicked_vehicle.wrecked?
            @vehicles.delete(clicked_vehicle)
            @selected_vehicle = nil if @selected_vehicle == clicked_vehicle
            GSDL::AudioManager.get("ding").play
          else
            @selected_vehicle = clicked_vehicle
          end
        else
          clicked_intersection = @intersections.find(&.clicked?(world_mx, world_my))
          if clicked_intersection && !clicked_intersection.flip_disabled?
            if clicked_intersection.selected?
              clicked_intersection.toggle
              clicked_intersection.selected = false
            else
              # Deselect others
              @intersections.each { |i| i.selected = false if i != clicked_intersection }
              clicked_intersection.selected = true
            end
            @selected_vehicle = nil
          elsif clicked_intersection
            # Flip/Action was disabled, keep selection
          else
            @intersections.each { |i| i.selected = false }
            @selected_vehicle = nil
          end
        end
      end

      @map.update(dt)
      # @intersections.each(&.update(dt))
      @target_areas.each(&.update(dt))

      @vehicles.each(&.update(dt, @intersections, @vehicles))
      @vehicles.reject! do |vehicle|
        if vehicle.finished? || vehicle.off_screen?(@map.width, @map.height)
          if vehicle.is_a?(VehiclePriority) && (vehicle.finished? || vehicle.target_reached?)
            GSDL::Data.increment("total_escorted", 1)
            if node_type = vehicle.target_node.try(&.type)
              case
              when node_type.target_ambulance? then GSDL::Data.increment("ambulances", 1)
              when node_type.target_police?    then GSDL::Data.increment("police", 1)
              when node_type.target_vip?       then GSDL::Data.increment("vips", 1)
              else # it was an exit
                GSDL::Data.increment("ambulances", 1) # fallback
              end
            end
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
      is_priority = Random.rand < 0.8
      choice = Random.rand(4)

      # Initial spawn location
      dir, sx, sy = case choice
                    when 0 then {GSDL::Direction::East, -IntersectionSize, 6 * TileSize + Lane4}
                    when 1 then {GSDL::Direction::West, @map.width + IntersectionSize, 6 * TileSize + Lane1}
                    when 2 then {GSDL::Direction::South, 7 * TileSize + Lane1, -IntersectionSize}
                    when 3 then {GSDL::Direction::North, 7 * TileSize + Lane4, @map.height + IntersectionSize}
                    else        {GSDL::Direction::East, -IntersectionSize, 6 * TileSize + Lane4}
                    end

      new_vehicle = if is_priority
                      # Randomly choose priority type (excluding VIP for now)
                      type = Random.rand < 0.6 ? PriorityType::Ambulance : PriorityType::Police
                      VehiclePriority.new(dir, sx, sy, type)
                    else
                      VehicleCivilian.new(dir, sx, sy)
                    end

      new_vehicle.select_target(@node_graph)
      new_vehicle.calculate_path(@node_graph)

      # Safety check: do not spawn if overlapping another vehicle
      if new_vehicle.target_node && @vehicles.none?(&.collides?(new_vehicle))
        if new_vehicle.path.empty? && !new_vehicle.target_reached?
           # puts "Vehicle spawned with no path and not at target! (Target: #{new_vehicle.target_node.try(&.type)})"
        end
        @vehicles << new_vehicle
      else
        # puts "Vehicle failed to spawn: No target or collision detected. (Target: #{new_vehicle.target_node.try(&.type)})"
      end
    end

    def draw(draw : GSDL::Draw)
      # 1. Clear to black to ensure out-of-bounds/menu-bar areas are clean
      draw.color = GSDL::Color::Black
      draw.clear

      # 2. Draw grass background ONLY where the map and viewport intersect
      draw_grass_on_map(draw)

      @map.draw(draw)
      @intersections.each(&.draw(draw))
      @target_areas.each(&.draw(draw))

      # draw_debug_graph(draw) # Uncomment to see nodes and connections

      # 3. Draw vehicles
      if selected = @selected_vehicle
        selected.draw_path(draw, @intersections)
      end
      @vehicles.each(&.draw(draw))

      # 4. Draw Black border around map
      draw_black_border_past_map(draw)

      # manually draw HUD
      hud.try &.draw(draw)
    end

    def draw_debug_graph(draw : GSDL::Draw)
      @node_graph.nodes.each do |node|
        color = case node.type
                when .intersection? then GSDL::Color::White
                when .exit?         then GSDL::Color::Red
                else GSDL::Color::Green
                end

        # Draw node
        GSDL::Box.new(width: 16, height: 16, x: node.x - 8, y: node.y - 8, color: color, z_index: 100).draw(draw)

        # Draw connections
        node.connections.each do |conn|
           # draw line between node and conn
           # GSDL doesn't have a simple Line primitive yet? Let's use a very thin box
           dx = conn.x - node.x
           dy = conn.y - node.y
           dist = Math.sqrt(dx*dx + dy*dy)
           # simplified: only horizontal/vertical lines in our grid
           if dx.abs > 1
             GSDL::Box.new(width: dx.abs.to_f32, height: 2_f32, x: Math.min(node.x, conn.x).to_f32, y: node.y - 1.0_f32, color: GSDL::Color.new(r: 255, g: 255, b: 0, a: 128), z_index: 90).draw(draw)
           elsif dy.abs > 1
             GSDL::Box.new(width: 2_f32, height: dy.abs.to_f32, x: node.x - 1.0_f32, y: Math.min(node.y, conn.y).to_f32, color: GSDL::Color.new(r: 255, g: 255, b: 0, a: 128), z_index: 90).draw(draw)
           end
        end
      end
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
