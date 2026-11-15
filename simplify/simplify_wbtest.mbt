///|
test "simplify gives None past MAX_SIMPLIFY_POINTS" {
  let b = @geom.TableBuilder::new()
  for i in 0..<=MAX_SIMPLIFY_POINTS {
    b.point(i.to_double(), (i % 7).to_double())
  }
  b.end_ring()
  b.end_part()
  b.end_feature(LineString)
  assert_true(simplify(b.finish(), 1.0, false) is None)
}
