module Traffic
  class TrafficSignal < GSDL::AnimatedSprite
    def initialize(key : String, x, y, origin = {0_f32, 0_f32})
      super(
        key: key,
        width: 16,
        height: 64,
        x: x,
        y: y,
        origin: origin,
      )

      # Setup a static animation so frame_index works for all 5 frames
      add("static", [0, 1, 2, 3, 4], fps: 1)
      play("static")
      @animation_player.pause
    end

    def frame=(index : Int32)
      @animation_player.frame_index = index
    end

    def show_green
      self.frame = 0
    end

    def show_yellow
      self.frame = 1
    end

    def show_red
      self.frame = 2
    end

    def show_red_full
      self.frame = 2
    end

    def show_red_turn_green
      self.frame = 3
    end

    def show_red_turn_yellow
      self.frame = 4
    end  end
end
