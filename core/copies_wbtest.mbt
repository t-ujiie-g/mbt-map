///|
test "unwrapped tile keys tell copies and tiles apart" {
  let keys = []
  for z in [0, 5, 28] {
    let n = 1 << z
    for x in (if n > 1 { [0, n - 1] } else { [0] }) {
      let id = TileId::new(z, x, n - 1).unwrap()
      for wrap in -MAX_WORLD_COPIES..<=MAX_WORLD_COPIES {
        let k = ({ id, wrap, } : UnwrappedTile).key()
        assert_true(!keys.contains(k))
        keys.push(k)
      }
    }
  }
  assert_eq(keys.length(), 5 * 7)
}
