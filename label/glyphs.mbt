///|
/// The glyph bitmaps (of type `B`) an atlas is made from, by glyph key. A worker
/// sends each glyph once, so a bitmap left out of a rebuilt atlas (`keep`) waits in
/// `old` until every worker has said it will send that glyph again (`forget`,
/// `forgotten`): tiles made before then may still use it.
pub struct GlyphStore[B] {
  priv mut bitmaps : Map[Int32, B]
  priv old : Map[Int32, B]
  priv mut epoch : Int32
  priv mut waits : Int32
}

///|
pub fn[B] GlyphStore::new() -> GlyphStore[B] {
  { bitmaps: Map([]), old: Map([]), epoch: 0, waits: 0, }
}

///|
/// Takes the bitmap a worker sent for glyph `key`.
pub fn[B] GlyphStore::add(
  self : GlyphStore[B],
  key : Int32,
  bitmap : B,
) -> Unit {
  self.bitmaps[key] = bitmap
}

///|
/// Glyph `key`'s bitmap, if the store still has it.
pub fn[B] GlyphStore::get(self : GlyphStore[B], key : Int32) -> B? {
  match self.bitmaps.get(key) {
    Some(b) => Some(b)
    None => self.old.get(key)
  }
}

///|
/// Keeps the bitmaps of the glyphs `used` (repeats allowed) and returns them; the others wait
/// until the workers forget them (`forget`).
pub fn[B] GlyphStore::keep(
  self : GlyphStore[B],
  used : Array[Int32],
) -> Array[(Int32, B)] {
  let kept = Map([])
  let out = []
  for key in used {
    if !kept.contains(key) && self.get(key) is Some(b) {
      kept[key] = b
      out.push((key, b))
      self.old.remove(key)
    }
  }
  for key, b in self.bitmaps {
    if !kept.contains(key) {
      self.old[key] = b
    }
  }
  self.bitmaps = kept
  out
}

///|
/// Starts a new epoch, in which `workers` must say they will send every glyph
/// again (`forgotten`) before the bitmaps left out are dropped; returns it.
pub fn[B] GlyphStore::forget(self : GlyphStore[B], workers : Int32) -> Int32 {
  self.epoch += 1
  self.waits = workers
  if workers <= 0 {
    self.old.clear()
  }
  self.epoch
}

///|
/// A worker has forgotten the glyphs it sent before `epoch`.
pub fn[B] GlyphStore::forgotten(self : GlyphStore[B], epoch : Int32) -> Unit {
  if epoch == self.epoch && self.waits > 0 {
    self.waits -= 1
    if self.waits == 0 {
      self.old.clear()
    }
  }
}

///|
/// Bitmaps held: kept, then waiting to be dropped.
pub fn[B] GlyphStore::sizes(self : GlyphStore[B]) -> (Int32, Int32) {
  (self.bitmaps.length(), self.old.length())
}
