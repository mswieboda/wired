require "./vehicle"

module Traffic
  class VehiclePriority < Vehicle
    property type : PriorityType = PriorityType::Ambulance
    @time_to_destination : Float32 = 0.0_f32

    def initialize(direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32, @type = PriorityType::Ambulance)
      super(direction, x, y)
      @time_to_destination = 0.0_f32
    end

    def priority? : Bool
      true
    end

    def has_top? : Bool
      false
    end

    def has_sirens? : Bool
      true
    end

    def tint_body? : Bool
      false
    end

    def skips_red_lights? : Bool
      true
    end

    def base_speed_range : Range(Float32, Float32)
      (400.0_f32)..(550.0_f32)
    end

    def late_to_target? : Bool
      @time_to_destination >= PriorityTimeToDestination
    end

    def select_target(graph : NodeGraph)
      # Priority logic: Hospital, Police, etc.
      type_node = case @type
                  when .ambulance? then NodeType::TargetAmbulance
                  when .police?    then NodeType::TargetPolice
                  when .vip?       then NodeType::TargetVIP
                  else NodeType::Exit
                  end

      targets = graph.nodes.select { |n| n.type == type_node }

      # Filter targets based on accessibility from the correct side of the road
      valid_targets = targets.select do |target|
        # Simulate finding the closest start node to our vehicle
        start_node = graph.nodes.select do |node|
          dist = node.distance_to(self.x.to_f32, self.y.to_f32)
          next true if dist < 16.0_f32 # Very close (on same spot)

          case self.direction
          when .east?  then node.x > self.x - 10.0_f32 && (node.y - self.y).abs < TileSize
          when .west?  then node.x < self.x + 10.0_f32 && (node.y - self.y).abs < TileSize
          when .north? then node.y < self.y + 10.0_f32 && (node.x - self.x).abs < TileSize
          when .south? then node.y > self.y - 10.0_f32 && (node.x - self.x).abs < TileSize
          else false
          end
        end.min_by? { |node| node.distance_to(self.x.to_f32, self.y.to_f32) }

        if start_node
          path = Pathfinder.find_path(start_node, target)
          unless path.empty?
            # Determine the final approach direction
            final_approach_dir = if path.size >= 2
                                   prev = path[-2]
                                   curr = path[-1]
                                   if (curr.x - prev.x).abs < (curr.y - prev.y).abs
                                     curr.y > prev.y ? GSDL::Direction::South : GSDL::Direction::North
                                   else
                                     curr.x > prev.x ? GSDL::Direction::East : GSDL::Direction::West
                                   end
                                 else
                                   self.direction
                                 end

            # Check if the final approach direction matches the required side of the road
            is_valid = if target.sprite_offset_y < 0.0_f32
                         final_approach_dir.left?
                       elsif target.sprite_offset_y > 0.0_f32
                         final_approach_dir.right?
                       elsif target.sprite_offset_x < 0.0_f32
                         final_approach_dir.down?
                       elsif target.sprite_offset_x > 0.0_f32
                         final_approach_dir.up?
                       else
                         true # No strict offset requirement
                       end

            # puts "Target #{target.type} accessibility check: #{is_valid} (Approach: #{final_approach_dir})"
            is_valid
          else
            # puts "Target #{target.type} rejected: No path found"
            false
          end
        else
          # puts "Target #{target.type} rejected: No start node in front"
          false
        end
      end

      # Fallback to random exit if no valid specific target found
      if valid_targets.empty?
        # puts "Priority vehicle #{@type} falling back to random Exit"
        valid_targets = graph.nodes.select(&.type.exit?)
      end

      @target_node = valid_targets.empty? ? nil : valid_targets.sample
      # puts "Priority vehicle #{@type} selected target: #{@target_node.try(&.type)} at #{@target_node.try(&.x)}, #{@target_node.try(&.y)}"
    end

    def asset_prefix : String
      case @type
      when .ambulance? then "ambulance"
      when .police?    then "cop"
      else "ambulance"
      end
    end

    def v_dims : Tuple(Int32, Int32)
      @type.ambulance? ? {32, 64} : {32, 48}
    end

    def setup_siren_animations(sprite : GSDL::AnimatedSprite, kind : Symbol)
      sprite.add("active", [0, 0, 1, 2, 1, 2, 1, 2, 1, 2], fps: 6)
      sprite.play("active")
    end

    def update_special_behavior(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      add_rate = 1.0_f32
      add_rate = is_waiting_on_wreck?(all_vehicles) ? 10.0_f32 : 3.0_f32 if @waiting
      @time_to_destination += dt * add_rate
      @time_to_destination = PriorityTimeToDestination if @time_to_destination >= PriorityTimeToDestination
    end

    def draw_status_overlay(draw : GSDL::Draw, th : Float32, cam_x : Float32, cam_y : Float32)
      # Priority-specific status (destination time) progress bar
      bar_w, bar_h = 48.0_f32, 12.0_f32
      bar_x, bar_y = self.x - (bar_w / 2.0_f32), self.y - (th / 2.0_f32) - 12.0_f32

      # Background
      GSDL::Box.new(
        width: bar_w,
        height: bar_h,
        x: bar_x,
        y: bar_y,
        color: GSDL::Color.new(30, 30, 30, 150),
        z_index: z_index + 1
      ).draw(draw)

      percent = Math.min(1.0_f32, @time_to_destination / PriorityTimeToDestination)
      color = if percent >= 1.0
          # red
          GSDL::Color.new(255, 50, 50)
        elsif percent >= 0.6
          # orange
          GSDL::Color.new(255, 120, 50)
        elsif percent >= 0.15
          # yellow
          GSDL::Color.new(255, 255, 50)
        else
          # green
          GSDL::Color.new(100, 255, 100)
        end

      # color = road_rage? ? GSDL::Color.new(255, 50, 50) : (frustrated? ? GSDL::Color.new(255, 120, 50) : (anxious? ? GSDL::Color.new(255, 255, 50) : GSDL::Color.new(100, 255, 100)))

      # Fill
      GSDL::Box.new(
        width: bar_w * percent,
        height: bar_h,
        x: bar_x,
        y: bar_y,
        color: color,
        z_index: z_index + 2
      ).draw(draw)

      # TODO: make this an X
      if percent >= 1
        GSDL::Box.new(
          width: 8,
          height: 14,
          x: bar_x + bar_w + 4,
          y: bar_y - 4,
          color: GSDL::Color.new(255, 0, 0),
          z_index: z_index + 3
        ).draw(draw)
      end
    end
  end
end
