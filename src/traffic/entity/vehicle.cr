module Traffic
  enum VehicleType
    Civilian
    Priority
  end

  module PatienceThresholds
    ANXIOUS    = 5.0_f32
    FRUSTRATED = 20.0_f32
    ROAD_RAGE  = 35.0_f32
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
          ix = inter.tile_x * 128.0_f32 + 64.0_f32
          iy = inter.tile_y * 128.0_f32 + 64.0_f32
          case cdir
          when .east?  then ix > cx && (iy - cy).abs < 64
          when .west?  then ix < cx && (iy - cy).abs < 64
          when .north? then iy < cy && (ix - cx).abs < 64
          when .south? then iy > cy && (ix - cx).abs < 64
          else false
          end
        end.min_by? do |inter|
          ix = inter.tile_x * 128.0_f32 + 64.0_f32
          iy = inter.tile_y * 128.0_f32 + 64.0_f32
          (ix - cx).abs + (iy - cy).abs
        end

        break unless next_inter

        inter_px = next_inter.tile_x * 128.0_f32
        inter_py = next_inter.tile_y * 128.0_f32
        
        turn_x = cx
        turn_y = cy
        
        if action.right?
          case cdir
          when .east?
            turn_x = inter_px + 32.0_f32
            cdir = GSDL::Direction::South
          when .south?
            turn_y = inter_py + 32.0_f32
            cdir = GSDL::Direction::West
          when .west?
            turn_x = inter_px + 96.0_f32
            cdir = GSDL::Direction::North
          when .north?
            turn_y = inter_py + 96.0_f32
            cdir = GSDL::Direction::East
          end
        else
          turn_x = inter_px + 64.0_f32
          turn_y = inter_py + 64.0_f32
          case cdir
          when .east?, .west?  then turn_y = cy
          when .north?, .south? then turn_x = cx
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

      # Check for collisions with other vehicles (Wreck state)
      # Skip if in safety mode (just after a turn)
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
        # Intersection check (incorporating red lights into halting)
        check_intersections(intersections)
      end

      unless @waiting
        handle_turns(intersections, all_vehicles)
      end

      unless @waiting
        # Speed adjustment for preparing to turn
        target_speed = @next_action.straight? ? @original_speed : @original_speed * 0.5_f32

        # Smoothly interpolate speed
        if @speed < target_speed
          @speed += 400.0_f32 * dt
          @speed = target_speed if @speed > target_speed
        elsif @speed > target_speed
          @speed -= 400.0_f32 * dt
          @speed = target_speed if @speed < target_speed
        end

        # Basic movement
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

        # Audio triggers for state transitions
        if road_rage? && !@rage_cooldown.started?
          GSDL::AudioManager.get("rage_trigger").play
          @rage_cooldown.start
        end

        # Honking ONLY when frustrated (Orange)
        if frustrated? && @honk_timer.done?
            GSDL::AudioManager.get("honk").play
            @honk_timer.duration = Time::Span.new(seconds: Random.rand(4..8))
            @honk_timer.restart
        end
      else
        # Gradually calm down when moving
        if road_rage? && @rage_cooldown.running?
          # Do nothing, wait for cooldown
        else
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
      # Center point of the vehicle
      check_x = self.x + width / 2.0_f32
      check_y = self.y + height / 2.0_f32

      current_inter = intersections.find { |inter| inter.clicked?(check_x, check_y) }

      if current_inter
        if current_inter != @last_intersection
          @last_intersection = current_inter

          # Only proceed if we have an action to perform
          if @next_action.right?
            inter_px = current_inter.tile_x * 128.0_f32
            inter_py = current_inter.tile_y * 128.0_f32

            # Ideal turn coordinates for right-hand traffic
            # E->S: Turn at x=inter_px+16, y=inter_py+80
            # S->W: Turn at x=inter_px+16, y=inter_py+16
            # W->N: Turn at x=inter_px+80, y=inter_py+16
            # N->E: Turn at x=inter_px+80, y=inter_py+80

            can_turn = false
            new_dir = self.direction
            new_x = self.x
            new_y = self.y

            threshold = 24.0_f32 # Distance from ideal point to trigger turn

            case self.direction
            when .east?  # East -> South (Lane X=16)
              target_x = inter_px + 16.0_f32
              if (self.x - target_x).abs < threshold
                can_turn = true
                new_dir = GSDL::Direction::South
                new_x = target_x
              end
            when .south? # South -> West (Lane Y=16)
              target_y = inter_py + 16.0_f32
              if (self.y - target_y).abs < threshold
                can_turn = true
                new_dir = GSDL::Direction::West
                new_y = target_y
              end
            when .west?  # West -> North (Lane X=80)
              target_x = inter_px + 80.0_f32
              if (self.x - target_x).abs < threshold
                can_turn = true
                new_dir = GSDL::Direction::North
                new_x = target_x
              end
            when .north? # North -> East (Lane Y=80)
              target_y = inter_py + 80.0_f32
              if (self.y - target_y).abs < threshold
                can_turn = true
                new_dir = GSDL::Direction::East
                new_y = target_y
              end
            else # ignore others
            end

            if can_turn
              # Safety check: would we collide immediately if we turned?
              # Temporarily switch direction and check collisions
              old_dir = self.direction
              old_x = self.x
              old_y = self.y

              self.direction = new_dir
              self.x = new_x
              self.y = new_y

              # Check if new position overlaps any vehicle (including its look_ahead_box for lane integrity)
              collision = all_vehicles.any? do |other|
                next false if other == self
                self.collides?(other) || other.look_ahead_box.overlaps?(self.collision_box)
              end

              if collision
                # Revert turn if it would cause immediate collision
                self.direction = old_dir
                self.x = old_x
                self.y = old_y
                # Keep @last_intersection so we don't try again for THIS intersection
              else
                # Success!
                @next_action = path.shift? || IntersectionAction::Straight
                @safety_timer = GSDL::Timer.new(0.5.seconds)
                @safety_timer.try(&.start)
              end
            else
                # Didn't reach turn point yet, reset last_intersection so we check again next frame
                @last_intersection = nil
            end
          elsif @next_action.straight?
            # We already reached the intersection, we are going straight.
            # Pop the next action for the NEXT intersection.
            @next_action = path.shift? || IntersectionAction::Straight
          end
        end
      else
        @last_intersection = nil
      end
    end

    private def check_intersections(intersections)
      # Detection box in front of the vehicle
      look_ahead = 40.0_f32

      check_x = self.x + width / 2.0_f32
      check_y = self.y + height / 2.0_f32

      # Check if already inside an intersection
      is_inside_intersection = intersections.any? { |inter| inter.clicked?(check_x, check_y) }

      case self.direction
      when .east?  then check_x += look_ahead
      when .west?  then check_x -= look_ahead
      when .north? then check_y -= look_ahead
      when .south? then check_y += look_ahead
      else # ignore others
      end

      intersections.each do |inter|
        if inter.clicked?(check_x, check_y)
          # If already inside, don't stop
          next if is_inside_intersection

          # Priority and Road Rage vehicles ignore signals
          next if road_rage? || @vehicle_type == VehicleType::Priority

          case self.direction
          when .north?, .south?
            # Vertical traffic: stop if signal is GreenEW or YellowEW (meaning RedNS)
            if inter.state == IntersectionSignal::GreenEW || inter.state == IntersectionSignal::YellowEW
              @waiting = true
              return
            end
          when .east?, .west?
            # Horizontal traffic: stop if signal is GreenNS or YellowNS (meaning RedEW)
            if inter.state == IntersectionSignal::GreenNS || inter.state == IntersectionSignal::YellowNS
              @waiting = true
              return
            end
          else # ignore others
          end
        end
      end
    end

    def off_screen?
      self.x < -200 || self.x > 2760 || self.y < -200 || self.y > 1600
    end

    def draw(draw : GSDL::Draw)
      old_scale_x = draw.current_scale_x
      old_scale_y = draw.current_scale_y

      draw.scale = GSDL::Game.camera.zoom

      cam_x = GSDL::Game.camera.x
      cam_y = GSDL::Game.camera.y

      flip = self.direction.west? ? GSDL::TileMap::Flip::Horizontal : GSDL::TileMap::Flip::None

      # Draw using directional texture and its actual size
      tex = GSDL::TextureManager.get(current_texture_key)
      tex_size = tex.size

      tint_color = if @wrecked
                     GSDL::Color.new(40, 40, 40, 255)
                   elsif @vehicle_type == VehicleType::Priority
                     GSDL::Color.new(0, 0, 255, 224)
                   else
                     GSDL::Color::White
                   end

      draw.texture(
        texture: tex,
        dest_rect: GSDL::FRect.new(x: self.x - cam_x, y: self.y - cam_y, w: tex_size[0], h: tex_size[1]),
        flip: flip,
        tint: tint_color,
        z_index: z_index
      )

      # Draw frustration bar above the vehicle
      unless @wrecked || patient?
        bar_w = 40.0_f32
        bar_h = 6.0_f32
        bar_x = self.x - cam_x + (tex_size[0] / 2.0_f32) - (bar_w / 2.0_f32)
        bar_y = self.y - cam_y - 12.0_f32

        # Background
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w, bar_h), GSDL::Color.new(30, 30, 30, 150), z_index + 1)

        # Foreground
        percent = Math.min(1.0_f32, @frustration / PatienceThresholds::ROAD_RAGE)
        color = if road_rage?
                  GSDL::Color.new(255, 50, 50, 255) # Red
                elsif frustrated?
                  GSDL::Color.new(255, 120, 50, 255) # Orange
                elsif anxious?
                  GSDL::Color.new(255, 255, 50, 255) # Yellow
                else
                  GSDL::Color.new(100, 255, 100, 255) # Green
                end
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w * percent, bar_h), color, z_index + 2)

        # Exclamation mark for Road Rage
        if road_rage?
          # Just a small red box or something as placeholder for "icon"
          draw.rect_fill(GSDL::FRect.new(bar_x + bar_w + 4, bar_y - 4, 8, 14), GSDL::Color.new(255, 0, 0, 255), z_index + 3)
        end
      end

      draw.scale = {old_scale_x, old_scale_y}
    end
  end
end
