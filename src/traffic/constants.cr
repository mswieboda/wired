module Traffic
  TileSize = 128.0_f32
  IntersectionSize = 2 * TileSize

  # Lane center offsets from road start (Proportional to TileSize)
  # Tile 1: 0.25 and 0.75 | Tile 2: 1.25 and 1.75
  LaneSegments = 8
  Lanes = 2
  Segments = Lanes * LaneSegments
  Lane1 = (5_f32 / Segments) * TileSize
  Lane2 = (12_f32 / Segments) * TileSize
  Lane3 = (20_f32 / Segments) * TileSize
  Lane4 = (27_f32 / Segments) * TileSize

  # Trigger/Detection Thresholds
  ThresholdTurn   = 0.125_f32 * TileSize
  LookAheadDist   = 0.15_f32 * TileSize
  SignalCheckDist = 0.25_f32 * TileSize
  SwitchZoneDist  = 2.5_f32 * TileSize

  # Patience
  module PatienceThresholds
    ANXIOUS    = 5.0_f32
    FRUSTRATED = 20.0_f32
    ROAD_RAGE  = 35.0_f32
  end
end
