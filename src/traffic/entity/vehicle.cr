module Traffic
  enum VehicleType
    Civilian
    Priority
  end

  class Vehicle < GSDL::Sprite
    property vehicle_type : VehicleType
    property speed : Float32
    property? waiting : Bool = false

    @original_speed : Float32

    def initialize(@vehicle_type, direction : GSDL::Direction, x, y)
      @original_speed = case @vehicle_type
                        when VehicleType::Priority
                          Random.rand(400.0_f32..550.0_f32)
                        else
                          Random.rand(200.0_f32..350.0_f32)
                        end
      @speed = @original_speed

      super("car", x, y)
      self.direction = direction

      # Adjust visual orientation and center on lane
      # car.png is 64x32
      # tile is 128x128
      case self.direction
      when .east?
        self.rotation = 0.0
      when .west?
        self.rotation = 180.0
      when .north?
        self.rotation = 270.0
      when .south?
        self.rotation = 90.0
      else # default
      end
    end

    def update(dt : Float32, intersections : Array(Intersection))
      @waiting = false

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

      # Intersection check
      check_intersections(intersections)

      unless @waiting
        self.x += dx * @speed * dt
        self.y += dy * @speed * dt
      end
    end

    private def check_intersections(intersections)
      # Detection box in front of the vehicle
      # Since tiles are 128px, let's check about 40px ahead
      look_ahead = 40.0_f32

      check_x = self.x + 32 # center of 64px width
      check_y = self.y + 16 # center of 32px height

      case self.direction
      when .east?  then check_x += look_ahead
      when .west?  then check_x -= look_ahead
      when .north? then check_y -= look_ahead
      when .south? then check_y += look_ahead
      else # ignore others
      end

      intersections.each do |inter|
        if inter.clicked?(check_x, check_y) # Reusing clicked? for bounds check
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
      # map is 20*128 x 11*128 = 2560x1408
      self.x < -200 || self.x > 2760 || self.y < -200 || self.y > 1600
    end

    def draw(draw : GSDL::Draw)
      # Manually account for camera for texture drawing
      old_scale_x = draw.current_scale_x
      old_scale_y = draw.current_scale_y

      draw.scale = GSDL::Game.camera.zoom

      cam_x = GSDL::Game.camera.x
      cam_y = GSDL::Game.camera.y

      # Use texture_rotated for orientation
      draw.texture_rotated(
        texture: GSDL::TextureManager.get("car"),
        dest_rect: GSDL::FRect.new(x: self.x - cam_x, y: self.y - cam_y, w: 64, h: 32),
        angle: self.rotation.to_f32,
        center: GSDL::Point.new(32, 16),
        z_index: z_index
      )

      draw.scale = {old_scale_x, old_scale_y}
    end
  end
end
