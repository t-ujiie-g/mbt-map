///|
/// The table with only the columns `names`, in that order; the name that is not a column
/// (or comes twice) as the error.
pub fn select(
  t : @geom.Table,
  names : ArrayView[String],
) -> Result[@geom.Table, String] {
  let columns = []
  for name in names {
    guard t.column(name) is Some(c) else { return Err("no column \{name}") }
    columns.push((name, c.values))
  }
  match t.with_columns(columns) {
    Some(out) => Ok(out)
    None => Err("a column selected twice")
  }
}

///|
/// The rows for which `keep` is true (not another value, an error or null), in their order.
pub fn filter(
  t : @geom.Table,
  keep : @style.Expr,
  hooks~ : Hooks = Hooks::default(),
) -> @geom.Table {
  let ctx : Row = { table: t, row: 0, hooks, }
  let rows : Array[Int32] = []
  for i in 0..<t.length() {
    ctx.row = i
    if keep.eval(0.0, ctx) is Bool(true) {
      rows.push(i)
    }
  }
  t.take(rows).unwrap()
}

///|
/// Rows `start` up to `end` (not included), both clamped to the table.
pub fn slice(t : @geom.Table, start : Int32, end : Int32) -> @geom.Table {
  let n = t.length()
  let a = start.max(0).min(n)
  let b = end.max(a).min(n)
  t.take(Array::makei(b - a, i => a + i)).unwrap()
}

///|
/// A column to derive: an expression computed per row, or the rows' values as given.
pub(all) enum Derived {
  Computed(@style.Expr)
  Given(Array[@geom.Prop?])
}

///|
/// The table with the columns `columns`: one of an existing name takes its place, the others
/// follow, each seeing the table as it was. An error for given values of another length.
pub fn derive_columns(
  t : @geom.Table,
  columns : ArrayView[(String, Derived)],
  hooks~ : Hooks = Hooks::default(),
) -> Result[@geom.Table, String] {
  let ctx : Row = { table: t, row: 0, hooks, }
  let out = t.columns.map(c => (c.name, c.values))
  for column in columns {
    let (name, how) = column
    let values = match how {
      Given(values) => {
        guard values.length() == t.length() else {
          return Err(
            "\{values.length()} values for \{name} in a table of \{t.length()} rows",
          )
        }
        values
      }
      Computed(e) =>
        Array::makei(t.length(), i => {
          ctx.row = i
          Some(prop_of(e.eval(0.0, ctx)))
        })
    }
    match out.search_by(c => c.0 == name) {
      Some(i) => out[i] = (name, values)
      None => out.push((name, values))
    }
  }
  Ok(t.with_columns(out).unwrap())
}

///|
/// How many cells of each column hold a number, a string, a boolean and null, and how many
/// rows lack the key: five counts per column, in the columns' order.
pub fn column_kinds(t : @geom.Table) -> Array[Int32] {
  let out : Array[Int32] = []
  for c in t.columns {
    let counts = [0, 0, 0, 0, 0]
    for v in c.values {
      let k = match v {
        Some(Num(_)) => 0
        Some(Str(_)) => 1
        Some(Bool(_)) => 2
        Some(Null) => 3
        None => 4
      }
      counts[k] += 1
    }
    out.append(counts)
  }
  out
}
