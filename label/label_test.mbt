///|
test "the atlas packs glyphs in shelves, padded, and keeps each glyph's place" {
  let a = @label.Atlas::new(20, 12)
  // Bitmaps go a pixel inside their rectangles.
  assert_eq(a.place(1, 8, 4), Some((1, 1)))
  assert_eq(a.place(2, 8, 4), Some((11, 1)))
  // Too wide for the first shelf: a new one below it.
  assert_eq(a.place(3, 8, 3), Some((1, 7)))
  assert_eq(a.place(1, 8, 4), None)
  assert_eq(a.rect(2), Some((10, 0, 10, 6)))
  // A short glyph takes the shortest shelf it fits.
  assert_eq(a.place(4, 2, 2), Some((11, 7)))
  assert_eq(a.place(5, 8, 8), None)
  assert_eq(a.place(6, 0, 3), None)
  assert_eq(a.rect(5), None)
}

///|
test "an atlas tells where a glyph's bitmap goes inside its padding" {
  let a = @label.Atlas::new(20, 12)
  assert_eq(a.place(7, 8, 4), Some((1, 1)))
  assert_eq(a.bitmap_at(7), Some((1, 1)))
  assert_eq(a.bitmap_at(8), None)
}

///|
test "a repacked atlas grows until its glyphs fill at most half of it" {
  // 4 glyphs of 14 x 14 padded to 16 x 16: 1024 pixels, past half of 32 x 32.
  let glyphs = [(1, 14, 14), (2, 14, 14), (3, 14, 14), (4, 14, 14)]
  let a = @label.Atlas::repack(glyphs, 32, 1024)
  assert_eq(a.width, 64)
  assert_eq(a.height, 64)
  for g in glyphs {
    assert_true(a.rect(g.0) is Some(_))
  }
  // Few glyphs stay in the smallest side asked for.
  assert_eq(@label.Atlas::repack([(1, 4, 4)], 32, 1024).width, 32)
  assert_eq(@label.Atlas::repack([], 32, 1024).width, 32)
}

///|
test "a repacked atlas puts the tallest glyphs first and leaves out keys not given" {
  let a = @label.Atlas::repack([(1, 4, 2), (2, 4, 6), (3, 4, 2)], 32, 32)
  assert_eq(a.rect(2), Some((0, 0, 6, 8)))
  assert_eq(a.rect(1), Some((6, 0, 6, 4)))
  assert_eq(a.rect(3), Some((12, 0, 6, 4)))
  assert_eq(a.rect(4), None)
}

///|
test "at its largest side a repacked atlas holds as many glyphs as fit" {
  let glyphs = Array::makei(10, i => (i, 14, 14))
  let a = @label.Atlas::repack(glyphs, 16, 32)
  assert_eq(a.width, 32)
  let placed = glyphs.iter().filter(g => a.rect(g.0) is Some(_)).count()
  assert_eq(placed, 4)
  // A max below the start side wins.
  assert_eq(@label.Atlas::repack([], 64, 32).width, 32)
}

///|
test "a glyph store keeps the glyphs used and drops the others once every worker forgot them" {
  let s : @label.GlyphStore[String] = @label.GlyphStore::new()
  s.add(1, "a")
  s.add(2, "b")
  s.add(3, "c")
  assert_eq(s.keep([3, 1, 3, 9]), [(3, "c"), (1, "a")])
  assert_eq(s.sizes(), (2, 1))
  // Left out but kept for tiles made before the workers forgot it.
  assert_eq(s.get(2), Some("b"))
  let epoch = s.forget(2)
  s.forgotten(epoch - 1)
  s.forgotten(epoch)
  assert_eq(s.sizes(), (2, 1))
  // A glyph waiting to be dropped comes back when used again.
  assert_eq(s.keep([2, 1]), [(2, "b"), (1, "a")])
  assert_eq(s.sizes(), (2, 1))
  s.forgotten(epoch)
  assert_eq(s.sizes(), (2, 0))
  assert_eq(s.get(3), None)
  // Answers to an older epoch do not count toward a newer one.
  assert_eq(s.keep([1]), [(1, "a")])
  let next = s.forget(1)
  s.forgotten(epoch)
  assert_eq(s.sizes(), (1, 1))
  s.forgotten(next)
  assert_eq(s.sizes(), (1, 0))
  // With no workers to wait for, the others go at once.
  s.add(5, "e")
  let _ = s.keep([1])
  let _ = s.forget(0)
  assert_eq(s.sizes(), (1, 0))
}

