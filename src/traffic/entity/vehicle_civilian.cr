require "./vehicle"

module Traffic
  class VehicleCivilian < Vehicle
    FrustrationRate = 0.5_f32

    @frustration : Float32 = 0.0_f32
    @honk_timer : GSDL::Timer
    @rage_cooldown : GSDL::Timer

    def initialize(direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      super
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
        bar_x, bar_y = self.x - cam_x - (bar_w / 2.0_f32), self.y - cam_y - (th / 2.0_f32) - 12.0_f32
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w, bar_h), GSDL::Color.new(30, 30, 30, 150), z_index + 1)
        percent = Math.min(1.0_f32, @frustration / PatienceThresholds::ROAD_RAGE)
        color = road_rage? ? GSDL::Color.new(255, 50, 50) : (frustrated? ? GSDL::Color.new(255, 120, 50) : (anxious? ? GSDL::Color.new(255, 255, 50) : GSDL::Color.new(100, 255, 100)))
        draw.rect_fill(GSDL::FRect.new(bar_x, bar_y, bar_w * percent, bar_h), color, z_index + 2)
        draw.rect_fill(GSDL::FRect.new(bar_x + bar_w + 4, bar_y - 4, 8, 14), GSDL::Color.new(255, 0, 0), z_index + 3) if road_rage?
      end
    end
  end
end
