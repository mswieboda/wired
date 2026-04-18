module Traffic
  enum IntersectionSignal
    GreenNS
    YellowNS
    GreenEW
    YellowEW
  end

  class Intersection < GSDL::Sprite
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    @timer : Float32 = 0.0
    @tile_x : Int32
    @tile_y : Int32

    def initialize(@tile_x, @tile_y)
      # Position in pixels based on tile coordinates
      px = @tile_x * 128
      py = @tile_y * 128
      
      # The signal sprite will be drawn twice, but for now let's just make it a composite or something.
      # Actually, let's just use GSDL::Draw to draw the signal indicator.
      # But the user asked for a 16x64 signal graphic.
      
      # We'll place two signals: one for NS (vertical) and one for EW (horizontal).
      # For now, let's just place one and see how it looks.
      super("signal", px + 128 - 20, py + 2)
      @state = IntersectionSignal::GreenNS
    end

    def update(dt : Float32)
      if @state == IntersectionSignal::YellowNS || @state == IntersectionSignal::YellowEW
        @timer -= dt
        if @timer <= 0
          next_state
        end
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
    end

    def toggle
      case @state
      when IntersectionSignal::GreenNS
        @state = IntersectionSignal::YellowNS
        @timer = 3.0
      when IntersectionSignal::GreenEW
        @state = IntersectionSignal::YellowEW
        @timer = 3.0
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
      # Common coordinates for the tile
      px = @tile_x * 128.0_f32
      py = @tile_y * 128.0_f32

      # NS Signal (Vertical)
      # Position: Center of the road (px + 64), offset by half width (8px) = px + 56
      # Moved down 32px for spacing
      ns_x = px + 56.0_f32
      ns_y = py + 32.0_f32
      draw.texture(
        texture: GSDL::TextureManager.get("signal"),
        dest_rect: GSDL::FRect.new(x: ns_x, y: ns_y, w: 16, h: 64),
        z_index: z_index
      )
      
      # EW Signal (Horizontal)
      # Position: Center of the tile (px + 64, py + 64), rotated
      # Moved left 32px (ew_center_x = 64 - 32 = 32)
      ew_center_x = px + 32.0_f32
      ew_center_y = py + 64.0_f32
      
      ew_rect_x = ew_center_x - 8.0_f32
      ew_rect_y = ew_center_y - 32.0_f32
      
      draw.texture_rotated(
        texture: GSDL::TextureManager.get("signal"),
        dest_rect: GSDL::FRect.new(x: ew_rect_x, y: ew_rect_y, w: 16, h: 64),
        angle: 90.0,
        center: GSDL::Point.new(8, 32), # Rotate around its own center
        z_index: z_index
      )
      
      # Glow effect for active lights
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
      # Clockwise 90 deg: (0, -20) -> (+20, 0)
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
