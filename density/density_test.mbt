///|
/// Contours as `value|polygons`, polygons by `;`, rings by `/`, points `x,y`
/// by spaces, numbers as JavaScript prints them (the generator's format).
fn digest(cs : Array[@density.Contour]) -> String {
  cs
  .map(c => {
    let polygons = c.coordinates.map(p => {
      p
      .map(r => r.map(q => q.0.to_string() + "," + q.1.to_string()).join(" "))
      .join("/")
    })
    c.value.to_string() + "|" + polygons.join(";")
  })
  .join("\n")
}

///|
fn fnv(s : String) -> UInt32 {
  let mut h = 0x811c9dc5U
  for i in 0..<s.length() {
    h = (h ^ s.code_unit_at(i).to_uint()) * 0x01000193U
  }
  h
}

///|
/// Asserts the digest's length and FNV-1a hash.
fn check(
  got : Array[@density.Contour]?,
  length : Int32,
  hash : UInt32,
) -> Unit raise {
  let d = digest(got.unwrap())
  assert_eq(d.length(), length)
  assert_eq(fnv(d), hash)
}
