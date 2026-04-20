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

  abstract class Vehicle < GSDL::Entity
    include GSDL::Collidable
    include GSDL::Area

    property speed : Float32
    property paint_color : GSDL::Color = GSDL::Color::White
    property? waiting : Bool = false
    property? wrecked : Bool = false
    property path = Deque(IntersectionAction).new
    property next_action : IntersectionAction = IntersectionAction::Straight
    property lane_state : LaneState = LaneState::Stable
    property target_node : Node? = nil
    property node_path = Array(Node).new
    property? finished : Bool = false

    abstract def select_target(graph : NodeGraph)
    abstract def has_top? : Bool
    abstract def has_sirens? : Bool
    abstract def tint_body? : Bool

    @target_world_coord : Float32 = 0.0_f32
    @yield_timer : GSDL::Timer
    @target_wait_timer : GSDL::Timer = GSDL::Timer.new(3.seconds)
    @blinker_timer : GSDL::Timer
    @blinker_on : Bool = false
    @original_speed : Float32
    @last_intersection : Intersection?
    @safety_timer : GSDL::Timer? = nil

    @direction : GSDL::Direction = GSDL::Direction::East
    @hovered : Bool = false

    @sprite_eb_body : GSDL::Sprite
    @sprite_wb_body : GSDL::Sprite
    @sprite_nb_body : GSDL::Sprite
    @sprite_sb_body : GSDL::Sprite

    @sprite_eb_top : GSDL::AnimatedSprite? = nil
    @sprite_wb_top : GSDL::AnimatedSprite? = nil
    @sprite_nb_top : GSDL::AnimatedSprite? = nil
    @sprite_sb_top : GSDL::AnimatedSprite? = nil

    @sprite_eb_sirens : GSDL::AnimatedSprite? = nil
    @sprite_wb_sirens : GSDL::AnimatedSprite? = nil
    @sprite_nb_sirens : GSDL::AnimatedSprite? = nil
    @sprite_sb_sirens : GSDL::AnimatedSprite? = nil

    @active_sprite_body : GSDL::Sprite
    @active_sprite_top : GSDL::AnimatedSprite? = nil
    @active_sprite_sirens : GSDL::AnimatedSprite? = nil

    abstract def priority? : Bool
    abstract def skips_red_lights? : Bool
    abstract def base_speed_range : Range(Float32, Float32)
    abstract def asset_prefix : String

    def h_dims : Tuple(Int32, Int32)
      {64, 32}
    end

    def v_dims : Tuple(Int32, Int32)
      {32, 48}
    end

    abstract def update_special_behavior(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
    abstract def draw_status_overlay(draw : GSDL::Draw, th : Float32, cam_x : Float32, cam_y : Float32)

    def setup_top_animations(sprite : GSDL::AnimatedSprite, kind : Symbol)
      # Override in subclasses
    end

    def setup_siren_animations(sprite : GSDL::AnimatedSprite, kind : Symbol)
      # Override in subclasses
    end

    def initialize(@direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      @x = x.to_f32
      @y = y.to_f32
      @origin = {0.5_f32, 0.5_f32}

      @yield_timer = GSDL::Timer.new(5.seconds)
      @blinker_timer = GSDL::Timer.new(0.5.seconds)
      @blinker_timer.start

      @original_speed = Random.rand(base_speed_range)
      @speed = @original_speed

      # 1. Create sprites
      hw, hh = h_dims
      vw, vh = v_dims

      @sprite_eb_body = GSDL::Sprite.new("#{asset_prefix}-eb-body", origin: {0.5_f32, 0.5_f32})
      @sprite_wb_body = GSDL::Sprite.new("#{asset_prefix}-eb-body", origin: {0.5_f32, 0.5_f32})
      @sprite_wb_body.flip_h = true
      @sprite_nb_body = GSDL::Sprite.new("#{asset_prefix}-nb-body", origin: {0.5_f32, 0.5_f32})
      @sprite_sb_body = GSDL::Sprite.new("#{asset_prefix}-sb-body", origin: {0.5_f32, 0.5_f32})

      if has_top?
        @sprite_eb_top = GSDL::AnimatedSprite.new("#{asset_prefix}-eb-top", hw, hh, origin: {0.5_f32, 0.5_f32})
        @sprite_wb_top = GSDL::AnimatedSprite.new("#{asset_prefix}-eb-top", hw, hh, origin: {0.5_f32, 0.5_f32})
        @sprite_wb_top.as(GSDL::AnimatedSprite).flip_h = true
        @sprite_nb_top = GSDL::AnimatedSprite.new("#{asset_prefix}-nb-top", vw, vh, origin: {0.5_f32, 0.5_f32})
        @sprite_sb_top = GSDL::AnimatedSprite.new("#{asset_prefix}-sb-top", vw, vh, origin: {0.5_f32, 0.5_f32})

        setup_top_animations(@sprite_eb_top.as(GSDL::AnimatedSprite), :eb)
        setup_top_animations(@sprite_wb_top.as(GSDL::AnimatedSprite), :wb)
        setup_top_animations(@sprite_nb_top.as(GSDL::AnimatedSprite), :nb)
        setup_top_animations(@sprite_sb_top.as(GSDL::AnimatedSprite), :sb)
      end

      if has_sirens?
        @sprite_eb_sirens = GSDL::AnimatedSprite.new("#{asset_prefix}-eb-sirens", hw, hh, origin: {0.5_f32, 0.5_f32})
        @sprite_wb_sirens = GSDL::AnimatedSprite.new("#{asset_prefix}-eb-sirens", hw, hh, origin: {0.5_f32, 0.5_f32})
        @sprite_wb_sirens.as(GSDL::AnimatedSprite).flip_h = true
        @sprite_nb_sirens = GSDL::AnimatedSprite.new("#{asset_prefix}-nb-sirens", vw, vh, origin: {0.5_f32, 0.5_f32})
        @sprite_sb_sirens = GSDL::AnimatedSprite.new("#{asset_prefix}-sb-sirens", vw, vh, origin: {0.5_f32, 0.5_f32})

        setup_siren_animations(@sprite_eb_sirens.as(GSDL::AnimatedSprite), :eb)
        setup_siren_animations(@sprite_wb_sirens.as(GSDL::AnimatedSprite), :wb)
        setup_siren_animations(@sprite_nb_sirens.as(GSDL::AnimatedSprite), :nb)
        setup_siren_animations(@sprite_sb_sirens.as(GSDL::AnimatedSprite), :sb)
      end

      # 2. Set active sprites immediately
      @active_sprite_body, @active_sprite_top, @active_sprite_sirens = case @direction
                       when .east?  then {@sprite_eb_body, @sprite_eb_top, @sprite_eb_sirens}
                       when .west?  then {@sprite_wb_body, @sprite_wb_top, @sprite_wb_sirens}
                       when .north? then {@sprite_nb_body, @sprite_nb_top, @sprite_nb_sirens}
                       when .south? then {@sprite_sb_body, @sprite_sb_top, @sprite_sb_sirens}
                       else {@sprite_eb_body, @sprite_eb_top, @sprite_eb_sirens}
                       end

      # 3. Safe to use self/methods now
      [
        {@sprite_eb_body, @sprite_eb_top, @sprite_eb_sirens},
        {@sprite_wb_body, @sprite_wb_top, @sprite_wb_sirens},
        {@sprite_nb_body, @sprite_nb_top, @sprite_nb_sirens},
        {@sprite_sb_body, @sprite_sb_top, @sprite_sb_sirens}
      ].each do |body, top, sirens|
        add_child(body)
        top.try { |t| add_child(t) }
        sirens.try { |s| add_child(s) }
      end

      update_active_visibility
    end

    def direction
      @direction
    end

    def direction=(dir : GSDL::Direction)
      return if @direction == dir
      @direction = dir
      @active_sprite_body, @active_sprite_top, @active_sprite_sirens = select_sprites_for_dir(dir)
      update_active_visibility
    end

    private def select_sprites_for_dir(dir) : Tuple(GSDL::Sprite, GSDL::AnimatedSprite?, GSDL::AnimatedSprite?)
      case dir
      when .east?  then {@sprite_eb_body, @sprite_eb_top, @sprite_eb_sirens}
      when .west?  then {@sprite_wb_body, @sprite_wb_top, @sprite_wb_sirens}
      when .north? then {@sprite_nb_body, @sprite_nb_top, @sprite_nb_sirens}
      when .south? then {@sprite_sb_body, @sprite_sb_top, @sprite_sb_sirens}
      else {@sprite_eb_body, @sprite_eb_top, @sprite_eb_sirens}
      end
    end

    private def update_active_visibility
      [@sprite_eb_body, @sprite_wb_body, @sprite_nb_body, @sprite_sb_body].each do |s|
        s.visible = s.active = (s == @active_sprite_body)
      end

      [
        @sprite_eb_top, @sprite_wb_top, @sprite_nb_top, @sprite_sb_top
      ].each do |s|
        s.try do |sprite|
          sprite.visible = sprite.active = (sprite == @active_sprite_top)
        end
      end

      [
        @sprite_eb_sirens, @sprite_wb_sirens, @sprite_nb_sirens, @sprite_sb_sirens
      ].each do |s|
        s.try do |sprite|
          sprite.visible = sprite.active = (sprite == @active_sprite_sirens)
        end
      end
    end

    def width
      @active_sprite_body.draw_width
    end

    def height
      @active_sprite_body.draw_height
    end

    def draw_x : GSDL::Num
      scene_x - (width * origin_x)
    end

    def draw_y : GSDL::Num
      scene_y - (height * origin_y)
    end

    def collision_bounding_box : GSDL::FRect
      # Collision box relative to Entity position (0,0)
      GSDL::FRect.new(-width / 2.0_f32, -height / 2.0_f32, width.to_f32, height.to_f32)
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

    def calculate_path(graph : NodeGraph)
      @path.clear
      @node_path.clear
      return unless target = @target_node

      # 1. Find the nearest node in front of us to start the path
      start_node = graph.nodes.select do |node|
        case self.direction
        when .east?  then node.x > self.x && (node.y - self.y).abs < TileSize
        when .west?  then node.x < self.x && (node.y - self.y).abs < TileSize
        when .north? then node.y < self.y && (node.x - self.x).abs < TileSize
        when .south? then node.y > self.y && (node.x - self.x).abs < TileSize
        else false
        end
      end.min_by? { |node| node.distance_to(self.x.to_f32, self.y.to_f32) }

      unless start_node
        if priority?
          puts "Priority #{asset_prefix} failed to find start node! (Pos: #{x},#{y} Dir: #{direction})"
        end
        return
      end

      # 2. Find path to target
      @node_path = Pathfinder.find_path(start_node, target)
      
      if @node_path.empty?
        if priority?
          puts "Priority #{asset_prefix} failed to find path to #{target.type}! (Start: #{start_node.type} at #{start_node.x},#{start_node.y})"
        end
        return
      end

      # 3. Convert node sequence to IntersectionActions
      # Logic: For every Intersection node 'N' at index 'i', we need to know how to get
      # from Node[i-1] to Node[i+1] via Node[i].
      
      # Determine initial direction from current pos to start_node
      current_dir = if (start_node.x - self.x).abs < (start_node.y - self.y).abs
                      start_node.y > self.y ? GSDL::Direction::South : GSDL::Direction::North
                    else
                      start_node.x > self.x ? GSDL::Direction::East : GSDL::Direction::West
                    end

      action_logs = [] of String

      (0...@node_path.size).each do |i|
        node = @node_path[i]
        
        # We only need steering actions for Intersections
        if node.type.intersection?
          # To determine the turn, we need the direction we entered from
          # and the direction we need to exit to.
          
          # 1. Entrance direction
          entrance_dir = if i == 0
                           current_dir
                         else
                           prev = @node_path[i-1]
                           if (node.x - prev.x).abs < (node.y - prev.y).abs
                             node.y > prev.y ? GSDL::Direction::South : GSDL::Direction::North
                           else
                             node.x > prev.x ? GSDL::Direction::East : GSDL::Direction::West
                           end
                         end
          
          # 2. Exit direction (to reach next node)
          if i < @node_path.size - 1
            nxt = @node_path[i+1]
            exit_dir = if (nxt.x - node.x).abs < (nxt.y - node.y).abs
                         nxt.y > node.y ? GSDL::Direction::South : GSDL::Direction::North
                       else
                         nxt.x > node.x ? GSDL::Direction::East : GSDL::Direction::West
                       end
            
            action = determine_action(entrance_dir, exit_dir)
            @path << action
            action_logs << "#{action} at [#{node.x.to_i},#{node.y.to_i}]"
          end
        end
      end

      @next_action = @path.shift? || IntersectionAction::Straight

      if priority?
        puts "Priority #{asset_prefix} Path Generated:"
        puts "  Spawn: #{x.to_i}, #{y.to_i} (Tile: #{(x/TileSize).to_i}, #{(y/TileSize).to_i})"
        puts "  Target: #{target.type} at #{target.x}, #{target.y}"
        puts "  Nodes: #{@node_path.map(&.type).join(" -> ")}"
        puts "  Actions: #{action_logs.join(" -> ")}"
        puts "  Current Action: [#{@next_action}] | Queue: #{@path.to_a.join(", ")}"
      end
    end

    def draw_path(draw : GSDL::Draw, intersections : Array(Intersection))
      segments = project_path_segments(intersections)
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

    def distance_to(other_x : Float32, other_y : Float32)
      Math.sqrt((self.x - other_x)**2 + (self.y - other_y)**2)
    end

    def clicked?(mx : Float32, my : Float32) : Bool
      target_in?(mx, my)
    end

    def area_bounding_box : GSDL::FRect
      # 4px padding around the sprite
      GSDL::FRect.new(-4_f32, -4_f32, width.to_f32 + 8_f32, height.to_f32 + 8_f32)
    end

    private def determine_action(current : GSDL::Direction, target : GSDL::Direction) : IntersectionAction
      return IntersectionAction::Straight if current == target

      case current
      when .east?
        return IntersectionAction::Right if target.south?
        return IntersectionAction::Left if target.north?
      when .west?
        return IntersectionAction::Right if target.north?
        return IntersectionAction::Left if target.south?
      when .north?
        return IntersectionAction::Right if target.east?
        return IntersectionAction::Left if target.west?
      when .south?
        return IntersectionAction::Right if target.west?
        return IntersectionAction::Left if target.east?
      end

      # If we reach here, it's a U-turn or invalid
      IntersectionAction::Straight
    end

    def update(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      super(dt)

      # Update hover state
      mx, my = GSDL::Mouse.position
      cam = GSDL::Game.camera
      world_mx = (mx / cam.zoom) + cam.x
      world_my = (my / cam.zoom) + cam.y
      @hovered = target_in?(world_mx, world_my)

      if @blinker_timer.done?
        @blinker_on = !@blinker_on
        @blinker_timer.restart
      end

      update_special_behavior(dt, intersections, all_vehicles)

      return if @wrecked
      @waiting = false

      # 1. Check for Target Arrival
      if target_reached?
        if priority?
           # Snap to exact target coordinates
           target = @target_node.not_nil!
           self.x = target.x
           self.y = target.y

           # Start wait timer if not already running
           unless @target_wait_timer.running? || @target_wait_timer.done?
             @target_wait_timer.start
           end

           @waiting = true # Force brake animation and stop moving

           if @target_wait_timer.done?
             @finished = true
           end
        else
           # Civilians finish immediately upon reaching their Exit node
           @finished = true
        end
      end

      return if @finished

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
        # Final Approach Homing for Priority Vehicles
        if priority? && (target = @target_node) && !target.type.exit?
          dist = distance_to(target.x, target.y)
          if dist < 1.5_f32 * TileSize
            # Perpendicular homing to handle off-lane target nodes
            home_speed = 100.0_f32 * dt
            case self.direction
            when .north?, .south?
              diff = target.x - self.x
              if diff.abs > 1.0_f32
                self.x += (diff > 0 ? home_speed : -home_speed)
              end
            when .east?, .west?
              diff = target.y - self.y
              if diff.abs > 1.0_f32
                self.y += (diff > 0 ? home_speed : -home_speed)
              end
            end
            end
            end

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

      update_animation_state
    end

    private def update_animation_state
      is_braking = @waiting || @speed < @original_speed * 0.8
      is_blinking_left = @next_action.left?
      is_blinking_right = @next_action.right?

      anim = if is_braking
        if is_blinking_left
          "brake_blink_left"
        elsif is_blinking_right
          "brake_blink_right"
        else
          "brake"
        end
      else
        if is_blinking_left
          "blink_left"
        elsif is_blinking_right
          "blink_right"
        else
          "idle"
        end
      end

      @active_sprite_top.try do |top|
        top.play(anim) unless top.playing?(anim)
      end

      @active_sprite_sirens.try do |sirens|
        sirens.play("active") unless sirens.playing?("active")
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
            # @next_action = IntersectionAction::Straight
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
                @node_path.shift?
                @safety_timer = GSDL::Timer.new(0.5.seconds); @safety_timer.try(&.start)
              end
            else
                @last_intersection = nil
            end
          elsif @next_action.straight?
            @next_action = path.shift? || IntersectionAction::Straight
            @node_path.shift?
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

    def target_reached? : Bool
      return false unless target = @target_node
      # Threshold: must be very close to the target node
      # Using 16.0 to be robust against high speeds (up to 9px/frame at 60fps)
      distance_to(target.x, target.y) < 16.0_f32
    end

    def off_screen?(map_width : Int32 | Float32, map_height : Int32 | Float32)
      buffer = TileSize * 2
      self.x < -buffer || self.x > (map_width + buffer) ||
      self.y < -buffer || self.y > (map_height + buffer)
    end

    def draw(draw : GSDL::Draw)
      if @hovered
        # Box primitive below the vehicle to show clickable area
        GSDL::Box.new(
          x: area_box.x,
          y: area_box.y,
          width: area_box.w,
          height: area_box.h,
          color: GSDL::ColorScheme.get(:highlight_alt),
          z_index: z_index - 1
        ).draw(draw)
      end

      @active_sprite_body.tint = tint_body? ? @paint_color : GSDL::Color::White

      if @wrecked
        # TODO: uses subtraction, probably should be redone for clarity
        wrecked_color = @paint_color - GSDL::ColorScheme.get(:wrecked)
        @active_sprite_body.tint = wrecked_color
        @active_sprite_top.try { |t| t.tint = wrecked_color }
        @active_sprite_sirens.try { |s| s.tint = wrecked_color }
      end

      @active_sprite_body.z_index = z_index
      @active_sprite_top.try { |t| t.z_index = z_index }
      @active_sprite_sirens.try { |s| s.z_index = z_index }

      super(draw)

      draw_status_overlay(draw, height.to_f32, GSDL::Game.camera.x, GSDL::Game.camera.y)
    end
  end
end
