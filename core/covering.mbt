///|
/// How many zoom levels deeper tiles of `tile_size` pixels (a power of two up to
/// `TILE_SIZE`) are than `TILE_SIZE` ones at the same camera zoom.
pub fn zoom_shift(tile_size : Int32) -> Int32 {
  let mut shift = 0
  while shift < 8 && tile_size << shift < TILE_SIZE.to_int() {
    shift += 1
  }
  shift
}

///|
/// Integer tile zoom for a source with tiles of `tile_size` pixels (a power of
/// two up to `TILE_SIZE`: 256-pixel tiles take one zoom more), limited to the
/// source's zoom range (higher camera zooms overzoom `max_tile_zoom`).
pub fn Transform::tile_zoom(
  self : Transform,
  min_tile_zoom : Int32,
  max_tile_zoom : Int32,
  tile_size~ : Int32 = 512,
) -> Int32 {
  let z = self.camera.zoom.floor().to_int() + zoom_shift(tile_size)
  @cmp.maximum(min_tile_zoom, @cmp.minimum(max_tile_zoom, z))
}

///|
/// How far from the camera tiles stay at the full tile zoom, in camera
/// distances; each doubling beyond it drops one zoom level. 1.5 keeps every
/// tile of an unpitched view with an aspect ratio up to about 3 at full zoom.
const LOD_DISTANCE : Double = 1.5

///|
/// Zoom levels below a source's `min_z` that distant ground may want and still
/// be drawn from `min_z` tiles; farther ground is left to the fog.
const MIN_ZOOM_SLACK : Int32 = 2

///|
/// Most world copies drawn either side of the main one, as MapLibre's
/// `coveringTiles` (three).
pub const MAX_WORLD_COPIES : Int32 = 3

///|
/// The world copies the view's ground reaches (`wrap` -1 is the copy west of
/// the main one, x in [-1, 0]); only the main one without `world_copies`.
pub fn Transform::wraps(self : Transform) -> (Int32, Int32) {
  if !self.limits.world_copies {
    return (0, 0)
  }
  let mut x0 = @double.infinity
  let mut x1 = @double.neg_infinity
  for m in self.base_footprint() {
    x0 = @cmp.minimum(x0, m.x)
    x1 = @cmp.maximum(x1, m.x)
  }
  let clamp = (x : Double) => {
    @cmp.maximum(
      -MAX_WORLD_COPIES,
      @cmp.minimum(MAX_WORLD_COPIES, x.floor().to_int()),
    )
  }
  (clamp(x0), clamp(x1))
}

///|
/// The footprint on ground between sea level and the center's height.
fn Transform::base_footprint(self : Transform) -> Array[MercatorCoord] {
  self.footprint(
    @cmp.minimum(0.0, self.elevation),
    @cmp.maximum(0.0, self.elevation),
  )
}

///|
/// Non-overlapping tiles over the view and the world copies it reaches, nearest the center first:
/// `max_z` near the camera, lower zooms down to `min_z` (none past `MIN_ZOOM_SLACK` below), on
/// ground between each tile's `heights` in meters (sea level and the center's).
pub fn Transform::covering_tiles(
  self : Transform,
  min_z : Int32,
  max_z : Int32,
  heights? : (TileId) -> (Double, Double),
) -> Array[UnwrappedTile] {
  let ws = self.world_size()
  let center = self.camera.center.to_mercator()
  let footprint = self.base_footprint()
  // The camera's ground position and height, in world pixels from the center.
  let d = center_distance(self.height)
  let pitch = radians(self.camera.pitch)
  let bearing = radians(self.camera.bearing)
  let behind = d * @math.sin(pitch)
  let cam_x = -@math.sin(bearing) * behind
  let cam_y = @math.cos(bearing) * behind
  let cam_z = d * @math.cos(pitch)
  let tiles : Array[UnwrappedTile] = []
  let distances : Array[Double] = []
  let (first, last) = self.wraps()
  for wrap in first..<=last {
    // Each copy is walked in the main world's units, the view moved by `wrap` worlds.
    let shift = wrap.to_double()
    let moved = (poly : Array[MercatorCoord]) => {
      poly.map(p => ({ x: p.x - shift, y: p.y, } : MercatorCoord))
    }
    let base = moved(footprint)
    let c : MercatorCoord = { x: center.x - shift, y: center.y, }
    let stack : Array[TileId] = [{ z: 0, x: 0, y: 0, }]
    while stack.pop() is Some(tile) {
      let b = tile.mercator_bounds()
      let ground = match heights {
        Some(f) => {
          let (lo, hi) = f(tile)
          moved(self.footprint(lo, hi))
        }
        None => base
      }
      if !overlaps(ground, b) {
        continue
      }
      // Distance from the camera to the tile's nearest ground point.
      let nx = (
          @cmp.maximum(b.min_x, @cmp.minimum(b.max_x, c.x + cam_x / ws)) - c.x
        ) *
        ws -
        cam_x
      let ny = (
          @cmp.maximum(b.min_y, @cmp.minimum(b.max_y, c.y + cam_y / ws)) - c.y
        ) *
        ws -
        cam_y
      let dist = (nx * nx + ny * ny + cam_z * cam_z).sqrt()
      let near = (levels : Int32) => {
        dist < LOD_DISTANCE * d * @math.pow(2.0, levels.to_double())
      }
      let split = if tile.z < min_z {
        if !near(max_z - min_z + MIN_ZOOM_SLACK) {
          continue
        }
        true
      } else {
        tile.z < max_z && near(max_z - tile.z - 1)
      }
      if split && tile.children() is Some(kids) {
        for k in kids {
          stack.push(k)
        }
      } else {
        let dx = (b.min_x + b.max_x) / 2.0 - c.x
        let dy = (b.min_y + b.max_y) / 2.0 - c.y
        tiles.push({ id: tile, wrap, })
        distances.push(dx * dx + dy * dy)
      }
    }
  }
  // `stable_order` rather than a sort instantiated for the tile type (bundle size).
  stable_order(distances[:]).iter().map(i => tiles[i]).to_array()
}

