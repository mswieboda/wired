require "./vehicle"

module Traffic
  class VehicleCivilian < Vehicle
    FrustrationRate = 0.5_f32

    @frustration : Float32 = 0.0_f32
    @honk_timer : GSDL::Timer
    @rage_cooldown : GSDL::Timer

    def initialize(direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      super
      
      # Assign random paint color
      colors = [
        :car_red,
        :car_green,
        :car_blue,
        :car_yellow,
        :car_silver,
        :car_gray,
        :car_dark_green,
        :car_black,
        :car_dark_red,
        :car_teal,
        :car_dark_blue,
      ]

      @paint_color = GSDL::ColorScheme.get(colors.sample)
      @honk_timer = GSDL::Timer.new(Time::Span.new(seconds: Random.rand(4..8)))
      @honk_timer.start
      @rage_cooldown = GSDL::Timer.new(2.seconds)
    end

    def priority? : Bool
      false
    end

    def skips_red_lights? : Bool
      road_rage?
    end

    def base_speed_range : Range(Float32, Float32)
      (200.0_f32)..(350.0_f32)
    end

    def asset_prefix : String
      "car"
    end

    def update_special_behavior(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      update_frustration(dt)
    end

    def setup_animations(sprite : GSDL::AnimatedSprite, kind : Symbol)
      case kind
      when :eb
        sprite.add("idle", [0], fps: 0)
        sprite.add("blink_right", [2, 0], fps: 3)
        sprite.add("blink_left", [0], fps: 3)
        sprite.add("brake", [1], fps: 0)
        sprite.add("brake_blink_right", [3, 1], fps: 3)
        sprite.add("brake_blink_left", [1], fps: 0)
      when :wb
        sprite.add("idle", [0], fps: 0)
        sprite.add("blink_right", [0], fps: 0)
        sprite.add("blink_left", [2, 0], fps: 3)
        sprite.add("brake", [1], fps: 0)
        sprite.add("brake_blink_right", [1], fps: 0)
        sprite.add("brake_blink_left", [3, 0], fps: 3)
      when :nb
        sprite.add("idle", [0], fps: 0)
        sprite.add("blink_right", [1, 0], fps: 3)
        sprite.add("blink_left", [2, 0], fps: 3)
        sprite.add("brake", [3], fps: 0)
        sprite.add("brake_blink_right", [5, 3], fps: 3)
        sprite.add("brake_blink_left", [4, 3], fps: 3)
      when :sb
        sprite.add("idle", [0], fps: 0)
        sprite.add("blink_right", [2, 0], fps: 3)
        sprite.add("blink_left", [1, 0], fps: 3)
        sprite.add("brake", [0], fps: 0)
        sprite.add("brake_blink_right", [2, 0], fps: 3)
        sprite.add("brake_blink_left", [1, 0], fps: 3)
      end

      sprite.play("idle")
    end

    private def update_frustration(dt : Float32)
      if @waiting
        @frustration += dt * FrustrationRate
        if road_rage? && !@rage_cooldown.started?
          GSDL::AudioManager.get("rage_trigger").play; @rage_cooldown.start
        end

        if frustrated? && @honk_timer.done?
            GSDL::AudioManager.get("honk").play; @honk_timer.duration = Time::Span.new(seconds: Random.rand(4..8)); @honk_timer.restart
        end
      else
        unless road_rage? && @rage_cooldown.running?
          @frustration -= dt * 8.0; @frustration = 0.0 if @frustration < 0
        end
      end
    end

    def patient?
      @frustration < PatienceThresholds::ANXIOUS
    end

    def anxious?
      @frustration >= PatienceThresholds::ANXIOUS && @frustration < PatienceThresholds::FRUSTRATED
    end

    def frustrated?
      @frustration >= PatienceThresholds::FRUSTRATED && @frustration < PatienceThresholds::ROAD_RAGE
    end

    def road_rage?
      @frustration >= PatienceThresholds::ROAD_RAGE
    end

    def draw_status_overlay(draw : GSDL::Draw, th : Float32, cam_x : Float32, cam_y : Float32)
      unless @wrecked || patient?
        bar_w, bar_h = 40.0_f32, 6.0_f32
        bar_x, bar_y = self.x - (bar_w / 2.0_f32), self.y - (th / 2.0_f32) - 12.0_f32
        
        # Background
        GSDL::Box.new(
          width: bar_w,
          height: bar_h,
          x: bar_x,
          y: bar_y,
          color: GSDL::Color.new(30, 30, 30, 150),
          z_index: z_index + 1
        ).draw(draw)
        
        percent = Math.min(1.0_f32, @frustration / PatienceThresholds::ROAD_RAGE)
        color = road_rage? ? GSDL::Color.new(255, 50, 50) : (frustrated? ? GSDL::Color.new(255, 120, 50) : (anxious? ? GSDL::Color.new(255, 255, 50) : GSDL::Color.new(100, 255, 100)))
        
        # Fill
        GSDL::Box.new(
          width: bar_w * percent,
          height: bar_h,
          x: bar_x,
          y: bar_y,
          color: color,
          z_index: z_index + 2
        ).draw(draw)

        if road_rage?
          GSDL::Box.new(
            width: 8,
            height: 14,
            x: bar_x + bar_w + 4,
            y: bar_y - 4,
            color: GSDL::Color.new(255, 0, 0),
            z_index: z_index + 3
          ).draw(draw)
        end
      end
    end
  end
end
