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
    @signal_ns : TrafficSignal
    @signal_ew : TrafficSignal

    def initialize(@tile_x, @tile_y)
      px = @tile_x * TileSize
      py = @tile_y * TileSize

      ns_x = px + (IntersectionSize - 12.0_f32)
      ns_y = py + 16.0_f32
      @signal_ns = TrafficSignal.new("traffic-signal-ns", ns_x, ns_y)

      ew_x = px + 16.0_f32
      ew_y = py + (IntersectionSize - 36.0_f32)
      @signal_ew = TrafficSignal.new("traffic-signal-ew", ew_x, ew_y)

      # We don't use the base sprite for drawing anymore, but we must initialize it
      super("traffic-signal-ns", px, py)

      @state = IntersectionSignal::GreenNS
      update_signal_frames
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
        update_signal_frames
      end
    end

    def update_signal_frames
      case @state
      when .green_ns?
        @signal_ns.show_green
        @signal_ew.show_red
      when .yellow_ns?
        @signal_ns.show_yellow
        @signal_ew.show_red
      when .green_ns_left?
        @signal_ns.show_red_turn_green
        @signal_ew.show_red
      when .yellow_ns_left?
        @signal_ns.show_red_turn_yellow
        @signal_ew.show_red
      when .green_ew?
        @signal_ns.show_red
        @signal_ew.show_green
      when .yellow_ew?
        @signal_ns.show_red
        @signal_ew.show_yellow
      when .green_ew_left?
        @signal_ns.show_red
        @signal_ew.show_red_turn_green
      when .yellow_ew_left?
        @signal_ns.show_red
        @signal_ew.show_red_turn_yellow
      when .all_red?
        @signal_ns.show_red
        @signal_ew.show_red
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
      update_signal_frames
    end

    def clicked?(mx, my)
      px = @tile_x * TileSize
      py = @tile_y * TileSize
      mx >= px && mx < px + IntersectionSize && my >= py && my < py + IntersectionSize
    end

    def draw(draw : GSDL::Draw)
      @signal_ns.z_index = z_index
      @signal_ew.z_index = z_index

      @signal_ns.draw(draw)
      @signal_ew.draw(draw)
    end
  end
end
