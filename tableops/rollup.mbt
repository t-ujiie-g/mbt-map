// The aggregates follow Arquero 8.0.3 (src/op/aggregate-functions.js, src/util/quantile.js),
// BSD 3-Clause License, Copyright (c) 2020-2024, UW Interactive Data Lab. See NOTICE.

///|
/// What `rollup` computes of a group's values, named as Arquero's aggregate functions
/// (`Quantile` with its fraction).
pub(all) enum Aggregate {
  Count
  Valid
  Distinct
  Sum
  Mean
  Min
  Max
  Median
  Any
  Variance
  Stdev
  Quantile(Double)
  Mode
  Product
}

///|
/// The aggregate at place `code` of the enumeration (`Count` for another), `fraction` being
/// `Quantile`'s.
pub fn Aggregate::coded(code : Int32, fraction : Double) -> Aggregate {
  match code {
    1 => Valid
    2 => Distinct
    3 => Sum
    4 => Mean
    5 => Min
    6 => Max
    7 => Median
    8 => Any
    9 => Variance
    10 => Stdev
    11 => Quantile(fraction)
    12 => Mode
    13 => Product
    _ => Count
  }
}

///|
/// Whether Arquero's aggregates and joins skip the value: null and NaN.
fn Key::missing(self : Key) -> Bool {
  match self {
    Nothing => true
    Number(n) => n.is_nan()
    _ => false
  }
}

///|
/// Writes what tells the key from every other of another type or value (0 and -0 are one).
fn Key::identity(self : Key, out : StringBuilder) -> Unit {
  match self {
    Nothing => out.write_char('n')
    Flag(b) => out.write_char(if b { 't' } else { 'f' })
    Number(x) =>
      if x.is_nan() {
        out.write_string("dN")
      } else {
        out.write_char('d')
        write_bits(out, (if x == 0.0 { 0.0 } else { x }).reinterpret_as_int64())
      }
    Text(s) => {
      out.write_char('s')
      write_bits(out, s.length().to_int64())
      out.write_string(s)
    }
  }
}

///|
/// Writes `bits` as five characters, 15 bits each.
fn write_bits(out : StringBuilder, bits : Int64) -> Unit {
  for shift in 0..<5 {
    let digit = (bits >> (shift * 15)).to_int() & 0x7fff
    out.write_char(Int32::unsafe_to_char(0x100 + digit))
  }
}

///|
fn Key::prop(self : Key) -> @geom.Prop {
  match self {
    Flag(b) => Bool(b)
    Number(n) if !n.is_nan() => Num(n)
    Text(s) => Str(s)
    _ => Null
  }
}

///|
fn number_prop(x : Double) -> @geom.Prop {
  Number(x).prop()
}

///|
/// The values' distinct identities in the order they first come: the first value of each and
/// how many times it comes.
fn tally(values : ArrayView[Key]) -> (Array[Key], Array[Int32]) {
  let index : Map[String, Int32] = Map([])
  let firsts = []
  let counts = []
  for v in values {
    let id = StringBuilder()
    v.identity(id)
    let id = id.to_string()
    match index.get(id) {
      Some(k) => counts[k] += 1
      None => {
        index[id] = firsts.length()
        firsts.push(v)
        counts.push(1)
      }
    }
  }
  (firsts, counts)
}

///|
/// Arquero's `quantile` of values sorted ascending: linear between the two around the rank.
fn quantile(sorted : ArrayView[Key], p : Double, hooks : Hooks) -> @geom.Prop {
  let n = sorted.length()
  if n == 0 {
    return Null
  }
  if p <= 0.0 || n < 2 {
    return number_prop(sorted[0].number(hooks))
  }
  if p >= 1.0 {
    return number_prop(sorted[n - 1].number(hooks))
  }
  let i = (n - 1).to_double() * p
  let i0 = i.floor()
  let v0 = sorted[i0.to_int()].number(hooks)
  let v1 = sorted[i0.to_int() + 1].number(hooks)
  number_prop(v0 + (v1 - v0) * (i - i0))
}

