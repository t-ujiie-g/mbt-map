// The rows' order follows Arquero 8.0.3's hash join (src/verbs/join.js), BSD 3-Clause License,
// Copyright (c) 2020-2024, UW Interactive Data Lab. See NOTICE.

///|
/// What rows of `t` join by in `columns`, None for a row with a null, absent or NaN key.
fn join_keys(
  t : @geom.Table,
  columns : ArrayView[String],
) -> Result[Array[String?], String] {
  let values = []
  for name in columns {
    match t.column(name) {
      Some(c) => values.push(c.values)
      None => if t.length() > 0 { return Err("no column \{name}") }
    }
  }
  Ok(
    Array::makei(t.length(), i => {
      let id = StringBuilder()
      for column in values {
        let key : Key = match column[i] {
          Some(Num(n)) => Number(n)
          Some(Str(s)) => Text(s)
          Some(Bool(b)) => Flag(b)
          _ => Nothing
        }
        if key.missing() {
          return None
        }
        key.identity(id)
      }
      Some(id.to_string())
    }),
  )
}

///|
/// The rows of `left` (with their geometry) beside the rows of `right` whose columns `on.1`
/// equal `left`'s `on.0` in type and value; with `keep_left`, also the rows without a match.
/// The columns are `left`'s, then `right`'s but the keys of the same name; a name in both gets
/// `suffix`. The rows come as Arquero's `join` gives them. Errors: no key, a column that is
/// missing, a name twice in the result.
pub fn join(
  left : @geom.Table,
  right : @geom.Table,
  on : ArrayView[(String, String)],
  keep_left~ : Bool = false,
  suffix~ : (String, String) = ("_1", "_2"),
) -> Result[@geom.Table, String] {
  guard on.length() > 0 else { return Err("no key to join on") }
  let keys_l = match join_keys(left, on.map(k => k.0)) {
    Ok(keys) => keys
    Err(message) => return Err(message)
  }
  let keys_r = match join_keys(right, on.map(k => k.1)) {
    Ok(keys) => keys
    Err(message) => return Err(message)
  }
  let (n_l, n_r) = (left.length(), right.length())
  // Arquero hashes the table with fewer rows and scans the other.
  let scans_left = n_l >= n_r
  let (scanned, hashed) = if scans_left {
    (keys_l, keys_r)
  } else {
    (keys_r, keys_l)
  }
  let lookup : Map[String, Int32] = Map([])
  let lists : Array[Array[Int32]] = []
  for i, key in hashed {
    if key is Some(key) {
      match lookup.get(key) {
        Some(k) => lists[k].push(i)
        None => {
          lookup[key] = lists.length()
          lists.push([i])
        }
      }
    }
  }
  let rows_l : Array[Int32] = []
  let rows_r : Array[Int32] = []
  let hit_l = FixedArray::make(n_l, false)
  for j, key in scanned {
    guard key is Some(key) && lookup.get(key) is Some(k) else { continue }
    for i in lists[k] {
      let (l, r) = if scans_left { (j, i) } else { (i, j) }
      rows_l.push(l)
      rows_r.push(r)
      hit_l[l] = true
    }
  }
  if keep_left {
    for l in 0..<n_l {
      if !hit_l[l] {
        rows_l.push(l)
        rows_r.push(-1)
      }
    }
  }
  let from_right = right.columns.filter(c => {
    on.search_by(k => k.0 == c.name && k.1 == c.name) is None
  })
  let renamed = (name : String, others : Array[@geom.Column], suffix : String) => {
    if others.search_by(c => c.name == name) is Some(_) {
      name + suffix
    } else {
      name
    }
  }
  let rows = left.take(rows_l).unwrap()
  let columns = rows.columns.map(c => {
    (renamed(c.name, from_right, suffix.0), c.values)
  })
  for c in from_right {
    columns.push(
      (
        renamed(c.name, left.columns, suffix.1),
        rows_r.map(r => if r < 0 { None } else { c.values[r] }),
      ),
    )
  }
  match rows.with_columns(columns) {
    Some(out) => Ok(out)
    None => Err("a column twice in the joined table")
  }
}
