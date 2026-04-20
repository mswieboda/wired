require "./pause_scene"

module Traffic
  class Scene::Play < GSDL::Scene
    @map : GSDL::TileMap
    @intersections : Array(Intersection) = [] of Intersection
    @vehicles : Array(Vehicle) = [] of Vehicle
    @target_areas : Array(TargetArea) = [] of TargetArea
    @selected_vehicle : Vehicle? = nil
    @node_graph : NodeGraph = NodeGraph.new
    @spawn_points : Array(Tuple(GSDL::Direction, Float32, Float32)) = [] of Tuple(GSDL::Direction, Float32, Float32)

    @spawn_timer : GSDL::Timer
    @spawn_interval_min : Float32 = VehicleSpawnIntervalMin
    @spawn_interval_max : Float32 = VehicleSpawnIntervalMax

    @ambulance_ui_strikes : GSDL::AnimatedSprite
    @cop_ui_strikes : GSDL::AnimatedSprite

    def initialize
      super(:main_menu)

      # Assets are loaded automatically via Traffic::Game hooks
      @map = GSDL::TileMapManager.get("traffic")
      @map.z_index = -10

      # Camera configuration
      camera.type = GSDL::Camera::Type::Manual
      camera.zoom = 0.5_f32
      camera.set_boundary(@map)
      camera.speed = CameraSpeed

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
      @spawn_points = @node_graph.get_spawn_points(@map)

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
      GSDL::Data.increment("ambulances_x", 0)
      GSDL::Data.increment("police", 0)
      GSDL::Data.increment("police_x", 0)
      GSDL::Data.increment("vips", 0)
      GSDL::Data.increment("vips_x", 0)

      hud = GSDL::HUD.new

      text_data_template = "Total: {total_escorted}\n" \
        "<c:red>A</c>: {ambulances}\n" \
        "<c:blue>P</c>: {police}"
      hud << GSDL::HUDText.new(
        text_data_template: text_data_template,
        anchor: GSDL::Anchor::TopRight,
        offset_x: 8,
        offset_y: 8,
        origin: {1_f32, 0_f32},
        color: GSDL::ColorScheme.get(:hud_main),
        align: GSDL::Font::Align::Right
      )
      hud << GSDL::HUDText.new(
        text_data_template: text_data_template,
        anchor: GSDL::Anchor::TopRight,
        offset_x: 8,
        offset_y: 8,
        origin: {1_f32, 0_f32},
        color: GSDL::ColorScheme.get(:hud_main),
        align: GSDL::Font::Align::Right
      )

      # UI icon for ambulance
      @ambulance_ui = GSDL::Sprite.new("ambulance-ui", origin: {1_f32, 1_f32})
      @ambulance_ui.draw_relative_to_camera = false
      @ambulance_ui.x = Game.width - 8
      @ambulance_ui.y = 112
      @ambulance_ui.z_index = 150

      # UI XXX for ambulance
      @ambulance_ui_strikes = GSDL::AnimatedSprite.new("ambulance-ui-strikes", 64, 32, origin: {1_f32, 1_f32})
      @ambulance_ui_strikes.draw_relative_to_camera = false
      @ambulance_ui_strikes.x = @ambulance_ui.x
      @ambulance_ui_strikes.y = @ambulance_ui.y
      @ambulance_ui_strikes.z_index = @ambulance_ui.z_index + 3
      @ambulance_ui_strikes.add("xxx", [0, 1, 2, 3], fps: 0)
      @ambulance_ui_strikes.play("xxx")

      # UI icon for cop
      @cop_ui = GSDL::Sprite.new("cop-ui", origin: {1_f32, 0_f32})
      @cop_ui.draw_relative_to_camera = false
      @cop_ui.x = Game.width - 8
      @cop_ui.y = @ambulance_ui.y + 8
      @cop_ui.z_index = 150

      # UI XXX for cop
      @cop_ui_strikes = GSDL::AnimatedSprite.new("cop-ui-strikes", 64, 32, origin: {1_f32, 0_f32})
      @cop_ui_strikes.draw_relative_to_camera = false
      @cop_ui_strikes.x = @cop_ui.x
      @cop_ui_strikes.y = @cop_ui.y
      @cop_ui_strikes.z_index = @cop_ui.z_index + 3
      @cop_ui_strikes.add("xxx", [0, 1, 2, 3], fps: 0)
      @cop_ui_strikes.play("xxx")

      self.pause_scene = PauseScene.new
      self.hud = hud
    end

    def update(dt : Float32)
      if GSDL::Input.action?(:menu)
        exit_with_transition
        return
      end

      update_spawner(dt)

      camera_update(dt)

      intersections_update(dt)

      @map.update(dt)

      # NOTE: target areas probably do not need to update, they are static
      # @target_areas.each(&.update(dt))

      vehicles_update(dt)

      # manually update HUD
      hud.try &.update(dt)
    end

    private def camera_update(dt : Float32)
      # Zoom in keyboard
      if GSDL::Input.action?(:zoom_in)
        zoom = camera.zoom + 1.0_f32 * dt
        zoom = CameraZoomInMax if zoom > 2_f32
        camera.zoom = zoom
      end

      # Zoom out keyboard
      if GSDL::Input.action?(:zoom_out)
        zoom = camera.zoom - 1.0_f32 * dt
        zoom = CameraZoomOutMax if zoom < CameraZoomOutMax
        camera.zoom = zoom
      end

      # Mouse wheel zoom
      wheel_y = GSDL::Mouse.wheel_y
      if wheel_y != 0
        zoom = camera.zoom + wheel_y * 0.1_f32
        zoom = CameraZoomInMax if zoom > CameraZoomInMax
        zoom = CameraZoomOutMax if zoom < CameraZoomOutMax
        camera.zoom = zoom
      end

      camera.update(dt)
    end

    private def vehicles_update(dt : Float32)
      @vehicles.each(&.update(dt, @map, @intersections, @vehicles))
      remove_vehicles_finished_or_target_reached()

      # Deselect if selected vehicle is gone or wrecked
      if selected = @selected_vehicle
        unless @vehicles.includes?(selected) && !selected.wrecked?
          @selected_vehicle = nil
        end
      end
    end

    private def intersections_update(dt : Float32)
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
    end

    private def remove_vehicles_finished_or_target_reached
      @vehicles.reject! do |vehicle|
        if vehicle.finished? || vehicle.off_screen?(@map.width, @map.height)
          if vehicle.is_a?(VehiclePriority) && (vehicle.finished? || vehicle.target_reached?)
            case vehicle.type
            when .ambulance?
              if vehicle.late_to_target?
                add_x_check_for_game_over("ambulances", @ambulance_ui_strikes)
                # xs = GSDL::Data.get("ambulances_x").as_i
                # xs += 1
                # xs = [xs, 3].min
                # GSDL::Data.set("ambulances_x", xs)
                # @ambulance_ui_strikes.as(GSDL::AnimatedSprite).frame_index = xs
              else
                GSDL::Data.increment("ambulances", 1)
              end
            when .police?
              if vehicle.late_to_target?
                add_x_check_for_game_over("police", @cop_ui_strikes)
                # xs = GSDL::Data.get("police_x").as_i
                # xs += 1
                # xs = [xs, 3].min
                # GSDL::Data.set("police_x", xs)
                # @cop_ui_strikes.as(GSDL::AnimatedSprite).frame_index = xs
              else
                GSDL::Data.increment("police", 1)
              end
            when .vip?
              if vehicle.late_to_target?
                GSDL::Data.increment("vips_x", 1)
              else
                GSDL::Data.increment("vips", 1)
              end
            end
          end

          true
        else
          false
        end
      end
    end

    def add_x_check_for_game_over(type : String, strikes : GSDL::AnimatedSprite)
      xs = GSDL::Data.get("#{type}_x").as_i
      xs += 1
      xs = [xs, 3].min
      GSDL::Data.set("#{type}_x", xs)
      # strikes.as(GSDL::AnimatedSprite).frame_index = xs
      strikes.frame_index = xs

      # game over check
      if xs >= 3
        # game over
        Game.paused = true
      end
    end

    private def update_spawner(dt : Float32)
      if @spawn_timer.done?
        spawn_vehicle
        @spawn_timer.duration = Random.rand(@spawn_interval_min..@spawn_interval_max).seconds
        @spawn_timer.restart
      end
    end

    private def spawn_vehicle
      is_priority = Random.rand < SpawnPriorityVehicleChance

      return if @spawn_points.empty?
      dir, sx, sy = @spawn_points.sample

      new_vehicle = if is_priority
                      # Randomly choose priority type (excluding VIP for now)
                      type = Random.rand < SpawnPriorityVehicleAmbulanceVsPoliceRatio ? PriorityType::Ambulance : PriorityType::Police
                      GSDL::AudioManager.get("siren").play
                      VehiclePriority.new(dir, sx, sy, type)
                    else
                      VehicleCivilian.new(dir, sx, sy)
                    end

      new_vehicle.select_target(@node_graph)
      new_vehicle.calculate_path(@node_graph)

      # Safety check: do not spawn if overlapping another vehicle
      if new_vehicle.target_node && @vehicles.none?(&.collides?(new_vehicle))
        # if new_vehicle.path.empty? && !new_vehicle.target_reached?
        #    puts "Vehicle spawned with no path and not at target! (Target: #{new_vehicle.target_node.try(&.type)})"
        # end
        @vehicles << new_vehicle
      # else
      #   puts "Vehicle failed to spawn: No target or collision detected. (Target: #{new_vehicle.target_node.try(&.type)})"
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

      draw_manual_hud_ui(draw)

      # manually draw HUD
      hud.try &.draw(draw)
    end

    def draw_manual_hud_ui(draw : GSDL::Draw)
      @ambulance_ui.draw(draw)
      @cop_ui.draw(draw)

      @ambulance_ui_strikes.draw(draw)
      @cop_ui_strikes.draw(draw)
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