///|
/// Whether the convex polygon `poly` and the box `b` intersect: no separating
/// axis among the box's axes and the polygon's edge normals.
fn overlaps(poly : Array[MercatorCoord], b : BBox) -> Bool {
  let n = poly.length()
  // Box axes: the polygon's extent against the box's.
  let mut x0 = poly[0].x
  let mut x1 = x0
  let mut y0 = poly[0].y
  let mut y1 = y0
  for p in poly {
    x0 = @cmp.minimum(x0, p.x)
    x1 = @cmp.maximum(x1, p.x)
    y0 = @cmp.minimum(y0, p.y)
    y1 = @cmp.maximum(y1, p.y)
  }
  if x1 < b.min_x || x0 > b.max_x || y1 < b.min_y || y0 > b.max_y {
    return false
  }
  if n < 3 {
    return true
  }
  // Edge normals: the box lies wholly outside an edge if even its corner
  // farthest along the inward normal is outside. `poly` turns one way, so
  // the sign of `turn` says which side is inside.
  let turn = (poly[1].x - poly[0].x) * (poly[2].y - poly[1].y) -
    (poly[1].y - poly[0].y) * (poly[2].x - poly[1].x)
  for i in 0..<n {
    let p = poly[i]
    let q = poly[(i + 1) % n]
    // Inward normal of edge p -> q.
    let (nx, ny) = if turn > 0.0 {
      (p.y - q.y, q.x - p.x)
    } else {
      (q.y - p.y, p.x - q.x)
    }
    let cx = if nx > 0.0 { b.max_x } else { b.min_x }
    let cy = if ny > 0.0 { b.max_y } else { b.min_y }
    if (cx - p.x) * nx + (cy - p.y) * ny < 0.0 {
      return false
    }
  }
  true
}

///|
/// The view's footprint (Mercator, convex) on ground between `lo` and `hi`
/// meters: the screen corners' rays (the top ones at the horizon line) met at
/// both heights, those above the camera just below it.
fn Transform::footprint(
  self : Transform,
  lo : Double,
  hi : Double,
) -> Array[MercatorCoord] {
  let ws = self.world_size()
  let c = self.camera.center.to_mercator()
  let ppm = self.pixels_per_meter()
  let camera = self.elevation * ppm +
    center_distance(self.height) * @math.cos(radians(self.camera.pitch)) -
    1.0
  let z0 = @cmp.minimum(lo * ppm, camera)
  let z1 = @cmp.minimum(hi * ppm, camera)
  let top = @cmp.maximum(0.0, self.height / 2.0 - self.horizon())
  let points = []
  for i in 0..<(if z0 == z1 { 4 } else { 8 }) {
    let k = i % 4
    let (ax, ay, az, bx, by, bz) = self.screen_ray(
      if k == 1 || k == 2 {
        self.width
      } else {
        0.0
      },
      if k < 2 {
        top
      } else {
        self.height
      },
    )
    let z = if i < 4 { z0 } else { z1 }
    let t = (az - z) / (az - bz)
    points.push({
      x: c.x + (ax + (bx - ax) * t) / ws,
      y: c.y + (ay + (by - ay) * t) / ws,
    })
  }
  if z0 == z1 {
    points
  } else {
    convex_hull(points)
  }
}

///|
/// The convex hull of `points`, with no three corners in line (Jarvis's march;
/// a handful of points).
fn convex_hull(points : Array[MercatorCoord]) -> Array[MercatorCoord] {
  let n = points.length()
  let mut start = 0
  for i, p in points {
    let s = points[start]
    if p.x < s.x || (p.x == s.x && p.y < s.y) {
      start = i
    }
  }
  let hull = []
  let mut p = start
  while hull.length() < n {
    let o = points[p]
    hull.push(o)
    let mut q = (p + 1) % n
    let mut a = points[q]
    for r, b in points {
      let turn = (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
      // In line: the farther point, so no corner lies between two others.
      if turn < 0.0 ||
        (
          turn == 0.0 &&
          (b.x - o.x).abs() + (b.y - o.y).abs() >
          (a.x - o.x).abs() + (a.y - o.y).abs()
        ) {
        q = r
        a = b
      }
    }
    p = q
    if p == start {
      break
    }
  }
  hull
}
