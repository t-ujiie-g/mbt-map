// The rows' order follows Arquero 8.0.3's hash join (src/verbs/join.js), BSD 3-Clause License,
// Copyright (c) 2020-2024, UW Interactive Data Lab. See NOTICE.

///|
fn cell_key(cell : @geom.Prop?) -> Key {
  match cell {
    Some(Num(n)) => Number(n)
    Some(Str(s)) => Text(s)
    Some(Bool(b)) => Flag(b)
    _ => Nothing
  }
}

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
        let key = cell_key(column[i])
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
/// The rows of `left` beside the rows of `right` whose columns `on.1` equal `left`'s `on.0` in
/// type and value, in Arquero's order, put as `beside` puts them; with `keep_left`, also the
/// rows without a match. Errors: no key, a column that is missing, a name twice in the result.
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
  beside(left, right, rows_l, rows_r, on, suffix)
}

///|
/// Rows `rows_l` of `left` (with their geometry) beside rows `rows_r` of `right` (-1: none):
/// `left`'s columns, then `right`'s but the keys `on` of the same name; a name in both gets
/// `suffix`. An error for a name twice in the result.
fn beside(
  left : @geom.Table,
  right : @geom.Table,
  rows_l : Array[Int32],
  rows_r : Array[Int32],
  on : ArrayView[(String, String)],
  suffix : (String, String),
) -> Result[@geom.Table, String] {
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

///|
/// Whether `pairs` (a row of `left`, then a row of `right`, and so on) are whole and in the tables.
fn pairs_fit(
  left : @geom.Table,
  right : @geom.Table,
  pairs : ArrayView[Int32],
) -> Bool {
  guard pairs.length() % 2 == 0 else { return false }
  for k in 0..<(pairs.length() / 2) {
    let (l, r) = (pairs[2 * k], pairs[2 * k + 1])
    guard l >= 0 && l < left.length() && r >= 0 && r < right.length() else {
      return false
    }
  }
  true
}

///|
/// The rows of `left` beside the rows of `right` that `pairs` give (`pairs_fit`), in their
/// order; with `keep_left`, also the rows of `left` in no pair, last. Columns as `join`'s.
pub fn join_pairs(
  left : @geom.Table,
  right : @geom.Table,
  pairs : ArrayView[Int32],
  keep_left~ : Bool = false,
  suffix~ : (String, String) = ("_1", "_2"),
) -> Result[@geom.Table, String] {
  guard pairs_fit(left, right, pairs) else {
    return Err("a pair out of the tables")
  }
  let n = pairs.length() / 2
  let rows_l = Array::makei(n, k => pairs[2 * k])
  let rows_r = Array::makei(n, k => pairs[2 * k + 1])
  if keep_left {
    let hit = FixedArray::make(left.length(), false)
    for l in rows_l {
      hit[l] = true
    }
    for l in 0..<left.length() {
      if !hit[l] {
        rows_l.push(l)
        rows_r.push(-1)
      }
    }
  }
  beside(left, right, rows_l, rows_r, [], suffix)
}

///|
/// `left` with a column per output: the aggregate, over the rows of `right` that `pairs` give
/// each row, of the value the output takes of them. One named as a column replaces it.
pub fn rollup_pairs(
  left : @geom.Table,
  right : @geom.Table,
  pairs : ArrayView[Int32],
  outputs : ArrayView[(String, Aggregate, @style.Expr)],
  hooks~ : Hooks = Hooks::default(),
) -> Result[@geom.Table, String] {
  guard pairs_fit(left, right, pairs) else {
    return Err("a pair out of the tables")
  }
  let n = pairs.length() / 2
  let columns = left.columns.map(c => (c.name, c.values))
  let computed = aggregates(
    right,
    Array::makei(n, k => pairs[2 * k + 1]),
    Array::makei(n, k => pairs[2 * k]),
    left.length(),
    outputs,
    hooks,
  )
  for column in computed {
    let values = column.1.map(v => Some(v))
    match columns.search_by(c => c.0 == column.0) {
      Some(i) => columns[i] = (column.0, values)
      None => columns.push((column.0, values))
    }
  }
  Ok(left.with_columns(columns).unwrap())
}

///|
/// The group of each row of `t` and each group's first row, as `rollup` groups rows by the
/// columns `names`; the name that is not a column as the error (unless `t` has no row).
pub fn column_groups(
  t : @geom.Table,
  names : ArrayView[String],
) -> Result[(Array[Int32], Array[Int32]), String] {
  let keys = []
  for name in names {
    match t.column(name) {
      Some(c) =>
        keys.push(FixedArray::makei(t.length(), i => cell_key(c.values[i])))
      None => if t.length() > 0 { return Err("no column \{name}") }
    }
  }
  if t.length() == 0 {
    return Ok(([], []))
  }
  Ok(group_rows(t.length(), keys))
}
