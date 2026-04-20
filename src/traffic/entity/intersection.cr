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
    AllRedNS
    AllRedEW
  end

  class Intersection < GSDL::Entity
    property state : IntersectionSignal = IntersectionSignal::GreenNS
    getter tile_x : Int32
    getter tile_y : Int32
    property? selected : Bool = false

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
    @signal_hud : GSDL::AnimatedSprite

    @flip_button : GSDL::Button
    @next_button : GSDL::Button

    @flipped : Bool = false
    @flipped_to_left : Bool = false
    getter? input_consumed : Bool = false
    getter? flip_disabled : Bool = false

    def initialize(@tile_x, @tile_y)
      @x = @tile_x * TileSize
      @y = @tile_y * TileSize
      @state = IntersectionSignal::GreenNSLeft
      @state_timer = GSDL::Timer.new(GreenLeftDuration.seconds)
      @state_timer.start

      # signal gfx
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

      # signal HUD
      @signal_hud = GSDL::AnimatedSprite.new("traffic-signal-hud", 256, 256)

      @signal_hud.add("GreenNSLeft", [0], fps: 0)
      @signal_hud.add("YellowNSLeft", [1], fps: 0)
      @signal_hud.add("GreenNS", [2], fps: 0)
      @signal_hud.add("YellowNS", [3], fps: 0)
      @signal_hud.add("AllRedNS", [4], fps: 0)
      @signal_hud.add("GreenEWLeft", [5], fps: 0)
      @signal_hud.add("YellowEWLeft", [6], fps: 0)
      @signal_hud.add("GreenEW", [7], fps: 0)
      @signal_hud.add("YellowEW", [8], fps: 0)
      @signal_hud.add("AllRedEW", [9], fps: 0)
      # z-index, intersection tile is -10 so just add a few just in case, -5 is draw_selected_vehicle_path
      @signal_hud.z_index = -8

      # Buttons
      @flip_button = GSDL::Button.new(
        on_click: ->(s : String) { flip },
        font: GSDL::Font.default(48.0_f32),
        text: "FLIP",
        x: GSDL::Game.width,
        y: GSDL::Game.height,
        padding_x: 16,
        padding_y: 8,
        origin: {1_f32, 1_f32},
        scale: {0.5_f32, 0.5_f32},
        draw_relative_to_camera: false,
      )
      @flip_button.x = GSDL::Game.width - 16_f32

      @next_button = GSDL::Button.new(
        on_click: ->(s : String) { toggle },
        font: GSDL::Font.default(48.0_f32),
        text: "CYCLE",
        x: GSDL::Game.width,
        y: GSDL::Game.height,
        padding_x: 16,
        padding_y: 8,
        origin: {1_f32, 1_f32},
        scale: {0.5_f32, 0.5_f32},
        draw_relative_to_camera: false,
      )
      @next_button.x = @flip_button.x - @flip_button.width / 2_f32 - 16


      # NOTE: add_child needs to go after any @var intialization
      add_child(@signal_nb)
      add_child(@signal_eb)
      add_child(@signal_sb)
      add_child(@signal_wb)
      add_child(@signal_hud)

      update_signal_frames
    end

    def update(dt : Float32)
      @input_consumed = false
      @flip_disabled = false
      return unless super(dt)

      if selected?
        # NEXT Button Hover Effect
        if GSDL::Mouse.in?(@next_button.screen_x, @next_button.screen_y, @next_button.screen_width, @next_button.screen_height)
          @next_button.color = GSDL::ColorScheme.get(:ui_hover)
        else
          @next_button.color = GSDL::ColorScheme.get(:ui_text)
        end

        # FLIP Button Hover Effect
        if GSDL::Mouse.in?(@flip_button.screen_x, @flip_button.screen_y, @flip_button.screen_width, @flip_button.screen_height)
          @flip_button.color = GSDL::ColorScheme.get(:ui_hover)
        else
          @flip_button.color = GSDL::ColorScheme.get(:ui_text)
        end

        @flip_button.update(dt)
        @next_button.update(dt)
      end

      update_auto_signal

      true
    end

    def update_auto_signal
      if @state_timer.done?
        case @state
        when .green_ns_left?
          @state = IntersectionSignal::YellowNSLeft
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ns_left?
          if @flipped
            @state = IntersectionSignal::AllRedNS
            @state_timer.duration = RedDuration.seconds
          else
            @state = IntersectionSignal::GreenNS
            @state_timer.duration = GreenDuration.seconds
          end
        when .green_ns?
          @state = IntersectionSignal::YellowNS
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ns?
          @state = IntersectionSignal::AllRedNS
          @state_timer.duration = RedDuration.seconds
        when .all_red_ns?
          if @flipped
            if @flipped_to_left
              @state = IntersectionSignal::GreenEWLeft
              @state_timer.duration = GreenLeftDuration.seconds
            else
              @state = IntersectionSignal::GreenEW
              @state_timer.duration = GreenDuration.seconds
            end
            @flipped = false
          else
            @state = IntersectionSignal::GreenEWLeft
            @state_timer.duration = GreenLeftDuration.seconds
          end
        when .green_ew_left?
          @state = IntersectionSignal::YellowEWLeft
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ew_left?
          if @flipped
            @state = IntersectionSignal::AllRedEW
            @state_timer.duration = RedDuration.seconds
          else
            @state = IntersectionSignal::GreenEW
            @state_timer.duration = GreenDuration.seconds
          end
        when .green_ew?
          @state = IntersectionSignal::YellowEW
          @state_timer.duration = YellowDuration.seconds
        when .yellow_ew?
          @state = IntersectionSignal::AllRedEW
          @state_timer.duration = RedDuration.seconds
        when .all_red_ew?
          if @flipped
            if @flipped_to_left
              @state = IntersectionSignal::GreenNSLeft
              @state_timer.duration = GreenLeftDuration.seconds
            else
              @state = IntersectionSignal::GreenNS
              @state_timer.duration = GreenDuration.seconds
            end
            @flipped = false
          else
            @state = IntersectionSignal::GreenNSLeft
            @state_timer.duration = GreenLeftDuration.seconds
          end
        end

        @state_timer.restart
        update_signal_frames
      end
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
      when .all_red_ns?, .all_red_ew?
        @signal_nb.show_red
        @signal_sb.show_red
        @signal_eb.show_red
        @signal_wb.show_red
      end

      @signal_hud.play(@state.to_s)
    end

    def toggle
      @input_consumed = true
      case @state
      when .green_ns?
        # puts "Forcing NS Yellow..."
        @state = IntersectionSignal::YellowNS
        @state_timer.duration = YellowDuration.seconds
      when .green_ns_left?
        # puts "Forcing NS Left Yellow..."
        @state = IntersectionSignal::YellowNSLeft
        @state_timer.duration = YellowDuration.seconds
      when .green_ew?
        # puts "Forcing EW Yellow..."
        @state = IntersectionSignal::YellowEW
        @state_timer.duration = YellowDuration.seconds
      when .green_ew_left?
        # puts "Forcing EW Left Yellow..."
        @state = IntersectionSignal::YellowEWLeft
        @state_timer.duration = YellowDuration.seconds
      else
        return
      end

      GSDL::AudioManager.get("ding").play
      @state_timer.restart
      update_signal_frames
    end

    def flip
      @input_consumed = true
      if @flipped || @state.yellow_ns? || @state.yellow_ns_left? || @state.yellow_ew? || @state.yellow_ew_left?
        @flip_disabled = true
        return
      end

      case @state
      when .green_ns?
        @state = IntersectionSignal::YellowNS
        @state_timer.duration = YellowDuration.seconds
        @flipped = true
        @flipped_to_left = false
      when .green_ns_left?
        @state = IntersectionSignal::YellowNSLeft
        @state_timer.duration = YellowDuration.seconds
        @flipped = true
        @flipped_to_left = true
      when .green_ew?
        @state = IntersectionSignal::YellowEW
        @state_timer.duration = YellowDuration.seconds
        @flipped = true
        @flipped_to_left = false
      when .green_ew_left?
        @state = IntersectionSignal::YellowEWLeft
        @state_timer.duration = YellowDuration.seconds
        @flipped = true
        @flipped_to_left = true
      else
        @flip_disabled = true
        return # Ignore AllRedNS, AllRedEW or states already in transition
      end

      GSDL::AudioManager.get("ding").play
      @state_timer.restart
      update_signal_frames
    end

    def clicked_any_button?(mx, my) : Bool
      return false unless selected?
      return true if GSDL::Mouse.in?(mx, my, @flip_button.screen_x, @flip_button.screen_y, @flip_button.screen_width, @flip_button.screen_height)
      return true if GSDL::Mouse.in?(mx, my, @next_button.screen_x, @next_button.screen_y, @next_button.screen_width, @next_button.screen_height)
      false
    end

    def clicked?(mx, my)
      mx >= @x && mx < @x + IntersectionSize && my >= @y && my < @y + IntersectionSize
    end

    def draw(draw : GSDL::Draw)
      if selected?
        padding = TileSize / 4.0_f32
        GSDL::Box.new(
          x: @x - padding,
          y: @y - padding,
          width: IntersectionSize + padding * 2,
          height: IntersectionSize + padding * 2,
          color: GSDL::ColorScheme.get(:highlight_alt),
          z_index: -9
        ).draw(draw)
      end

      super(draw)

      if selected?
        @flip_button.draw(draw)
        @next_button.draw(draw)
      end
    end
  end
end
