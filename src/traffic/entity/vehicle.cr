module Traffic
  enum IntersectionAction
    Straight
    Right
    Left
  end

  enum LaneState
    Stable
    Yielding
    Switching
  end

  abstract class Vehicle < GSDL::Sprite
    include GSDL::Collidable

    property speed : Float32
    property? waiting : Bool = false
    property? wrecked : Bool = false
    property path = Deque(IntersectionAction).new
    property next_action : IntersectionAction = IntersectionAction::Straight
    property lane_state : LaneState = LaneState::Stable

    @target_world_coord : Float32 = 0.0_f32
    @yield_timer : GSDL::Timer
    @blinker_timer : GSDL::Timer
    @blinker_on : Bool = false
    @original_speed : Float32
    @last_intersection : Intersection?
    @safety_timer : GSDL::Timer? = nil

    abstract def priority? : Bool
    abstract def skips_red_lights? : Bool
    abstract def base_speed_range : Range(Float32, Float32)
    abstract def update_special_behavior(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
    abstract def draw_status_overlay(draw : GSDL::Draw, th : Float32, cam_x : Float32, cam_y : Float32)
    abstract def tint_color : GSDL::Color

    def initialize(direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      @yield_timer = GSDL::Timer.new(5.seconds)
      @blinker_timer = GSDL::Timer.new(0.5.seconds)
      @blinker_timer.start

      @original_speed = Random.rand(base_speed_range)
      @speed = @original_speed

      self.direction = direction
      super(current_texture_key, x, y, origin: {0.5_f32, 0.5_f32})
      self.rotation = 0.0
    end

    def collision_bounding_box : GSDL::FRect
      GSDL::FRect.new(-width / 2.0_f32, -height / 2.0_f32, width, height)
    end

    def width : Float32
      GSDL::TextureManager.get(current_texture_key).size[0].to_f32
    end

    def height : Float32
      GSDL::TextureManager.get(current_texture_key).size[1].to_f32
    end

    private def current_texture_key : String
      case self.direction
      when .north? then "car-nb"
      when .south? then "car-sb"
      else "car-eb"
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
      else box
      end
    end

    def blind_spot_box(target_x : Float32, target_y : Float32, aggressive = false) : GSDL::FRect
      # Area in the target lane to check before merging
      look_dist = aggressive ? 0.0_f32 : 64.0_f32
      case self.direction
      when .east?  then GSDL::FRect.new(self.x - width, target_y - height/2, width + look_dist, height)
      when .west?  then GSDL::FRect.new(self.x - look_dist, target_y - height/2, width + look_dist, height)
      when .north? then GSDL::FRect.new(target_x - width/2, self.y - look_dist, width, height + look_dist)
      when .south? then GSDL::FRect.new(target_x - width/2, self.y - height, width, height + look_dist)
      else collision_box
      end
    end

    def calculate_path(intersections : Array(Intersection))
      @path.clear
      current_dir = self.direction
      current_x = self.x
      current_y = self.y
      will_turn_left = Random.rand < 0.2
      10.times do
        next_inter = intersections.select do |inter|
          ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
          case current_dir
          when .east?  then ix > current_x && (iy - current_y).abs < TileSize
          when .west?  then ix < current_x && (iy - current_y).abs < TileSize
          when .north? then iy < current_y && (ix - current_x).abs < TileSize
          when .south? then iy > current_y && (ix - current_x).abs < TileSize
          else false
          end
        end.min_by? do |inter|
          ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
          (ix - current_x).abs + (iy - current_y).abs
        end
        break unless next_inter
        roll = Random.rand
        if will_turn_left && roll < 0.4
          @path << IntersectionAction::Left; will_turn_left = false
          current_x, current_y = next_inter.tile_x * TileSize + TileSize, next_inter.tile_y * TileSize + TileSize
          current_dir = case current_dir
                        when .east?  then GSDL::Direction::North
                        when .west?  then GSDL::Direction::South
                        when .north? then GSDL::Direction::West
                        when .south? then GSDL::Direction::East
                        else current_dir
                        end
        elsif roll < 0.2
          @path << IntersectionAction::Right
          current_x, current_y = next_inter.tile_x * TileSize + TileSize, next_inter.tile_y * TileSize + TileSize
          current_dir = case current_dir
                        when .east?  then GSDL::Direction::South
                        when .west?  then GSDL::Direction::North
                        when .north? then GSDL::Direction::East
                        when .south? then GSDL::Direction::West
                        else current_dir
                        end
        else
          @path << IntersectionAction::Straight
          current_x, current_y = next_inter.tile_x * TileSize + TileSize, next_inter.tile_y * TileSize + TileSize
        end
      end
      @next_action = @path.shift? || IntersectionAction::Straight
    end

    def clicked?(mx : Float32, my : Float32) : Bool
      collision_box.overlaps?(GSDL::FRect.new(mx, my, 1, 1))
    end

    def project_path_segments(intersections : Array(Intersection)) : Array(GSDL::FRect)
      segments = [] of GSDL::FRect
      thickness = 8.0_f32
      cx, cy = self.x, self.y
      cdir = self.direction
      actions = [@next_action] + path.to_a
      actions.each do |action|
        next_inter = intersections.select do |inter|
          ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
          case cdir
          when .east?  then ix > cx && (iy - cy).abs < TileSize
          when .west?  then ix < cx && (iy - cy).abs < TileSize
          when .north? then iy < cy && (ix - cx).abs < TileSize
          when .south? then iy > cy && (ix - cx).abs < TileSize
          else false
          end
        end.min_by? do |inter|
          ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
          (ix - cx).abs + (iy - cy).abs
        end
        break unless next_inter
        inter_px, inter_py = next_inter.tile_x * TileSize, next_inter.tile_y * TileSize
        turn_x, turn_y = cx, cy
        if action.right? || action.left?
          case cdir
          when .east?  then turn_x = inter_px + (action.right? ? Lane1 : Lane3); cdir = action.right? ? GSDL::Direction::South : GSDL::Direction::North
          when .south? then turn_y = inter_py + (action.right? ? Lane1 : Lane3); cdir = action.right? ? GSDL::Direction::West : GSDL::Direction::East
          when .west?  then turn_x = inter_px + (action.right? ? Lane4 : Lane2); cdir = action.right? ? GSDL::Direction::North : GSDL::Direction::South
          when .north? then turn_y = inter_py + (action.right? ? Lane4 : Lane2); cdir = action.right? ? GSDL::Direction::East : GSDL::Direction::West
          end
        else
          case cdir
          when .east?, .west?  then turn_x = inter_px + TileSize
          when .north?, .south? then turn_y = inter_py + TileSize
          end
        end
        seg_x, seg_y = (cx < turn_x ? cx : turn_x) - (thickness / 2), (cy < turn_y ? cy : turn_y) - (thickness / 2)
        segments << GSDL::FRect.new(seg_x.to_f32, seg_y.to_f32, ((cx - turn_x).abs + thickness).to_f32, ((cy - turn_y).abs + thickness).to_f32)
        cx, cy = turn_x, turn_y
      end
      end_dist = 2000.0_f32
      final_x, final_y = cx, cy
      case cdir
      when .east?  then final_x += end_dist
      when .west?  then final_x -= end_dist
      when .north? then final_y -= end_dist
      when .south? then final_y += end_dist
      end
      seg_x, seg_y = (cx < final_x ? cx : final_x) - (thickness / 2), (cy < final_y ? cy : final_y) - (thickness / 2)
      segments << GSDL::FRect.new(seg_x.to_f32, seg_y.to_f32, ((cx - final_x).abs + thickness).to_f32, ((cy - final_y).abs + thickness).to_f32)
      segments
    end

    def update(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      if @blinker_timer.done?
        @blinker_on = !@blinker_on
        @blinker_timer.restart
      end

      update_special_behavior(dt, intersections, all_vehicles)

      return if @wrecked
      @waiting = false

      # Collision check
      unless @safety_timer.try(&.running?)
        all_vehicles.each do |other|
          next if other == self
          if self.collides?(other)
            @wrecked = true; other.wrecked = true; GSDL::AudioManager.get("crash").play; return
          end
        end
      end

      # Forward halting
      look_box = look_ahead_box
      all_vehicles.each do |other|
        next if other == self
        if look_box.overlaps?(other.collision_box)
          @waiting = true; break
        end
      end

      update_lane_switching(dt, intersections, all_vehicles) unless @waiting
      check_intersections(intersections) unless @waiting
      handle_turns(intersections, all_vehicles) unless @waiting

      unless @waiting
        target_speed = @next_action.straight? ? @original_speed : @original_speed * 0.5_f32
        if @speed < target_speed
          @speed += 400.0_f32 * dt; @speed = target_speed if @speed > target_speed
        elsif @speed > target_speed
          @speed -= 400.0_f32 * dt; @speed = target_speed if @speed < target_speed
        end

        dx, dy = 0.0_f32, 0.0_f32
        case self.direction
        when .east?  then dx = 1.0_f32
        when .west?  then dx = -1.0_f32
        when .north? then dy = -1.0_f32
        when .south? then dy = 1.0_f32
        else # ignore
        end

        # Orthogonal lane switching movement
        if @lane_state.switching?
          switch_speed = 150.0_f32 * dt
          case self.direction
          when .north?, .south?
            if (self.x - @target_world_coord).abs < switch_speed
              self.x = @target_world_coord; @lane_state = LaneState::Stable
            else
              self.x += (self.x < @target_world_coord ? switch_speed : -switch_speed)
            end
          when .east?, .west?
            if (self.y - @target_world_coord).abs < switch_speed
              self.y = @target_world_coord; @lane_state = LaneState::Stable
            else
              self.y += (self.y < @target_world_coord ? switch_speed : -switch_speed)
            end
          end
        end

        self.x += dx * @speed * dt
        self.y += dy * @speed * dt
      end
    end

    private def update_lane_switching(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      return if @lane_state.switching?

      # Find next intersection distance
      next_inter = intersections.select do |inter|
        ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
        case self.direction
        when .east?  then ix > self.x && (iy - self.y).abs < TileSize
        when .west?  then ix < self.x && (iy - self.y).abs < TileSize
        when .north? then iy < self.y && (ix - self.x).abs < TileSize
        when .south? then iy > self.y && (ix - self.x).abs < TileSize
        else false
        end
      end.min_by? do |inter|
        ix, iy = inter.tile_x * TileSize + TileSize, inter.tile_y * TileSize + TileSize
        (ix - self.x).abs + (iy - self.y).abs
      end

      return unless next_inter
      dist = case self.direction
             when .east?  then (next_inter.tile_x * TileSize) - self.x
             when .west?  then self.x - (next_inter.tile_x * TileSize + IntersectionSize)
             when .north? then self.y - (next_inter.tile_y * TileSize + IntersectionSize)
             when .south? then (next_inter.tile_y * TileSize) - self.y
             else 9999.0_f32
             end

      return if dist > SwitchZoneDist || dist < 0

      # Correct base_coord for the specific 2-tile roads in this map
      if self.direction.north? || self.direction.south?
        base_coord = 7.0_f32 * TileSize
        current_val = self.x
      else
        base_coord = 6.0_f32 * TileSize
        current_val = self.y
      end

      current_offset = current_val - base_coord

      # Required Offset
      req_offset = if @next_action.left?
                     (self.direction.north? || self.direction.east?) ? Lane3 : Lane2
                   else # Straight or Right
                     (self.direction.north? || self.direction.east?) ? Lane4 : Lane1
                   end

      if (current_offset - req_offset).abs > 5.0_f32
        # Need to switch
        target_world = base_coord + req_offset
        aggressive = priority?

        if @lane_state.yielding? || aggressive
          if !aggressive && @yield_timer.done?
            # Timeout: cancel turn and recalculate
            @next_action = IntersectionAction::Straight
            calculate_path(intersections)
            @lane_state = LaneState::Stable
          else
            # Check blind spot
            tx, ty = self.x, self.y
            if self.direction.north? || self.direction.south?
              tx = target_world
            else
              ty = target_world
            end
            unless all_vehicles.any? { |o| o != self && o.collision_box.overlaps?(blind_spot_box(tx.to_f32, ty.to_f32, aggressive)) }
              @target_world_coord = target_world; @lane_state = LaneState::Switching
            else
              @waiting = true # Stop and wait for gap
            end
          end
        else
          @lane_state = LaneState::Yielding
          @yield_timer.restart
          @waiting = true
        end
      else
        @lane_state = LaneState::Stable
      end
    end

    private def is_waiting_on_wreck?(all_vehicles : Array(Vehicle)) : Bool
      look_box = look_ahead_box
      all_vehicles.any? { |o| o != self && o.wrecked? && look_box.overlaps?(o.collision_box) }
    end

    private def handle_turns(intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      current_inter = intersections.find { |inter| inter.clicked?(self.x, self.y) }
      if current_inter
        if current_inter != @last_intersection
          @last_intersection = current_inter
          if @next_action.right? || @next_action.left?
            inter_px, inter_py = current_inter.tile_x * TileSize, current_inter.tile_y * TileSize
            can_turn, new_dir, new_x, new_y = false, self.direction, self.x, self.y
            threshold = ThresholdTurn

            if @next_action.right?
              case self.direction
              when .east?  then (can_turn = true; new_dir = GSDL::Direction::South; new_x = inter_px + Lane1) if (self.x - (inter_px + Lane1)).abs < threshold
              when .south? then (can_turn = true; new_dir = GSDL::Direction::West;  new_y = inter_py + Lane1) if (self.y - (inter_py + Lane1)).abs < threshold
              when .west?  then (can_turn = true; new_dir = GSDL::Direction::North; new_x = inter_px + Lane4) if (self.x - (inter_px + Lane4)).abs < threshold
              when .north? then (can_turn = true; new_dir = GSDL::Direction::East;  new_y = inter_py + Lane4) if (self.y - (inter_py + Lane4)).abs < threshold
              else # ignore
              end
            else # Left turn
              case self.direction
              when .east?  then (can_turn = true; new_dir = GSDL::Direction::North; new_x = inter_px + Lane3) if (self.x - (inter_px + Lane3)).abs < threshold
              when .south? then (can_turn = true; new_dir = GSDL::Direction::East;  new_y = inter_py + Lane3) if (self.y - (inter_py + Lane3)).abs < threshold
              when .west?  then (can_turn = true; new_dir = GSDL::Direction::South; new_x = inter_px + Lane2) if (self.x - (inter_px + Lane2)).abs < threshold
              when .north? then (can_turn = true; new_dir = GSDL::Direction::West;  new_y = inter_py + Lane2) if (self.y - (inter_py + Lane2)).abs < threshold
              else # ignore
              end
            end

            if can_turn
              old_dir, old_x, old_y = self.direction, self.x, self.y
              self.direction, self.x, self.y = new_dir, new_x, new_y
              if all_vehicles.any? { |o| o != self && (self.collides?(o) || o.look_ahead_box.overlaps?(self.collision_box)) }
                self.direction, self.x, self.y = old_dir, old_x, old_y
              else
                @next_action = path.shift? || IntersectionAction::Straight
                @safety_timer = GSDL::Timer.new(0.5.seconds); @safety_timer.try(&.start)
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
      is_committed = intersections.any? { |inter| inter.clicked?(self.x, self.y) }
      look_ahead = 16.0_f32
      check_x, check_y = self.x, self.y
      case self.direction
      when .east?  then check_x += (width / 2.0_f32) + look_ahead
      when .west?  then check_x -= (width / 2.0_f32) + look_ahead
      when .north? then check_y -= (height / 2.0_f32) + look_ahead
      when .south? then check_y += (height / 2.0_f32) + look_ahead
      else # ignore
      end

      intersections.each do |inter|
        if inter.clicked?(check_x, check_y)
          next if is_committed
          next if skips_red_lights?
          dist_to_line = case self.direction
                         when .east?  then (inter.tile_x * TileSize) - (self.x + width / 2.0_f32)
                         when .west?  then (self.x - width / 2.0_f32) - (inter.tile_x * TileSize + IntersectionSize)
                         when .north? then (self.y - height / 2.0_f32) - (inter.tile_y * TileSize + IntersectionSize)
                         when .south? then (inter.tile_y * TileSize) - (self.y + height / 2.0_f32)
                         else 0.0_f32
                         end
          case self.direction
          when .north?, .south?
            case inter.state
            when .green_ns?
              # Straight/Right go, Left waits
              @waiting = true if @next_action.left?
            when .yellow_ns?
              # Straight/Right might go if close, Left waits
              @waiting = true if @next_action.left? || dist_to_line > 32.0_f32
            when .green_ns_left?
              # Left goes, Straight/Right waits
              @waiting = true unless @next_action.left?
            when .yellow_ns_left?
              # Left might go if close, Straight/Right MUST wait
              @waiting = true if !@next_action.left? || dist_to_line > 32.0_f32
            else
              # AllRed or EW states
              @waiting = true
            end
          when .east?, .west?
            case inter.state
            when .green_ew?
              # Straight/Right go, Left waits
              @waiting = true if @next_action.left?
            when .yellow_ew?
              # Straight/Right might go if close, Left waits
              @waiting = true if @next_action.left? || dist_to_line > 32.0_f32
            when .green_ew_left?
              # Left goes, Straight/Right waits
              @waiting = true unless @next_action.left?
            when .yellow_ew_left?
              # Left might go if close, Straight/Right MUST wait
              @waiting = true if !@next_action.left? || dist_to_line > 32.0_f32
            else
              # AllRed or NS states
              @waiting = true
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
      tw, th = tex.size[0].to_f32, tex.size[1].to_f32
      tint_color = self.tint_color
      draw.texture(texture: tex, dest_rect: GSDL::FRect.new(x: self.x - (tw/2.0_f32) - cam_x, y: self.y - (th/2.0_f32) - cam_y, w: tw, h: th), flip: flip, tint: tint_color, z_index: z_index)

      # Blinkers
      if @blinker_on && (@next_action.left? || @next_action.right?)
        b_color = GSDL::Color.new(255, 165, 0)
        bx, by = self.x, self.y # Use world center directly

        # Determine triangle points based on world coords (Triangle class handles camera)
        case self.direction
        when .east?
          if @next_action.left? # Facing Up
            p1 = {bx, by - 16.0_f32}; p2 = {bx - 8.0_f32, by - 4.0_f32}; p3 = {bx + 8.0_f32, by - 4.0_f32}
          else # Right (Facing Down)
            p1 = {bx, by + 16.0_f32}; p2 = {bx - 8.0_f32, by + 4.0_f32}; p3 = {bx + 8.0_f32, by + 4.0_f32}
          end
        when .west?
          if @next_action.left? # Facing Down
            p1 = {bx, by + 16.0_f32}; p2 = {bx - 8.0_f32, by + 4.0_f32}; p3 = {bx + 8.0_f32, by + 4.0_f32}
          else # Right (Facing Up)
            p1 = {bx, by - 16.0_f32}; p2 = {bx - 8.0_f32, by - 4.0_f32}; p3 = {bx + 8.0_f32, by - 4.0_f32}
          end
        when .north?
          if @next_action.left? # Facing Left
            p1 = {bx - 16.0_f32, by}; p2 = {bx - 4.0_f32, by - 8.0_f32}; p3 = {bx - 4.0_f32, by + 8.0_f32}
          else # Right (Facing Right)
            p1 = {bx + 16.0_f32, by}; p2 = {bx + 4.0_f32, by - 8.0_f32}; p3 = {bx + 4.0_f32, by + 8.0_f32}
          end
        when .south?
          if @next_action.left? # Facing Right
            p1 = {bx + 16.0_f32, by}; p2 = {bx + 4.0_f32, by - 8.0_f32}; p3 = {bx + 4.0_f32, by + 8.0_f32}
          else # Right (Facing Left)
            p1 = {bx - 16.0_f32, by}; p2 = {bx - 4.0_f32, by - 8.0_f32}; p3 = {bx - 4.0_f32, by + 8.0_f32}
          end
        else # ignore
          p1 = p2 = p3 = {0.0_f32, 0.0_f32}
        end

        GSDL::Triangle.new(p1, p2, p3, color: b_color, z_index: z_index + 50).draw(draw)
      end

      draw_status_overlay(draw, th, cam_x, cam_y)
      draw.scale = {old_scale_x, old_scale_y}
    end
  end
end
