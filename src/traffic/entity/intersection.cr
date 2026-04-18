module Traffic
  enum IntersectionSignal
    GreenNS
    YellowNS
    GreenEW
    YellowEW
  end

  class Intersection < GSDL::Sprite
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    @state_timer : GSDL::Timer
    @tile_x : Int32
    @tile_y : Int32

    def initialize(@tile_x, @tile_y)
      # Position in pixels based on tile coordinates
      px = @tile_x * 128
      py = @tile_y * 128

      super("signal", px + 128 - 20, py + 2)
      @state = IntersectionSignal::GreenNS
      @state_timer = GSDL::Timer.new(3.seconds)
    end

    def update(dt : Float32)
      if @state_timer.done?
        next_state
      end
    end

    def next_state
      case @state
      when IntersectionSignal::YellowNS
        @state = IntersectionSignal::GreenEW
      when IntersectionSignal::YellowEW
        @state = IntersectionSignal::GreenNS
      else
        # No auto-transition from Green for now
      end
      @state_timer.stop
    end

    def toggle
      return if @state_timer.running?

      case @state
      when IntersectionSignal::GreenNS
        @state = IntersectionSignal::YellowNS
        @state_timer.restart
      when IntersectionSignal::GreenEW
        @state = IntersectionSignal::YellowEW
        @state_timer.restart
      else
        # Transitioning, ignore
      end
    end

    def clicked?(mx, my)
      px = @tile_x * 128
      py = @tile_y * 128
      mx >= px && mx < px + 128 && my >= py && my < py + 128
    end

    def draw(draw : GSDL::Draw)
      # Common coordinates for the tile in world space
      px = @tile_x * 128.0_f32
      py = @tile_y * 128.0_f32

      # NS Signal (Vertical)
      # 3/4 (12px) inside right edge, 1/4 (4px) outside.
      # Right edge is px + 128. So ns_x = px + 128 - 12 = px + 116.
      ns_x = px + 116.0_f32
      ns_y = py + 16.0_f32

      # EW Signal (Horizontal)
      # 3/4 (12px) inside bottom edge, 1/4 (4px) outside.
      # Bottom edge is py + 128. Signal "height" is 16.
      # Bottom of signal is ew_center_y + 8.
      # So ew_center_y + 8 = py + 128 + 4 => ew_center_y = py + 124.
      ew_center_x = px + 24.0_f32
      ew_center_y = py + 124.0_f32

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

      # NS Glow (Vertical offsets)
      case @state
      when IntersectionSignal::GreenNS
        draw.circle_fill(ns_x + 8, ns_y + 52, 6, glow_color, z_index + 1)
      when IntersectionSignal::YellowNS
        draw.circle_fill(ns_x + 8, ns_y + 32, 6, glow_color, z_index + 1)
      when IntersectionSignal::GreenEW, IntersectionSignal::YellowEW
        draw.circle_fill(ns_x + 8, ns_y + 12, 6, glow_color, z_index + 1)
      end

      # EW Glow (Horizontal offsets after 90 deg rotation)
      case @state
      when IntersectionSignal::GreenEW
        # Green is at center - 20
        draw.circle_fill(ew_center_x - 20, ew_center_y, 6, glow_color, z_index + 1)
      when IntersectionSignal::YellowEW
        # Yellow is at center
        draw.circle_fill(ew_center_x, ew_center_y, 6, glow_color, z_index + 1)
      when IntersectionSignal::GreenNS, IntersectionSignal::YellowNS
        # Red is at center + 20
        draw.circle_fill(ew_center_x + 20, ew_center_y, 6, glow_color, z_index + 1)
      end
    end
  end
end
