module Traffic
  TileSize = 128.0_f32
  IntersectionSize = 2 * TileSize
  
  # Lane center offsets from road start (0 to 256)
  Lane1 = 32.0_f32
  Lane2 = 96.0_f32
  Lane3 = 160.0_f32
  Lane4 = 224.0_f32
  
  # Trigger/Detection Thresholds
  ThresholdTurn   = 0.125_f32 * TileSize # 16px
  LookAheadDist   = 0.15_f32 * TileSize
  SignalCheckDist = 0.25_f32 * TileSize
  
  # Patience
  module PatienceThresholds
    ANXIOUS    = 5.0_f32
    FRUSTRATED = 20.0_f32
    ROAD_RAGE  = 35.0_f32
  end
end
