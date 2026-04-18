module Traffic
  enum IntersectionSignal
    GreenNS
    GreenNSLeft
    YellowNS
    GreenEW
    GreenEWLeft
    YellowEW
  end

  class Intersection < GSDL::Sprite
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    getter tile_x : Int32
    getter tile_y : Int32
    @state_timer : GSDL::Timer
    @switch_interval : Time::Span
    @tile_x : Int32
    @tile_y : Int32

    def initialize(@tile_x, @tile_y, switch_seconds : Int32 = 10)
      # Position in pixels based on top-left tile of 2x2 intersection
      px = @tile_x * TileSize
      py = @tile_y * TileSize

      @switch_interval = switch_seconds.seconds
      super("signal", px + IntersectionSize - 20, py + 2)
      @state = IntersectionSignal::GreenNS
      @state_timer = GSDL::Timer.new(@switch_interval)
      @state_timer.start
    end

    def update(dt : Float32)
      if @state_timer.done?
        case @state
        when IntersectionSignal::GreenNS
          @state = IntersectionSignal::GreenNSLeft
          @state_timer.duration = 10.seconds
          @state_timer.restart
        when IntersectionSignal::GreenNSLeft
          @state = IntersectionSignal::YellowNS
          @state_timer.duration = 3.seconds
          @state_timer.restart
        when IntersectionSignal::YellowNS
          @state = IntersectionSignal::GreenEW
          @state_timer.duration = @switch_interval
          @state_timer.restart
        when IntersectionSignal::GreenEW
          @state = IntersectionSignal::GreenEWLeft
          @state_timer.duration = 10.seconds
          @state_timer.restart
        when IntersectionSignal::GreenEWLeft
          @state = IntersectionSignal::YellowEW
          @state_timer.duration = 3.seconds
          @state_timer.restart
        when IntersectionSignal::YellowEW
          @state = IntersectionSignal::GreenNS
          @state_timer.duration = @switch_interval
          @state_timer.restart
        end
      end
    end

    def toggle
      # Manual toggle can still work, just restart the timer for the next phase
      case @state
      when IntersectionSignal::GreenNS
        @state = IntersectionSignal::GreenNSLeft
        @state_timer.duration = 10.seconds
        @state_timer.restart
      when IntersectionSignal::GreenEW
        @state = IntersectionSignal::GreenEWLeft
        @state_timer.duration = 10.seconds
        @state_timer.restart
      else
        # Transitioning, ignore
      end
    end


    def clicked?(mx, my)
      px = @tile_x * TileSize
      py = @tile_y * TileSize
      mx >= px && mx < px + IntersectionSize && my >= py && my < py + IntersectionSize
    end

    def draw(draw : GSDL::Draw)
      # Common coordinates for the 2x2 block in world space
      px = @tile_x * TileSize
      py = @tile_y * TileSize

      # NS Signal (Vertical)
      # Positioned on the right edge of the 256px block
      ns_x = px + (IntersectionSize - 12.0_f32)
      ns_y = py + 16.0_f32

      # EW Signal (Horizontal)
      # Positioned on the bottom edge of the 256px block
      ew_center_x = px + 24.0_f32
      ew_center_y = py + (IntersectionSize - 4.0_f32)

      ew_rect_x = ew_center_x - 8.0_f32
      ew_rect_y = ew_center_y - 32.0_f32

      # Manually account for camera for texture drawing
      old_scale_x = draw.current_scale_x
      old_scale_y = draw.current_scale_y

      draw.scale = GSDL::Game.camera.zoom

      cam_x = GSDL::Game.camera.x
      cam_y = GSDL::Game.camera.y

      # Draw NS Signal
      draw.texture(
        texture: GSDL::TextureManager.get("signal"),
        dest_rect: GSDL::FRect.new(x: ns_x - cam_x, y: ns_y - cam_y, w: 16, h: 64),
        z_index: z_index
      )

      # Draw EW Signal
      draw.texture_rotated(
        texture: GSDL::TextureManager.get("signal"),
        dest_rect: GSDL::FRect.new(x: ew_rect_x - cam_x, y: ew_rect_y - cam_y, w: 16, h: 64),
        angle: 90.0,
        center: GSDL::Point.new(8, 32),
        z_index: z_index
      )

      draw.scale = {old_scale_x, old_scale_y}

      # Glow effect for active lights (GSDL::Shape handles camera automatically)
      glow_color = GSDL::Color.new(red: 255, green: 255, blue: 255, alpha: 180)
      left_glow_color = GSDL::Color.new(red: 100, green: 255, blue: 100, alpha: 220)

      # NS Glow (Vertical offsets)
      case @state
      when IntersectionSignal::GreenNS
        draw.circle_fill(ns_x + 8, ns_y + 52, 6, glow_color, z_index + 1)
      when IntersectionSignal::GreenNSLeft
        # Left-turn indicator
        draw.circle_fill(ns_x + 8, ns_y + 52, 7, left_glow_color, z_index + 1)
        draw.rect_fill(GSDL::FRect.new(ns_x + 4, ns_y + 48, 8, 8), left_glow_color, z_index + 2)
      when IntersectionSignal::YellowNS
        draw.circle_fill(ns_x + 8, ns_y + 32, 6, glow_color, z_index + 1)
      else
        # Red is at ns_y + 12
        draw.circle_fill(ns_x + 8, ns_y + 12, 6, glow_color, z_index + 1)
      end

      # EW Glow (Horizontal offsets after 90 deg rotation)
      case @state
      when IntersectionSignal::GreenEW
        # Green is at center - 20
        draw.circle_fill(ew_center_x - 20, ew_center_y, 6, glow_color, z_index + 1)
      when IntersectionSignal::GreenEWLeft
        draw.circle_fill(ew_center_x - 20, ew_center_y, 7, left_glow_color, z_index + 1)
        draw.rect_fill(GSDL::FRect.new(ew_center_x - 24, ew_center_y - 4, 8, 8), left_glow_color, z_index + 2)
      when IntersectionSignal::YellowEW
        # Yellow is at center
        draw.circle_fill(ew_center_x, ew_center_y, 6, glow_color, z_index + 1)
      else
        # Red is at center + 20
        draw.circle_fill(ew_center_x + 20, ew_center_y, 6, glow_color, z_index + 1)
      end

    end
  end
end
