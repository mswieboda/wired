module Traffic
  enum IntersectionSignal
    GreenNS
    YellowNS
    GreenNSLeft
    YellowNSLeft
    GreenEW
    YellowEW
    GreenEWLeft
    YellowEWLeft
    AllRed
  end

  class Intersection < GSDL::Sprite
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    getter tile_x : Int32
    getter tile_y : Int32
    @state_timer : GSDL::Timer
    @tile_x : Int32
    @tile_y : Int32

    def initialize(@tile_x, @tile_y)
      px = @tile_x * TileSize
      py = @tile_y * TileSize
      super("signal", px + IntersectionSize - 20, py + 2)
      @state = IntersectionSignal::GreenNS
      @state_timer = GSDL::Timer.new(10.seconds)
      @state_timer.start
    end

    def update(dt : Float32)
      if @state_timer.done?
        case @state
        when .green_ns?       then @state = IntersectionSignal::YellowNS;      @state_timer.duration = 3.seconds
        when .yellow_ns?      then @state = IntersectionSignal::GreenNSLeft;  @state_timer.duration = 10.seconds
        when .green_ns_left?  then @state = IntersectionSignal::YellowNSLeft; @state_timer.duration = 3.seconds
        when .yellow_ns_left? then @state = IntersectionSignal::AllRed;        @state_timer.duration = 1.seconds
        when .all_red?        then @state = IntersectionSignal::GreenEW;       @state_timer.duration = 10.seconds
        when .green_ew?       then @state = IntersectionSignal::YellowEW;      @state_timer.duration = 3.seconds
        when .yellow_ew?      then @state = IntersectionSignal::GreenEWLeft;  @state_timer.duration = 10.seconds
        when .green_ew_left?  then @state = IntersectionSignal::YellowEWLeft; @state_timer.duration = 3.seconds
        when .yellow_ew_left? then @state = IntersectionSignal::GreenNS;       @state_timer.duration = 10.seconds
        end
        @state_timer.restart
      end
    end

    def toggle
      case @state
      when .green_ns?       then puts "Forcing NS Yellow..."; @state = IntersectionSignal::YellowNS;      @state_timer.duration = 3.seconds
      when .green_ns_left?  then puts "Forcing NS Left Yellow..."; @state = IntersectionSignal::YellowNSLeft; @state_timer.duration = 3.seconds
      when .green_ew?       then puts "Forcing EW Yellow..."; @state = IntersectionSignal::YellowEW;      @state_timer.duration = 3.seconds
      when .green_ew_left?  then puts "Forcing EW Left Yellow..."; @state = IntersectionSignal::YellowEWLeft; @state_timer.duration = 3.seconds
      else return
      end
      @state_timer.restart
    end

    def clicked?(mx, my)
      px = @tile_x * TileSize
      py = @tile_y * TileSize
      mx >= px && mx < px + IntersectionSize && my >= py && my < py + IntersectionSize
    end

    def draw(draw : GSDL::Draw)
      px = @tile_x * TileSize
      py = @tile_y * TileSize
      cam_x, cam_y = GSDL::Game.camera.x, GSDL::Game.camera.y
      zoom = GSDL::Game.camera.zoom
      
      # Tints
      color_green  = GSDL::Color.new(100, 255, 100)
      color_yellow = GSDL::Color.new(255, 255, 100)
      color_red    = GSDL::Color.new(255, 100, 100)

      ns_tint = color_red
      ew_tint = color_red
      ns_left_color = color_red
      ew_left_color = color_red

      case @state
      when .green_ns?       then ns_tint = color_green
      when .yellow_ns?      then ns_tint = color_yellow
      when .green_ns_left?  then ns_left_color = color_green
      when .yellow_ns_left? then ns_left_color = color_yellow
      when .green_ew?       then ew_tint = color_green
      when .yellow_ew?      then ew_tint = color_yellow
      when .green_ew_left?  then ew_left_color = color_green
      when .yellow_ew_left? then ew_left_color = color_yellow
      end

      # 1. Draw Signal Head Textures
      old_scale_x, old_scale_y = draw.current_scale_x, draw.current_scale_y
      draw.scale = zoom
      
      ns_x = px + (IntersectionSize - 12.0_f32)
      ns_y = py + 16.0_f32
      ew_center_x = px + 24.0_f32
      ew_center_y = py + (IntersectionSize - 4.0_f32)
      ew_rect_x = ew_center_x - 8.0_f32
      ew_rect_y = ew_center_y - 32.0_f32

      draw.texture(GSDL::TextureManager.get("signal"), dest_rect: GSDL::FRect.new(ns_x - cam_x, ns_y - cam_y, 16, 64), tint: ns_tint, z_index: z_index)
      draw.texture_rotated(GSDL::TextureManager.get("signal"), dest_rect: GSDL::FRect.new(ew_rect_x - cam_x, ew_rect_y - cam_y, 16, 64), angle: 90.0, center: GSDL::Point.new(8, 32), tint: ew_tint, z_index: z_index)

      draw.scale = {old_scale_x, old_scale_y}

      # 2. Draw Left Arrows (Smaller, Always Visible)
      # NS facing Left
      p1_ns = {ns_x - 14.0_f32, ns_y + 32.0_f32} # Tip
      p2_ns = {ns_x - 2.0_f32,  ns_y + 22.0_f32} # Top
      p3_ns = {ns_x - 2.0_f32,  ns_y + 42.0_f32} # Bottom
      GSDL::Triangle.new(p1_ns, p2_ns, p3_ns, color: ns_left_color, z_index: z_index + 20).draw(draw)

      # EW facing Up
      p1_ew = {ew_center_x,              ew_center_y - 14.0_f32} # Tip
      p2_ew = {ew_center_x - 10.0_f32,  ew_center_y - 2.0_f32}  # Left
      p3_ew = {ew_center_x + 10.0_f32,  ew_center_y - 2.0_f32}  # Right
      GSDL::Triangle.new(p1_ew, p2_ew, p3_ew, color: ew_left_color, z_index: z_index + 20).draw(draw)
    end
  end
end
