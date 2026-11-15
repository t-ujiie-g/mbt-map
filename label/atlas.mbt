///|
/// Rectangles for glyph bitmaps in a texture of `width` x `height`, packed in
/// shelves as they come, each with `GLYPH_PADDING` blank pixels around it (as
/// MapLibre's `GlyphAtlas`); a glyph keeps its place once given one.
pub struct Atlas {
  width : Int32
  height : Int32
  priv shelves : Array[(Int32, Int32, Int32)]
  priv rects : Map[Int32, (Int32, Int32, Int32, Int32)]
}

///|
/// Blank pixels around each glyph bitmap, which its rectangle and quad include.
const GLYPH_PADDING : Int32 = 1

///|
pub fn Atlas::new(width : Int32, height : Int32) -> Atlas {
  { width, height, shelves: [], rects: Map([]), }
}

///|
/// Glyph `cp`'s rectangle (x, y, width, height) with its padding, if it has one.
pub fn Atlas::rect(self : Atlas, cp : Int32) -> (Int32, Int32, Int32, Int32)? {
  self.rects.get(cp)
}

///|
/// Where glyph `cp`'s bitmap goes, inside its rectangle's padding, if it has one.
pub fn Atlas::bitmap_at(self : Atlas, cp : Int32) -> (Int32, Int32)? {
  match self.rects.get(cp) {
    Some((x, y, _, _)) => Some((x + GLYPH_PADDING, y + GLYPH_PADDING))
    None => None
  }
}

///|
/// Places glyph `cp` of `w` x `h` pixels and returns where its bitmap goes; None when
/// the atlas is full (or the glyph already has a place, which stays as it was).
pub fn Atlas::place(
  self : Atlas,
  cp : Int32,
  w : Int32,
  h : Int32,
) -> (Int32, Int32)? {
  if self.rects.contains(cp) || w <= 0 || h <= 0 {
    return None
  }
  let cw = w + 2 * GLYPH_PADDING
  let ch = h + 2 * GLYPH_PADDING
  // The shortest shelf it fits, (y, height, used width) each.
  let mut best = -1
  for i, s in self.shelves {
    if s.1 >= ch &&
      s.2 + cw <= self.width &&
      (best < 0 || s.1 < self.shelves[best].1) {
      best = i
    }
  }
  if best < 0 {
    let top = match self.shelves.last() {
      Some(s) => s.0 + s.1
      None => 0
    }
    if top + ch > self.height || cw > self.width {
      return None
    }
    self.shelves.push((top, ch, 0))
    best = self.shelves.length() - 1
  }
  let (y, sh, used) = self.shelves[best]
  self.shelves[best] = (y, sh, used + cw)
  self.rects[cp] = (used, y, cw, ch)
  Some((used + GLYPH_PADDING, y + GLYPH_PADDING))
}

///|
/// Padded pixels a glyph of `w` x `h` takes in an atlas.
fn padded_area(w : Int32, h : Int32) -> Int64 {
  (w + 2 * GLYPH_PADDING).to_int64() * (h + 2 * GLYPH_PADDING).to_int64()
}

///|
/// Places every glyph of `glyphs` (key, width, height); false if some did not fit.
fn Atlas::place_all(
  self : Atlas,
  glyphs : Array[(Int32, Int32, Int32)],
) -> Bool {
  let mut fits = true
  for g in glyphs {
    if self.place(g.0, g.1, g.2) is None && g.1 > 0 && g.2 > 0 {
      fits = false
    }
  }
  fits
}

///|
/// A square atlas of `glyphs` (key, width, height), tallest first: the smallest side from
/// `side` doubling to `max` that they fill at most half of (so rebuilds stay rare) and all
/// fit; else side `max` with as many as fit (`rect` tells which).
pub fn Atlas::repack(
  glyphs : Array[(Int32, Int32, Int32)],
  side : Int32,
  max : Int32,
) -> Atlas {
  let sorted = glyphs.copy()
  sorted.sort_by((a, b) => if a.2 != b.2 { b.2 - a.2 } else { a.0 - b.0 })
  let mut area = 0L
  for g in sorted {
    area += padded_area(g.1, g.2)
  }
  let mut s = @cmp.minimum(side, max)
  while s < max && area * 2 > s.to_int64() * s.to_int64() {
    s = @cmp.minimum(s * 2, max)
  }
  let mut atlas = Atlas::new(s, s)
  while !atlas.place_all(sorted) && s < max {
    s = @cmp.minimum(s * 2, max)
    atlas = Atlas::new(s, s)
  }
  atlas
}
