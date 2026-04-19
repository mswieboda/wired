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

  class Intersection < GSDL::Entity
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    getter tile_x : Int32
    getter tile_y : Int32

    GreenDuration = 28_f32
    GreenLeftDuration = 5_f32
    YellowDuration = 2_f32
    RedDuration = 1_f32

    @state_timer : GSDL::Timer
    @tile_x : Int32
    @tile_y : Int32
    @signal_nb : TrafficSignal
    @signal_eb : TrafficSignal
    @signal_sb : TrafficSignal
    @signal_wb : TrafficSignal

    def initialize(@tile_x, @tile_y)
      @x = @tile_x * TileSize
      @y = @tile_y * TileSize
      @state = IntersectionSignal::GreenNS
      @state_timer = GSDL::Timer.new(GreenDuration.seconds)

      # Position children relative to parent
      offset = 12_f32
      origin = {0.5_f32, 1_f32}

      # north-bound
      offset_x = IntersectionSize - offset
      @signal_nb = TrafficSignal.new("traffic-signal-nb", offset_x, offset, origin)

      # east-bound
      offset_x = IntersectionSize - offset
      offset_y = IntersectionSize - offset
      @signal_eb = TrafficSignal.new("traffic-signal-eb", offset_x, offset_y, origin)

      # south-bound
      offset_y = IntersectionSize - offset
      @signal_sb = TrafficSignal.new("traffic-signal-sb", offset, offset_y, origin)

      # west-bound
      @signal_wb = TrafficSignal.new("traffic-signal-wb", offset, offset, origin)

      add_child(@signal_nb)
      add_child(@signal_eb)
      add_child(@signal_sb)
      add_child(@signal_wb)

      update_signal_frames
      @state_timer.start
    end

    def update(dt : Float32)
      return unless super(dt)

      if @state_timer.done?
        case @state
        when .green_ns?
          @state = IntersectionSignal::YellowNS
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ns?
          @state = IntersectionSignal::GreenNSLeft
          @state_timer.duration = GreenLeftDuration.seconds
        when .green_ns_left?
          @state = IntersectionSignal::YellowNSLeft
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ns_left?
          @state = IntersectionSignal::AllRed
          @state_timer.duration = RedDuration.seconds
        when .all_red?
          @state = IntersectionSignal::GreenEW
          @state_timer.duration = GreenDuration.seconds
        when .green_ew?
          @state = IntersectionSignal::YellowEW
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ew?
          @state = IntersectionSignal::GreenEWLeft
          @state_timer.duration = GreenLeftDuration.seconds
        when .green_ew_left?
          @state = IntersectionSignal::YellowEWLeft
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ew_left?
          @state = IntersectionSignal::GreenNS
          @state_timer.duration = GreenDuration.seconds
        end

        @state_timer.restart
        update_signal_frames
      end
      true
    end

    def update_signal_frames
      case @state
      when .green_ns?
        @signal_nb.show_green
        @signal_sb.show_green
        @signal_eb.show_red
        @signal_wb.show_red
      when .yellow_ns?
        @signal_nb.show_yellow
        @signal_sb.show_yellow
        @signal_eb.show_red
        @signal_wb.show_red
      when .green_ns_left?
        @signal_nb.show_red_turn_green
        @signal_sb.show_red_turn_green
        @signal_eb.show_red
        @signal_wb.show_red
      when .yellow_ns_left?
        @signal_nb.show_red_turn_yellow
        @signal_sb.show_red_turn_yellow
        @signal_eb.show_red
        @signal_wb.show_red
      when .green_ew?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_green
        @signal_wb.show_green
      when .yellow_ew?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_yellow
        @signal_wb.show_yellow
      when .green_ew_left?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_red_turn_green
        @signal_wb.show_red_turn_green
      when .yellow_ew_left?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_red_turn_yellow
        @signal_wb.show_red_turn_yellow
      when .all_red?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_red
        @signal_wb.show_red
      end
    end

    def toggle
      case @state
      when .green_ns?
        puts "Forcing NS Yellow..."
        @state = IntersectionSignal::YellowNS
        @state_timer.duration = YellowDuration.seconds
      when .green_ns_left?
        puts "Forcing NS Left Yellow..."
        @state = IntersectionSignal::YellowNSLeft
        @state_timer.duration = YellowDuration.seconds
      when .green_ew?
        puts "Forcing EW Yellow..."
        @state = IntersectionSignal::YellowEW
        @state_timer.duration = YellowDuration.seconds
      when .green_ew_left?
        puts "Forcing EW Left Yellow..."
        @state = IntersectionSignal::YellowEWLeft
        @state_timer.duration = YellowDuration.seconds
      else
        return
      end

      @state_timer.restart
      update_signal_frames
    end

    def clicked?(mx, my)
      mx >= @x && mx < @x + IntersectionSize && my >= @y && my < @y + IntersectionSize
    end

    def draw(draw : GSDL::Draw)
      @signal_nb.z_index = z_index
      @signal_eb.z_index = z_index
      @signal_sb.z_index = z_index
      @signal_wb.z_index = z_index
      super(draw)
    end
  end
end
