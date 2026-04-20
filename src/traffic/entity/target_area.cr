module Traffic
  class TargetArea < GSDL::Entity
    property type : NodeType

    def initialize(@type, x : Float32, y : Float32, ox : Float32 = 0.0_f32, oy : Float32 = 0.0_f32)
      @x = x
      @y = y
      @origin = {0.5_f32, 0.5_f32}
      
      asset = case @type
              when .target_ambulance? then "hospital"
              when .target_police?    then "police-station"
              when .target_vip?       then "penthouse"
              else "hospital" # fallback
              end
      
      # Visual Sprite
      sprite = GSDL::Sprite.new(asset, origin: {0.5_f32, 0.5_f32})
      sprite.x = ox * TileSize
      sprite.y = oy * TileSize
      add_child(sprite)
    end

    def draw(draw : GSDL::Draw)
      super(draw)
      
      draw_pulse_animation(draw)
    end

    def draw_pulse_animation(draw : GSDL::Draw)
      # neon glow under/around target area
      color = case @type
              when .target_ambulance? then GSDL::ColorScheme.get(:target_hospital)
              when .target_police?    then GSDL::ColorScheme.get(:target_police)
              when .target_vip?       then GSDL::ColorScheme.get(:target_vip)
              else GSDL::Color::White
              end
      color.alpha = 128_u8

      # Simple pulse logic based on time
      pulse = (Math.sin((GSDL.ticks / 1000.0) * 4.0).to_f32 + 1.0_f32) / 2.0_f32
      glow_size = TileSize * (1.25_f32 + pulse * 0.2_f32)

      GSDL::Box.new(
        width: glow_size,
        height: glow_size,
        x: self.x - (glow_size / 2),
        y: self.y - (glow_size / 2),
        color: color,
        z_index: -11 # behind roads
      ).draw(draw)
    end
  end
end