///|
test "the grid finds overlapping and touching boxes across cells" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  assert_false(g.hits(10.0, 10.0, 50.0, 20.0))
  g.insert(10.0, 10.0, 50.0, 20.0)
  assert_true(g.hits(40.0, 15.0, 90.0, 40.0))
  assert_true(g.hits(50.0, 10.0, 60.0, 20.0))
  assert_false(g.hits(50.1, 10.0, 60.0, 20.0))
  assert_false(g.hits(0.0, 30.0, 200.0, 100.0))
  // Boxes reaching past the grid are clamped into its cells.
  g.insert(-50.0, 90.0, 300.0, 140.0)
  assert_true(g.hits(150.0, 95.0, 160.0, 99.0))
  // Off the grid nothing is met; over all of it, everything.
  assert_false(g.hits(201.0, 0.0, 300.0, 100.0))
  assert_true(g.hits(-1.0, -1.0, 201.0, 101.0))
  assert_true(@label.Grid::new(10.0, 10.0).hits(-1.0, -1.0, 11.0, 11.0))
}

///|
test "circles meet boxes and circles as MapLibre's grid has them" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  g.insert_circle(50.0, 50.0, 10.0)
  // Circles must overlap; a box may touch.
  assert_true(g.hits_circle(65.0, 50.0, 6.0))
  assert_false(g.hits_circle(66.0, 50.0, 6.0))
  assert_true(g.hits(60.0, 40.0, 70.0, 60.0))
  assert_false(g.hits(58.0, 58.0, 70.0, 70.0))
  assert_true(g.hits(57.0, 57.0, 70.0, 70.0))
  g.insert(100.0, 10.0, 120.0, 20.0)
  assert_true(g.hits_circle(125.0, 15.0, 5.0))
  assert_false(g.hits_circle(125.1, 15.0, 5.0))
  assert_false(g.hits_circle(-20.0, 50.0, 10.0))
}

///|
test "a box is inside the grid while some of it lies on it" {
  let g = @label.Grid::new(200.0, 100.0)
  assert_true(g.inside(-10.0, -10.0, 0.0, 0.0))
  assert_false(g.inside(-10.0, -10.0, -0.1, 50.0))
  assert_false(g.inside(200.0, 0.0, 210.0, 10.0))
  assert_true(g.inside(199.9, 99.9, 210.0, 110.0))
}

///|
test "reset empties the grid and resizes it" {
  let g = @label.Grid::new(200.0, 100.0, cell=32.0)
  g.insert(10.0, 10.0, 50.0, 20.0)
  g.insert_circle(150.0, 50.0, 10.0)
  g.reset(200.0, 100.0)
  assert_false(g.hits(0.0, 0.0, 199.0, 99.0))
  assert_false(g.hits_circle(150.0, 50.0, 10.0))
  g.insert(10.0, 10.0, 50.0, 20.0)
  assert_true(g.hits(40.0, 15.0, 90.0, 40.0))
  g.reset(400.0, 300.0)
  assert_false(g.hits(40.0, 15.0, 90.0, 40.0))
  assert_true(g.inside(390.0, 290.0, 410.0, 310.0))
  g.insert(350.0, 250.0, 380.0, 280.0)
  assert_true(g.hits(370.0, 270.0, 390.0, 290.0))
}

///|
test "cooperative hits meet only boxes and circles of symbols that never overlap" {
  let g = @label.Grid::new(200.0, 200.0)
  g.insert(10.0, 10.0, 20.0, 20.0, never=false)
  g.insert_circle(100.0, 100.0, 5.0, never=false)
  assert_true(g.hits(15.0, 15.0, 30.0, 30.0))
  assert_false(g.hits(15.0, 15.0, 30.0, 30.0, cooperative=true))
  assert_false(g.hits_circle(102.0, 100.0, 3.0, cooperative=true))
  g.insert(40.0, 40.0, 50.0, 50.0)
  g.insert_circle(150.0, 150.0, 5.0)
  assert_true(g.hits(45.0, 45.0, 60.0, 60.0, cooperative=true))
  assert_true(g.hits_circle(152.0, 150.0, 3.0, cooperative=true))
  g.reset(200.0, 200.0)
  g.insert(10.0, 10.0, 20.0, 20.0)
  assert_true(g.hits(15.0, 15.0, 30.0, 30.0, cooperative=true))
}
