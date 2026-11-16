///|
/// A turn and half a turn of longitude and the poles' latitude, in `DEGREE_SCALE` integers.
const TURN : Int64 = 3_600_000_000L

///|
const HALF_TURN : Int64 = 1_800_000_000L

///|
const POLE : Int64 = 900_000_000L

///|
/// The world copies either side of a ring's own that may reach ±180°: the
/// inputs' longitudes stay within 540° (`refusal`).
const MAX_COPIES : Int64 = 2L

///|
/// Whether a geodesic buffer by `meters` of a feature with box `w`, `s`, `e`, `n` may pass ±180°
/// or reach a pole: false only within 10° of its center and clear of both by three times the
/// distance (a miter's spike).
fn may_wrap(
  w : Double,
  s : Double,
  e : Double,
  n : Double,
  meters : Double,
) -> Bool {
  // 6.3e6 m is under the ellipsoid's smallest radius of curvature.
  let reach = degrees(meters.abs() * 3.0 / 6.3e6) * 1.1
  let half = ((e - w) * (e - w) + (n - s) * (n - s)).sqrt() / 2.0
  let lat = @cmp.maximum(n.abs(), s.abs()) + reach
  if !(half + reach <= 10.0 && lat <= 89.0) {
    return true
  }
  let lon = reach / @math.cos(radians(lat))
  !(w - lon > -180.0 && e + lon < 180.0)
}

///|
/// A longitude step in `DEGREE_SCALE` integers taken the short way round.
fn short_way(d : Int64) -> Int64 {
  if d > HALF_TURN {
    d - TURN
  } else if d < -HALF_TURN {
    d + TURN
  } else {
    d
  }
}

///|
/// The quotient of `a` by `TURN` rounded down.
fn turns_floor(a : Int64) -> Int64 {
  let q = a / TURN
  if a % TURN < 0L {
    q - 1L
  } else {
    q
  }
}

///|
/// A ring in `DEGREE_SCALE` integers, its longitudes continuous from its first point (each edge
/// the short way round): `turns` east around the axis before it closes, `wraps` if an edge
/// passed the meridian opposite the plane's center.
priv struct Lifted {
  path : Array[@clipper.Point64]
  turns : Int64
  wraps : Bool
}

///|
fn lift(
  ring : Array[@clipper.Point64],
  to_xy : (@clipper.Point64) -> (Double, Double),
) -> Lifted {
  let path : Array[@clipper.Point64] = Array(capacity=ring.length())
  let mut wraps = false
  let mut raw = 0L
  let mut lon = 0L
  for i, p in ring {
    let (x, y) = to_xy(p)
    let q = degree_int(x, y)
    if i == 0 {
      lon = q.x
    } else {
      let d = short_way(q.x - raw)
      wraps = wraps || d != q.x - raw
      lon += d
    }
    raw = q.x
    path.push({ x: lon, y: q.y, })
  }
  guard path.length() > 0 else { return { path, turns: 0L, wraps, } }
  let first = path[0].x
  let closing = short_way(first - raw)
  wraps = wraps || closing != first - raw
  { path, turns: (lon + closing - first) / TURN, wraps, }
}

///|
/// The copies of a ring spanning `min` to `max` that reach ±180°: the first
/// and last number of turns to shift it by (none if the first is larger).
fn copies(min : Int64, max : Int64) -> (Int64, Int64) {
  (
    @cmp.maximum(-MAX_COPIES, -turns_floor(max + HALF_TURN)),
    @cmp.minimum(MAX_COPIES, turns_floor(HALF_TURN - min)),
  )
}

///|
/// `path` moved east by `turns`.
fn shifted(
  path : Array[@clipper.Point64],
  turns : Int64,
) -> Array[@clipper.Point64] {
  path.map(p => { x: p.x + turns * TURN, y: p.y, })
}

///|
/// The world from -180° to 180°, counter-clockwise or clockwise.
fn world(ccw : Bool) -> Array[@clipper.Point64] {
  let ring : Array[@clipper.Point64] = [
    { x: -HALF_TURN, y: -POLE, },
    { x: HALF_TURN, y: -POLE, },
    { x: HALF_TURN, y: POLE, },
    { x: -HALF_TURN, y: POLE, },
  ]
  if ccw {
    ring
  } else {
    ring.rev()
  }
}

///|
/// The polygons of `root` (a geodesic buffer's plane: `to_xy` gives degrees, `north` is its north
/// pole) cut to ±180° of longitude in `DEGREE_SCALE` integers (RFC 7946 §3.1.9; the method is in
/// docs/dev/ARCHITECTURE-MODULES.md). None if nothing needs cutting or a ring turns twice.
fn cut_to_world(
  root : @clipper.PolyPath64,
  to_xy : (@clipper.Point64) -> (Double, Double),
  north : @clipper.Point64,
) -> @clipper.PolyPath64? {
  let subject = []
  let mut needed = false
  // How many times the polygons cover the north pole: a ring adds to the
  // winding on its inside, which its lifted copy shows as the side south of it
  // (around a pole) or as its outside (around both).
  let mut cover = 0
  let stack = [root.children]
  while stack.pop() is Some(nodes) {
    for node in nodes {
      stack.push(node.children)
      let ring = node.polygon
      let side = @clipper.area(ring[:])
      guard side != 0.0 else { continue }
      let sign = if side > 0.0 { 1 } else { -1 }
      let { path, turns, wraps, } = lift(ring, to_xy)
      let mut min = path[0].x
      let mut max = min
      for p in path {
        min = @cmp.minimum(min, p.x)
        max = @cmp.maximum(max, p.x)
      }
      needed = needed ||
        wraps ||
        turns != 0L ||
        min < -HALF_TURN ||
        max > HALF_TURN
      if turns == 0L {
        let (k0, k1) = copies(min, max)
        for k in k0..<=k1 {
          subject.push(shifted(path, k))
        }
        if (@clipper.area(path[:]) > 0.0) != (side > 0.0) &&
          @clipper.point_in_polygon(north, ring[:]) is IsInside {
          cover += sign
        }
        continue
      }
      guard turns == 1L || turns == -1L else { return None }
      if turns.to_int() == sign {
        cover += sign
      }
      // One path through every copy, closed along the south pole's latitude.
      let (k0, k1) = if turns > 0L {
        copies(min, max + TURN)
      } else {
        copies(min - TURN, max)
      }
      guard k0 <= k1 else { continue }
      let (first, last) = if turns > 0L { (k0, k1) } else { (k1, k0) }
      let long = []
      for j in 0L..<=(k1 - k0) {
        long.append(shifted(path, first + j * turns))
      }
      let end = path[0].x + (last + turns) * TURN
      long.push({ x: end, y: path[0].y, })
      long.push({ x: end, y: -POLE, })
      long.push({ x: path[0].x + first * TURN, y: -POLE, })
      subject.push(long)
    }
  }
  guard needed else { return None }
  for _ in 0..<cover.abs() {
    subject.push(world(cover > 0))
  }
  let c = @clipper.Clipper64::new()
  c.add_subject(subject)
  c.add_clip([world(true)])
  match c.execute_tree(Intersection, Positive) {
    Some((cut, _)) => Some(cut)
    None => None
  }
}
