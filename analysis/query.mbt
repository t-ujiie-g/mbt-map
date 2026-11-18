///|
/// An index over the features' boxes (`bbox`); features without geometry get
/// an inverted box that no search finds.
pub fn Index::of_table(t : @geom.Table) -> Index {
  let index = Index::new(t.length())
  for f in 0..<t.length() {
    let (x0, y0, x1, y1) = bbox(t, f)
    index.add(x0, y0, x1, y1) |> ignore
  }
  index.finish() |> ignore
  index
}

///|
/// Calls `f` with each point of Point and MultiPoint feature `i`.
fn each_point(t : @geom.Table, i : Int32, f : (Double, Double) -> Bool) -> Unit {
  guard t.kinds[i] is (Point | MultiPoint) else { return }
  let (a, b) = t.feature_points(i)
  for p in a..<b {
    if !f(t.coords[p * 2], t.coords[p * 2 + 1]) {
      return
    }
  }
}

///|
/// Whether (x, y) is in any polygon of `polygons` among `candidates`.
fn in_any(
  polygons : @geom.Table,
  candidates : Array[Int32],
  x : Double,
  y : Double,
) -> Bool {
  for f in candidates {
    if contains_point(polygons, f, x, y) {
      return true
    }
  }
  false
}

///|
/// Point and MultiPoint features of `points` with a point in or on some polygon
/// of `polygons` (Turf's `pointsWithinPolygon`, keeping whole features), in
/// order; `index` is `Index::of_table(polygons)`.
pub fn points_within(
  points : @geom.Table,
  polygons : @geom.Table,
  index : Index,
) -> Array[Int32] {
  let out = []
  let candidates = []
  for i in 0..<points.length() {
    let mut inside = false
    each_point(points, i, (x, y) => {
      candidates.clear()
      index.search(x, y, x, y, candidates)
      inside = in_any(polygons, candidates, x, y)
      !inside
    })
    if inside {
      out.push(i)
    }
  }
  out
}

///|
/// Per feature of `t` with a geometry, up to `k` items of `index` by box distance from the
/// center of its box within `max_distance`, nearest first: pairs of the feature and an item.
pub fn nearest_pairs(
  t : @geom.Table,
  index : Index,
  k~ : Int32 = 1,
  max_distance~ : Double = @double.infinity,
) -> Array[Int32] {
  let out = []
  let near = []
  for f in 0..<t.length() {
    let (x0, y0, x1, y1) = bbox(t, f)
    guard x0 <= x1 else { continue }
    near.clear()
    index.neighbors(
      (x0 + x1) / 2.0,
      (y0 + y1) / 2.0,
      near,
      max_results=k,
      max_distance~,
    )
    for item in near {
      out.push(f)
      out.push(item)
    }
  }
  out
}

///|
/// Most cells `grid_count` fills.
const MAX_GRID_CELLS : Int32 = 1 << 24

///|
/// Point counts of a `cols` x `rows` grid over the box, row by row from
/// `min_y`; points on the max edges fall in the last cells, points outside
/// are left out. None for an empty box or more than `MAX_GRID_CELLS` cells.
pub fn grid_count(
  t : @geom.Table,
  min_x : Double,
  min_y : Double,
  max_x : Double,
  max_y : Double,
  cols : Int32,
  rows : Int32,
) -> FixedArray[Int32]? {
  if !(max_x > min_x && max_y > min_y) ||
    cols <= 0 ||
    rows <= 0 ||
    cols > MAX_GRID_CELLS / rows {
    return None
  }
  let out = FixedArray::make(cols * rows, 0)
  let w = (max_x - min_x) / cols.to_double()
  let h = (max_y - min_y) / rows.to_double()
  for i in 0..<t.length() {
    each_point(t, i, (x, y) => {
      if x >= min_x && x <= max_x && y >= min_y && y <= max_y {
        let c = @cmp.minimum(((x - min_x) / w).to_int(), cols - 1)
        let r = @cmp.minimum(((y - min_y) / h).to_int(), rows - 1)
        out[r * cols + c] += 1
      }
      true
    })
  }
  Some(out)
}