///|
/// The aggregate of a group of `count` rows whose values that are not missing are `values`,
/// in the rows' order: null where Arquero gives `undefined`.
fn Aggregate::of(
  self : Aggregate,
  count : Int32,
  values : Array[Key],
  hooks : Hooks,
) -> @geom.Prop {
  let valid = values.length()
  match self {
    Count => return Num(count.to_double())
    Valid => return Num(valid.to_double())
    Distinct => {
      let n = tally(values).0.length() + (if valid == count { 0 } else { 1 })
      return Num(n.to_double())
    }
    _ => ()
  }
  guard valid > 0 else { return Null }
  match self {
    Any => values[0].prop()
    Sum => {
      let mut sum = 0.0
      for v in values {
        sum += v.number(hooks)
      }
      number_prop(sum)
    }
    Product => {
      let mut product = 1.0
      for v in values {
        product *= v.number(hooks)
      }
      number_prop(product)
    }
    Mean | Variance | Stdev => {
      let mut mean = 0.0
      let mut dev = 0.0
      for k, v in values {
        let x = v.number(hooks)
        let d = x - mean
        mean += d / (k + 1).to_double()
        dev += d * (x - mean)
      }
      if self is Mean {
        number_prop(mean)
      } else if valid < 2 {
        Null
      } else {
        let variance = dev / (valid - 1).to_double()
        number_prop(if self is Stdev { variance.sqrt() } else { variance })
      }
    }
    Min | Max => {
      let sign = if self is Min { -1 } else { 1 }
      let mut best = values[0]
      for v in values {
        if loose_order(v, best, hooks) == sign {
          best = v
        }
      }
      best.prop()
    }
    Mode => {
      let (firsts, counts) = tally(values)
      let mut mode = 0
      for k, n in counts {
        if n > counts[mode] {
          mode = k
        }
      }
      firsts[mode].prop()
    }
    Median | Quantile(_) => {
      let p = if self is Quantile(p) { p } else { 0.5 }
      let rows = FixedArray::makei(valid, i => i)
      stable_sort(rows, (a, b) => loose_order(values[a], values[b], hooks))
      quantile(Array::makei(valid, i => values[rows[i]]), p, hooks)
    }
    Count | Valid | Distinct => Null
  }
}

///|
/// The group of each row and each group's first row, groups in the order they first come: rows
/// are one group where `keys` have the same identities (all rows, without keys).
fn group_rows(
  n : Int32,
  keys : ArrayView[FixedArray[Key]],
) -> (Array[Int32], Array[Int32]) {
  let of_row = Array::make(n, 0)
  if keys.length() == 0 {
    return (of_row, [0])
  }
  let first : Array[Int32] = []
  let index : Map[String, Int32] = Map([])
  for i in 0..<n {
    let id = StringBuilder()
    for key in keys {
      key[i].identity(id)
    }
    let id = id.to_string()
    of_row[i] = match index.get(id) {
      Some(g) => g
      None => {
        index[id] = first.length()
        first.push(i)
        first.length() - 1
      }
    }
  }
  (of_row, first)
}

///|
/// Each of `outputs` (a name, an aggregate and the value it takes of a row of `t`) in `size`
/// groups: row `rows[k]` is in group `groups[k]`.
fn aggregates(
  t : @geom.Table,
  rows : Array[Int32],
  groups : Array[Int32],
  size : Int32,
  outputs : ArrayView[(String, Aggregate, @style.Expr)],
  hooks : Hooks,
) -> Array[(String, Array[@geom.Prop])] {
  let counts = FixedArray::make(size, 0)
  for k in 0..<rows.length() {
    counts[groups[k]] += 1
  }
  outputs.map(output => {
    let (name, how, e) = output
    let held : Array[Array[Key]] = Array::makei(size, _ => [])
    if !(how is Count) {
      let values = keys_of(t, e, hooks)
      for k, row in rows {
        if !values[row].missing() {
          held[groups[k]].push(values[row])
        }
      }
    }
    (name, Array::makei(size, g => how.of(counts[g], held[g], hooks)))
  })
}

///|
/// One row without geometry per group of rows with the same `keys` (a name and its value; one
/// row for the table without keys), groups in the order they first come: the keys, then each of
/// `outputs` (a name, an aggregate and the value it takes), a later name replacing an earlier.
pub fn rollup(
  t : @geom.Table,
  keys : ArrayView[(String, @style.Expr)],
  outputs : ArrayView[(String, Aggregate, @style.Expr)],
  hooks~ : Hooks = Hooks::default(),
) -> @geom.Table {
  let n = t.length()
  let key_values = keys.map(k => keys_of(t, k.1, hooks))
  let (of_row, first) = group_rows(n, key_values)
  let size = first.length()
  let columns : Array[(String, Array[@geom.Prop])] = []
  let put = (name : String, values : Array[@geom.Prop]) => {
    match columns.search_by(c => c.0 == name) {
      Some(i) => columns[i] = (name, values)
      None => columns.push((name, values))
    }
  }
  for k, key in keys {
    put(key.0, first.map(row => key_values[k][row].prop()))
  }
  let rows = Array::makei(n, i => i)
  for column in aggregates(t, rows, of_row, size, outputs, hooks) {
    put(column.0, column.1)
  }
  let out = @geom.Table::new()
  for g in 0..<size {
    out.push_row(None, columns.map(c => (c.0, Some(c.1[g])))) |> ignore
  }
  out
}
