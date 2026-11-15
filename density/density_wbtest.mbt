///|
test "contours caps" {
  let values = FixedArray::make(4, 1.0)
  assert_true(contours(values, -1, 4, [0.5], true) is None)
  assert_true(contours(values, 5000, 5000, [0.5], true) is None)
  let many = Array::makei(MAX_THRESHOLDS + 1, i => i.to_double())
  assert_true(contours(values, 2, 2, many, true) is None)
  let fine = Array::makei(MAX_THRESHOLDS, i => i.to_double())
  assert_eq(contours(values, 2, 2, fine, true).unwrap().length(), 4096)
  // Cells times thresholds past MAX_CONTOUR_WORK.
  assert_true(contours(values, 4096, 4096, fine, true) is None)
}

///|
test "contour_density refuses unequal inputs and caps" {
  let xs : FixedArray[Double] = [1.0, 2.0]
  let ys : FixedArray[Double] = [1.0]
  assert_true(contour_density(xs, ys, None, 10, 10, 1, 1.0, 5) is None)
  assert_true(contour_density(xs, xs, Some([1.0]), 10, 10, 1, 1.0, 5) is None)
  assert_true(
    contour_density(xs, xs, None, 10, 10, 1, @double.not_a_number, 5) is None,
  )
  assert_true(
    contour_density(xs, xs, None, 10, 10, 1, 1.0, MAX_THRESHOLDS + 1) is None,
  )
  assert_true(contour_density(xs, xs, None, 100000, 100000, 1, 1.0, 5) is None)
  assert_true(contour_density(xs, xs, None, 10, 10, 1, 1.0e12, 5) is None)
  assert_true(
    contour_density(xs, xs, None, 2147483647, 10, 1 << 30, 1.0, 5) is None,
  )
  // A huge cell size leaves a grid of no cells, and no contours, as in d3.
  let none = contour_density(xs, xs, None, 10, 10, 1 << 30, 1.0, 5)
  assert_eq(none.unwrap().length(), 0)
  let explicit = contour_density(
    xs,
    xs,
    None,
    10,
    10,
    2,
    1.0,
    5,
    trig=@core.Trig::moonbit(),
  )
  assert_eq(explicit.unwrap().map(c => (c.value, c.coordinates.length())), [
    (0.01, 1),
    (0.02, 1),
    (0.03, 1),
    (0.04, 1),
    (0.05, 1),
    (0.06, 1),
  ])
}
