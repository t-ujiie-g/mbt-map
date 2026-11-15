///|
test "concave and convex give None past MAX_HULL_POINTS" {
  let b = @geom.TableBuilder::new()
  for i in 0..<=MAX_HULL_POINTS {
    b.point(i.to_double(), (i % 7).to_double())
  }
  b.end_ring()
  b.end_part()
  b.end_feature(MultiPoint)
  let t = b.finish()
  assert_true(concave(t, 2.0, 0.0) is None)
  assert_true(convex(t) is None)
}
