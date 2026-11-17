// `order` follows Arquero 8.0.3's comparator (src/expression/compare.js), BSD 3-Clause License,
// Copyright (c) 2020-2024, UW Interactive Data Lab. See NOTICE.

///|
/// A sort key's value in a row: what `prop_of` keeps, and NaN (which sorts as Arquero sorts it).
priv enum Key {
  Nothing
  Number(Double)
  Text(String)
  Flag(Bool)
}

///|
fn key_of(v : @style.Value) -> Key {
  match v {
    Bool(b) => Flag(b)
    Num(n) => Number(n)
    Str(s) => Text(s)
    _ => Nothing
  }
}

///|
/// -1, 0 or 1 as JavaScript's `<` and `>` order two strings: by UTF-16 code units.
fn code_unit_order(a : String, b : String) -> Int32 {
  let n = a.length().min(b.length())
  for i in 0..<n {
    let d = a[i].to_int().compare(b[i].to_int())
    if d != 0 {
      return d
    }
  }
  a.length().compare(b.length())
}

///|
/// JavaScript's `ToNumber` of a key that is not null.
fn Key::number(self : Key, hooks : Hooks) -> Double {
  match self {
    Number(n) => n
    Flag(b) => if b { 1.0 } else { 0.0 }
    Text(s) => (hooks.text_number)(s)
    Nothing => 0.0
  }
}

///|
/// Arquero's comparison of two values (`compare.js`): null first, then NaN, then by JavaScript's
/// `<` and `>` (two strings by code units, else as numbers); 0 where neither holds.
fn order(u : Key, v : Key, hooks : Hooks) -> Int32 {
  match (u, v) {
    (Nothing, Nothing) => return 0
    (Nothing, _) => return -1
    (_, Nothing) => return 1
    (Text(a), Text(b)) => return code_unit_order(a, b)
    _ => ()
  }
  let (a, b) = (u.number(hooks), v.number(hooks))
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    let nan = (k : Key) => k is Number(n) && n.is_nan()
    if nan(u) && !nan(v) {
      -1
    } else if nan(v) && !nan(u) {
      1
    } else {
      0
    }
  }
}

///|
/// `rows` sorted by `before` (negative: the first comes first), rows that compare equal in
/// their order: a merge sort, as a stable `Array.prototype.sort` leaves them.
fn stable_sort(
  rows : FixedArray[Int32],
  before : (Int32, Int32) -> Int32,
) -> Unit {
  let n = rows.length()
  let spare = FixedArray::make(n, 0)
  let mut width = 1
  let mut from = rows
  let mut to = spare
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = (lo + width).min(n)
      let hi = (lo + 2 * width).min(n)
      let mut i = lo
      let mut j = mid
      for k in lo..<hi {
        if i < mid && (j >= hi || before(from[j], from[i]) >= 0) {
          to[k] = from[i]
          i += 1
        } else {
          to[k] = from[j]
          j += 1
        }
      }
      lo = hi
    }
    let t = from
    from = to
    to = t
    width *= 2
  }
  if !physical_equal(from, rows) {
    from.blit_to(rows, len=n)
  }
}

///|
/// The rows ordered by `keys` (an expression and whether it descends), the first key first, as
/// Arquero's `orderby`: rows that compare equal on every key keep their order.
pub fn orderby(
  t : @geom.Table,
  keys : ArrayView[(@style.Expr, Bool)],
  hooks~ : Hooks = Hooks::default(),
) -> @geom.Table {
  let ctx : Row = { table: t, row: 0, hooks, }
  let n = t.length()
  let values = keys.map(k => {
    FixedArray::makei(n, i => {
      ctx.row = i
      key_of(k.0.eval(0.0, ctx))
    })
  })
  let rows = FixedArray::makei(n, i => i)
  stable_sort(rows, (a, b) => {
    for k, key in keys {
      let o = order(values[k][a], values[k][b], hooks)
      if o != 0 {
        return if key.1 { -o } else { o }
      }
    }
    0
  })
  t.take(Array::from_fixed_array(rows)).unwrap()
}
