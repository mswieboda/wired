module Traffic
  enum NodeType
    Intersection
    Exit
    TargetAmbulance
    TargetPolice
    TargetVIP
  end

  class Node
    property x : Float32
    property y : Float32
    property type : NodeType
    property connections = Array(Node).new
    property sprite_offset_x : Float32 = 0.0_f32
    property sprite_offset_y : Float32 = 0.0_f32

    def initialize(@x, @y, @type, @sprite_offset_x = 0.0_f32, @sprite_offset_y = 0.0_f32)
    end

    def distance_to(other : Node)
      distance_to(other.x, other.y)
    end

    def distance_to(ox : Float32, oy : Float32)
      Math.sqrt((@x - ox)**2 + (@y - oy)**2)
    end
  end

  class NodeGraph
    property nodes = Array(Node).new

    def build(map : GSDL::TileMap, intersections : Array(Intersection))
      @nodes.clear

      # 1. Add Intersection Nodes
      intersections.each do |inter|
        # Center of intersection (2x2 tiles)
        @nodes << Node.new(inter.x + TileSize, inter.y + TileSize, NodeType::Intersection)
      end

      # 2. Add Target Nodes from Object Layer
      map.layers.each do |layer|
        if layer.is_a?(GSDL::ObjectGroup)
          layer.objects.each do |obj|
            type = case obj.type
                   when "TargetAmbulance" then NodeType::TargetAmbulance
                   when "TargetPolice"    then NodeType::TargetPolice
                   when "TargetVIP"       then NodeType::TargetVIP
                   else next
                   end
            
            ox = obj.properties["sprite_tile_offset_x"]?.try(&.as_f.to_f32) || 0.0_f32
            oy = obj.properties["sprite_tile_offset_y"]?.try(&.as_f.to_f32) || 0.0_f32
            
            @nodes << Node.new(obj.x, obj.y, type, ox, oy)
          end
        end
      end

      # 3. Add Exit Nodes at Map Edges
      # North/South
      (0...map.map_width_tiles).each do |tx|
        if is_road?(map, tx, 0)
          @nodes << Node.new(tx * TileSize + (TileSize / 2), -TileSize, NodeType::Exit)
        end
        if is_road?(map, tx, map.map_height_tiles - 1)
          @nodes << Node.new(tx * TileSize + (TileSize / 2), map.height + TileSize, NodeType::Exit)
        end
      end
      # East/West
      (0...map.map_height_tiles).each do |ty|
        if is_road?(map, 0, ty)
          @nodes << Node.new(-TileSize, ty * TileSize + (TileSize / 2), NodeType::Exit)
        end
        if is_road?(map, map.map_width_tiles - 1, ty)
          @nodes << Node.new(map.width + TileSize, ty * TileSize + (TileSize / 2), NodeType::Exit)
        end
      end

      # puts "NodeGraph: Built #{@nodes.size} nodes."

      # 4. Connect Nodes (Only if directly adjacent)
      conn_count = 0
      @nodes.each do |node_a|
        @nodes.each do |node_b|
          next if node_a == node_b
          next if node_a.connections.includes?(node_b)

          if connected_by_road?(map, node_a, node_b)
            # CHECK: Is there any other node between A and B?
            has_node_between = @nodes.any? do |node_mid|
              next if node_mid == node_a || node_mid == node_b
              
              # Is node_mid on the line between A and B?
              on_line = false
              dx_ab = (node_a.x - node_b.x).abs
              dy_ab = (node_a.y - node_b.y).abs
              
              if dx_ab < 5.0 # Vertical road
                if (node_mid.x - node_a.x).abs < 5.0
                  min_y, max_y = {node_a.y, node_b.y}.minmax
                  on_line = node_mid.y > min_y && node_mid.y < max_y
                end
              elsif dy_ab < 5.0 # Horizontal road
                if (node_mid.y - node_a.y).abs < 5.0
                  min_x, max_x = {node_a.x, node_b.x}.minmax
                  on_line = node_mid.x > min_x && node_mid.x < max_x
                end
              end
              on_line
            end

            unless has_node_between
              node_a.connections << node_b
              node_b.connections << node_a # Assuming two-way roads for now
              conn_count += 1
            end
          end
        end
      end

      # puts "NodeGraph: Created #{conn_count} connections."
    end

    private def is_road?(map, tx, ty)
      tile = map.tile_at(tx, ty)
      return false unless tile

      # GID range (current tileset)
      gid = tile.local_tile_id + 1
      # Based on tiles.png: 1-16 are road/intersections
      gid >= 1 && gid <= 16
    end

    private def connected_by_road?(map, a, b)
      # Check if aligned
      dx = (a.x - b.x).abs
      dy = (a.y - b.y).abs
      # Lenient threshold to handle 2-tile wide roads and offsets
      threshold = TileSize + 2.0_f32

      if dx < threshold
        # Vertical connection
        mid_x = (a.x + b.x) / 2.0_f32
        min_y = Math.min(a.y, b.y)
        max_y = Math.max(a.y, b.y)
        # Scan along Y, clamping to map boundaries
        y = Math.max(0.0_f32, min_y + TileSize)
        limit = Math.min(map.height.to_f32 - 1.0_f32, max_y)
        while y < limit
          return false unless is_road_at?(map, mid_x, y)
          y += TileSize
        end
        return true
      elsif dy < threshold
        # Horizontal connection
        mid_y = (a.y + b.y) / 2.0_f32
        min_x = Math.min(a.x, b.x)
        max_x = Math.max(a.x, b.x)
        # Scan along X, clamping to map boundaries
        x = Math.max(0.0_f32, min_x + TileSize)
        limit = Math.min(map.width.to_f32 - 1.0_f32, max_x)
        while x < limit
          return false unless is_road_at?(map, x, mid_y)
          x += TileSize
        end
        return true
      end

      false
    end

    private def is_road_at?(map, x, y)
      tx = (x // TileSize).to_i
      ty = (y // TileSize).to_i
      is_road?(map, tx, ty)
    end
  end
end
