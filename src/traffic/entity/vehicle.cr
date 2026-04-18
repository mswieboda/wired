module Traffic
  enum VehicleType
    Civilian
    Priority
  end

  enum IntersectionAction
    Straight
    Right
    Left
  end

  class Vehicle < GSDL::Sprite
    include GSDL::Collidable

    property vehicle_type : VehicleType
    property speed : Float32
    property? waiting : Bool = false
    property? wrecked : Bool = false
    property time_to_destination : Float32 = 0.0_f32
    property frustration : Float32 = 0.0_f32
    property path = Deque(IntersectionAction).new
    property next_action : IntersectionAction = IntersectionAction::Straight

    @original_speed : Float32
    @honk_timer : GSDL::Timer
    @rage_cooldown : GSDL::Timer
    @last_intersection : Intersection?
    @safety_timer : GSDL::Timer? = nil

    def patient?    ; @frustration < PatienceThresholds::ANXIOUS; end
    def anxious?    ; @frustration >= PatienceThresholds::ANXIOUS && @frustration < PatienceThresholds::FRUSTRATED; end
    def frustrated? ; @frustration >= PatienceThresholds::FRUSTRATED && @frustration < PatienceThresholds::ROAD_RAGE; end
    def road_rage?  ; @frustration >= PatienceThresholds::ROAD_RAGE; end

    def initialize(@vehicle_type : VehicleType, direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      @honk_timer = GSDL::Timer.new(Time::Span.new(seconds: Random.rand(4..8)))
      @honk_timer.start
      @rage_cooldown = GSDL::Timer.new(2.seconds)

      @original_speed = case @vehicle_type
                        when VehicleType::Priority
                          @time_to_destination = 60.0_f32
                          Random.rand(400.0_f32..550.0_f32)
                        else
                          Random.rand(200.0_f32..350.0_f32)
                        end
      @speed = @original_speed

      self.direction = direction
      super(current_texture_key, x, y)

      # No rotation needed anymore as we use directional assets
      self.rotation = 0.0
    end

    def collision_bounding_box : GSDL::FRect
      # Use intrinsic texture size without transformation
      GSDL::FRect.new(0, 0, width, height)
    end

    def width : Float32
      tex_size = GSDL::TextureManager.get(current_texture_key).size
      tex_size[0]
    end

    def height : Float32
      tex_size = GSDL::TextureManager.get(current_texture_key).size
      tex_size[1]
    end

    private def current_texture_key : String
      case self.direction
      when .north? then "car_north"
      when .south? then "car_south"
      else "car_east"
      end
    end

    def look_ahead_box : GSDL::FRect
      box = collision_box
      look_dist = 24.0_f32

      case self.direction
      when .east?  then GSDL::FRect.new(box.right, box.y, look_dist, box.h)
      when .west?  then GSDL::FRect.new(box.left - look_dist, box.y, look_dist, box.h)
      when .north? then GSDL::FRect.new(box.x, box.y - look_dist, box.w, look_dist)
      when .south? then GSDL::FRect.new(box.x, box.bottom, box.w, look_dist)
      else box # fallback
      end
    end

    def clicked?(mx : Float32, my : Float32) : Bool
      box = collision_box
      mx >= box.x && mx < box.x + box.w && my >= box.y && my < box.y + box.h
    end

    def project_path_segments(intersections : Array(Intersection)) : Array(GSDL::FRect)
      segments = [] of GSDL::FRect
      thickness = 8.0_f32
      
      cx = self.x + width / 2.0_f32
      cy = self.y + height / 2.0_f32
      
      cdir = self.direction
      actions = [@next_action] + path.to_a

      actions.each do |action|
        next_inter = intersections.select do |inter|
          ix = inter.tile_x * TileSize + TileSize
          iy = inter.tile_y * TileSize + TileSize
          case cdir
          when .east?  then ix > cx && (iy - cy).abs < TileSize
          when .west?  then ix < cx && (iy - cy).abs < TileSize
          when .north? then iy < cy && (ix - cx).abs < TileSize
          when .south? then iy > cy && (ix - cx).abs < TileSize
          else false
          end
        end.min_by? do |inter|
          ix = inter.tile_x * TileSize + TileSize
          iy = inter.tile_y * TileSize + TileSize
          (ix - cx).abs + (iy - cy).abs
        end

        break unless next_inter

        inter_px = next_inter.tile_x * TileSize
        inter_py = next_inter.tile_y * TileSize
        
        turn_x = cx
        turn_y = cy
        
        if action.right? || action.left?
          case cdir
          when .east?
            turn_x = inter_px + (action.right? ? Lane4 : Lane1)
            cdir = action.right? ? GSDL::Direction::South : GSDL::Direction::North
          when .south?
            turn_y = inter_py + (action.right? ? Lane1 : Lane4)
            cdir = action.right? ? GSDL::Direction::West : GSDL::Direction::East
          when .west?
            turn_x = inter_px + (action.right? ? Lane1 : Lane4)
            cdir = action.right? ? GSDL::Direction::North : GSDL::Direction::South
          when .north?
            turn_y = inter_py + (action.right? ? Lane4 : Lane1)
            cdir = action.right? ? GSDL::Direction::East : GSDL::Direction::West
          end
        else
          case cdir
          when .east?, .west?  then turn_x = inter_px + TileSize
          when .north?, .south? then turn_y = inter_py + TileSize
          end
        end

        seg_x = (cx < turn_x ? cx : turn_x).to_f32 - (thickness / 2.0_f32)
        seg_y = (cy < turn_y ? cy : turn_y).to_f32 - (thickness / 2.0_f32)
        seg_w = (cx - turn_x).abs.to_f32 + thickness
        seg_h = (cy - turn_y).abs.to_f32 + thickness
        
        segments << GSDL::FRect.new(seg_x, seg_y, seg_w, seg_h)
        
        cx = turn_x
        cy = turn_y
      end
      
      end_dist = 2000.0_f32
      final_x = cx
      final_y = cy
      case cdir
      when .east?  then final_x += end_dist
      when .west?  then final_x -= end_dist
      when .north? then final_y -= end_dist
      when .south? then final_y += end_dist
      end
      
      seg_x = (cx < final_x ? cx : final_x).to_f32 - (thickness / 2.0_f32)
      seg_y = (cy < final_y ? cy : final_y).to_f32 - (thickness / 2.0_f32)
      seg_w = (cx - final_x).abs.to_f32 + thickness
      seg_h = (cy - final_y).abs.to_f32 + thickness
      segments << GSDL::FRect.new(seg_x, seg_y, seg_w, seg_h)

      segments
    end

    def update(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      if @vehicle_type == VehicleType::Priority
        decay_rate = 1.0_f32
        if @waiting
          if is_waiting_on_wreck?(all_vehicles)
            decay_rate = 10.0_f32
          else
            decay_rate = 3.0_f32
          end
        end
        @time_to_destination -= dt * decay_rate
        @time_to_destination = 0.0_f32 if @time_to_destination < 0
      end

      return if @wrecked

      update_frustration(dt) unless @vehicle_type == VehicleType::Priority

      @waiting = false

      # Check for collisions with other vehicles
      unless @safety_timer.try(&.running?)
        all_vehicles.each do |other|
          next if other == self
          if self.collides?(other)
            @wrecked = true
            other.wrecked = true
            GSDL::AudioManager.get("crash").play
            return
          end
        end
      end

      # Lane-halting logic: look ahead
      look_box = look_ahead_box
      all_vehicles.each do |other|
        next if other == self
        if look_box.overlaps?(other.collision_box)
          @waiting = true
          break
        end
      end

      unless @waiting
        check_intersections(intersections)
      end

      unless @waiting
        handle_turns(intersections, all_vehicles)
      end

      unless @waiting
        target_speed = @next_action.straight? ? @original_speed : @original_speed * 0.5_f32
        if @speed < target_speed
          @speed += 400.0_f32 * dt
          @speed = target_speed if @speed > target_speed
        elsif @speed > target_speed
          @speed -= 400.0_f32 * dt
          @speed = target_speed if @speed < target_speed
        end

        dx = 0.0_f32
        dy = 0.0_f32
        case self.direction
        when .east?  then dx = 1.0_f32
        when .west?  then dx = -1.0_f32
        when .north? then dy = -1.0_f32
        when .south? then dy = 1.0_f32
        else # ignore others
        end

        self.x += dx * @speed * dt
        self.y += dy * @speed * dt
      end
    end

    private def update_frustration(dt : Float32)
      if @waiting
        @frustration += dt * 2.0
        if road_rage? && !@rage_cooldown.started?
          GSDL::AudioManager.get("rage_trigger").play
          @rage_cooldown.start
        end
        if frustrated? && @honk_timer.done?
            GSDL::AudioManager.get("honk").play
            @honk_timer.duration = Time::Span.new(seconds: Random.rand(4..8))
            @honk_timer.restart
        end
      else
        unless road_rage? && @rage_cooldown.running?
          @frustration -= dt * 8.0
          @frustration = 0.0 if @frustration < 0
        end
      end
    end

    private def is_waiting_on_wreck?(all_vehicles : Array(Vehicle)) : Bool
      look_box = look_ahead_box
      all_vehicles.any? do |other|
        next false if other == self
        other.wrecked? && look_box.overlaps?(other.collision_box)
      end
    end

    private def handle_turns(intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      check_x = self.x + width / 2.0_f32
      check_y = self.y + height / 2.0_f32

      current_inter = intersections.find { |inter| inter.clicked?(check_x, check_y) }

      if current_inter
        if current_inter != @last_intersection
          @last_intersection = current_inter

          if @next_action.right? || @next_action.left?
            inter_px = current_inter.tile_x * TileSize
            inter_py = current_inter.tile_y * TileSize

            can_turn = false
            new_dir = self.direction
            new_x = self.x
            new_y = self.y
            threshold = ThresholdTurn

            if @next_action.right?
              case self.direction
              when .east? 
                target_x = inter_px + Lane4
                if (self.x - target_x).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::South; new_x = target_x
                end
              when .south?
                target_y = inter_py + Lane1
                if (self.y - target_y).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::West; new_y = target_y
                end
              when .west?
                target_x = inter_px + Lane1
                if (self.x - target_x).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::North; new_x = target_x
                end
              when .north?
                target_y = inter_py + Lane4
                if (self.y - target_y).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::East; new_y = target_y
                end
              else # ignore
              end
            else # Left turn
              case self.direction
              when .east?
                target_x = inter_px + Lane1
                if (self.x - target_x).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::North; new_x = target_x
                end
              when .south?
                target_y = inter_py + Lane4
                if (self.y - target_y).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::East; new_y = target_y
                end
              when .west?
                target_x = inter_px + Lane4
                if (self.x - target_x).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::South; new_x = target_x
                end
              when .north?
                target_y = inter_py + Lane1
                if (self.y - target_y).abs < threshold
                  can_turn = true; new_dir = GSDL::Direction::West; new_y = target_y
                end
              else # ignore
              end
            end

            if can_turn
              old_dir, old_x, old_y = self.direction, self.x, self.y
              self.direction, self.x, self.y = new_dir, new_x, new_y
              collision = all_vehicles.any? { |o| o != self && (self.collides?(o) || o.look_ahead_box.overlaps?(self.collision_box)) }
              if collision
                self.direction, self.x, self.y = old_dir, old_x, old_y
              else
                @next_action = path.shift? || IntersectionAction::Straight
                @safety_timer = GSDL::Timer.new(0.5.seconds)
                @safety_timer.try(&.start)
              end
            else
                @last_intersection = nil
            end
          elsif @next_action.straight?
            @next_action = path.shift? || IntersectionAction::Straight
          end
        end
      else
        @last_intersection = nil
      end
    end

    private def check_intersections(intersections)
      look_ahead = 40.0_f32
      check_x = self.x + width / 2.0_f32
      check_y = self.y + height / 2.0_f32
      is_inside_intersection = intersections.any? { |inter| inter.clicked?(check_x, check_y) }

      case self.direction
      when .east?  then check_x += look_ahead
      when .west?  then check_x -= look_ahead
      when .north? then check_y -= look_ahead
      when .south? then check_y += look_ahead
      else # ignore
      end

      intersections.each do |inter|
        if inter.clicked?(check_x, check_y)
          next if is_inside_intersection
          next if road_rage? || @vehicle_type == VehicleType::Priority
          case self.direction
          when .north?, .south?
            case inter.state
            when .green_ew?, .green_ew_left?, .yellow_ew? then @waiting = true; return
            when .green_ns? then ( @waiting = true; return ) if @next_action.left?
            when .green_ns_left? then ( @waiting = true; return ) unless @next_action.left?
            when .yellow_ns? then @waiting = true; return
            end
          when .east?, .west?
            case inter.state
            when .green_ns?, .green_ns_left?, .yellow_ns? then @waiting = true; return
            when .green_ew? then ( @waiting = true; return ) if @next_action.left?
            when .green_ew_left? then ( @waiting = true; return ) unless @next_action.left?
            when .yellow_ew? then @waiting = true; return
            end
          else # ignore
          end
        end
      end
    end

    def off_screen?
      self.x < -IntersectionSize || self.x > (14 * TileSize + IntersectionSize) || self.y < -IntersectionSize || self.y > (13 * TileSize + IntersectionSize)
    end

    def draw(draw : GSDL::Draw)
      old_scale_x, old_scale_y = draw.current_scale_x, draw.current_scale_y
      draw.scale = GSDL::Game.camera.zoom
      cam_x, cam_y = GSDL::Game.camera.x, GSDL::Game.camera.y
      flip = self.direction.west? ? GSDL::TileMap::Flip::Horizontal : GSDL::TileMap::Flip::None
      tex = GSDL::TextureManager.get(current_texture_key)
      tex_size = tex.size
      tint_color = @wrecked ? GSDL::Color.new(40, 40, 40) : (@vehicle_type == VehicleType::Priority ? GSDL::Color.new(0, 0, 255, 224) : GSDL::Color::White)

      draw.texture(
        texture: tex,
        dest_rect: GSDL::FRect.new(x: self.x - cam_x, y: self.y - cam_y, w: tex_size[0], h: tex_size[1]),
        flip: flip,
        tint: tint_color,
        z_index: z_index
      )

      unless @wrecked || patient?
        bar_w, bar_h = 40.0_f32, 6.0_f32
        bar_x = self.x - cam_x + (tex_size[0] / 2.0_f32) - (bar_w / 2.0_f32)
        bar_y = self.y - cam_y - 12.0_f32
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w, bar_h), GSDL::Color.new(30, 30, 30, 150), z_index + 1)
        percent = Math.min(1.0_f32, @frustration / PatienceThresholds::ROAD_RAGE)
        color = road_rage? ? GSDL::Color.new(255, 50, 50) : (frustrated? ? GSDL::Color.new(255, 120, 50) : (anxious? ? GSDL::Color.new(255, 255, 50) : GSDL::Color.new(100, 255, 100)))
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w * percent, bar_h), color, z_index + 2)
        draw.rect_fill(GSDL::FRect.new(bar_x + bar_w + 4, bar_y - 4, 8, 14), GSDL::Color.new(255, 0, 0), z_index + 3) if road_rage?
      end
      draw.scale = {old_scale_x, old_scale_y}
    end
  end
end
