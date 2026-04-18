module Traffic
  class TrafficSignal < GSDL::AnimatedSprite
    def initialize(key : String, x, y, rotation = 0.0_f32)
      super(key, 16, 64, x, y)
      self.rotation = rotation

      # Setup a dummy animation so frame_index works for all 4 frames
      add("static", [0, 1, 2, 3], fps: 1)
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

    def show_red_turn_green
      self.frame = 2
    end

    def show_red_turn_yellow
      self.frame = 3
    end

    # Assuming frame 3 (Red + Turn Yellow) is the fallback for "Red"
    # if no specific Red frame exists, or perhaps it's intended
    # to be used when the other side is Green.
    def show_red
      self.frame = 3
    end
  end
end
