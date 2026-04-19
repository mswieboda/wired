require "./vehicle"

module Traffic
  class VehiclePriority < Vehicle
    @time_to_destination : Float32 = 0.0_f32

    def initialize(direction : GSDL::Direction, x : Int32 | Float32, y : Int32 | Float32)
      super
      @time_to_destination = 60.0_f32
    end

    def priority? : Bool
      true
    end

    def skips_red_lights? : Bool
      true
    end

    def base_speed_range : Range(Float32, Float32)
      (400.0_f32)..(550.0_f32)
    end

    def update_special_behavior(dt : Float32, intersections : Array(Intersection), all_vehicles : Array(Vehicle))
      decay_rate = 1.0_f32
      decay_rate = is_waiting_on_wreck?(all_vehicles) ? 10.0_f32 : 3.0_f32 if @waiting
      @time_to_destination -= dt * decay_rate
      @time_to_destination = 0.0_f32 if @time_to_destination < 0
    end

    def tint_color : GSDL::Color
      @wrecked ? GSDL::Color.new(40, 40, 40) : GSDL::Color.new(0, 0, 255, 224)
    end

    def draw_status_overlay(draw : GSDL::Draw, th : Float32, cam_x : Float32, cam_y : Float32)
      # Priority-specific status (e.g. destination time) can be added here if needed
    end
  end
end
