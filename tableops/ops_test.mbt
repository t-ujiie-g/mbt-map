///|
/// Rows named a to e: a point per row but the third; `n` 3, 1, null, 2 and absent; `kind`.
fn sample() -> @geom.Table {
  let b = @geom.TableBuilder::new()
  let rows : Array[(String, @geom.Prop?, String)] = [
    ("a", Some(Num(3.0)), "park"),
    ("b", Some(Num(1.0)), "school"),
    ("c", Some(Null), "park"),
    ("d", Some(Num(2.0)), "park"),
    ("e", None, "school"),
  ]
  for i, row in rows {
    if i != 2 {
      b.point(i.to_double(), 10.0)
      b.end_ring()
      b.end_part()
    }
    b.prop("name", Str(row.0))
    if row.1 is Some(n) {
      b.prop("n", n)
    }
    b.prop("kind", Str(row.2))
    b.end_feature(if i == 2 { NoGeometry } else { Point })
  }
  b.finish()
}

///|
fn expr(text : String) -> @style.Expr {
  @style.compile(@json.parse(text)) catch {
    _ => abort("not an expression: \{text}")
  }
}

///|
fn names(t : @geom.Table) -> Array[@geom.Prop?] {
  t.column("name").unwrap().values
}

///|
fn strs(names : Array[String]) -> Array[@geom.Prop?] {
  names.map(s => Some(@geom.Prop::Str(s)))
}

///|
test "select keeps the named columns in the order given and the geometry" {
  let t = @tableops.select(sample(), ["kind", "name"]).unwrap()
  assert_eq(t.columns.map(c => c.name), ["kind", "name"])
  assert_eq(names(t), strs(["a", "b", "c", "d", "e"]))
  assert_eq(t.coords, sample().coords)
  assert_eq(@tableops.select(sample(), []).unwrap().columns.length(), 0)
  assert_true(@tableops.select(sample(), ["name", "x"]) is Err("no column x"))
  assert_true(
    @tableops.select(sample(), ["name", "name"])
    is Err("a column selected twice"),
  )
}

///|
test "filter keeps the rows whose test is true, with their geometry" {
  let parks = @tableops.filter(
    sample(),
    expr("[\"==\", [\"get\", \"kind\"], \"park\"]"),
  )
  assert_eq(names(parks), strs(["a", "c", "d"]))
  assert_eq(parks.kinds, [Point, NoGeometry, Point])
  assert_eq(parks.coords, [0.0, 10.0, 3.0, 10.0])
  // An error (a string compared with a number) and a value that is not a boolean keep nothing.
  assert_eq(
    @tableops.filter(sample(), expr("[\">\", [\"get\", \"name\"], 1]")).length(),
    0,
  )
  assert_eq(@tableops.filter(sample(), expr("[\"get\", \"n\"]")).length(), 0)
  let points = @tableops.filter(
    sample(),
    expr("[\"==\", [\"geometry-type\"], \"Point\"]"),
  )
  assert_eq(names(points), strs(["a", "b", "d", "e"]))
}

///|
test "slice clamps its ends to the table" {
  assert_eq(names(@tableops.slice(sample(), 1, 3)), strs(["b", "c"]))
  assert_eq(names(@tableops.slice(sample(), -4, 2)), strs(["a", "b"]))
  assert_eq(names(@tableops.slice(sample(), 3, 99)), strs(["d", "e"]))
  assert_eq(@tableops.slice(sample(), 4, 2).length(), 0)
  assert_eq(@tableops.slice(sample(), 9, 12).length(), 0)
}

///|
test "derive_columns computes columns, replaces one in place and takes given values" {
  let t = @tableops.derive_columns(sample(), [
    ("double", Computed(expr("[\"*\", [\"get\", \"n\"], 2]"))),
    ("name", Computed(expr("[\"upcase\", [\"get\", \"name\"]]"))),
    (
      "rank",
      Given([Some(Num(1.0)), None, Some(Str("x")), Some(Null), Some(Bool(true))]),
    ),
    ("nan", Computed(expr("[\"/\", 0, 0]"))),
  ]).unwrap()
  assert_eq(t.columns.map(c => c.name), [
    "name", "n", "kind", "double", "rank", "nan",
  ])
  assert_eq(names(t), strs(["A", "B", "C", "D", "E"]))
  // Null and an absent `n` are not numbers: the product is an error, kept as null.
  assert_eq(t.column("double").unwrap().values, [
    Some(Num(6.0)),
    Some(Num(2.0)),
    Some(Null),
    Some(Num(4.0)),
    Some(Null),
  ])
  assert_eq(t.column("rank").unwrap().values[1:3].to_owned(), [
    None,
    Some(Str("x")),
  ])
  assert_eq(t.column("nan").unwrap().values[0], Some(Null))
  assert_eq(t.coords, sample().coords)
  assert_true(
    @tableops.derive_columns(sample(), [("x", Given([None]))])
    is Err("1 values for x in a table of 5 rows"),
  )
}

///|
test "column_kinds counts numbers, strings, booleans, nulls and absent cells per column" {
  assert_eq(@tableops.column_kinds(sample()), [
    0, 5, 0, 0, 0, 3, 0, 0, 1, 1, 0, 5, 0, 0, 0,
  ])
  assert_eq(@tableops.column_kinds(@geom.Table::new()), [])
}

///|
test "orderby puts null first, then NaN, then values; descending reverses; ties keep their order" {
  let by = (text : String, descending : Bool) => {
    names(@tableops.orderby(sample(), [(expr(text), descending)]))
  }
  assert_eq(by("[\"get\", \"n\"]", false), strs(["c", "e", "b", "d", "a"]))
  assert_eq(by("[\"get\", \"n\"]", true), strs(["a", "d", "b", "c", "e"]))
  assert_eq(by("[\"get\", \"kind\"]", false), strs(["a", "c", "d", "b", "e"]))
  assert_eq(by("[\"get\", \"kind\"]", true), strs(["b", "e", "a", "c", "d"]))
  let two = @tableops.orderby(sample(), [
    (expr("[\"get\", \"kind\"]"), true),
    (expr("[\"get\", \"name\"]"), true),
  ])
  assert_eq(names(two), strs(["e", "b", "d", "c", "a"]))
  // NaN for b (1 - 1 over 0), null where `n` is not a number: null, then NaN, then numbers.
  let nan = by(
    "[\"/\", [\"-\", [\"get\", \"n\"], 1], [\"-\", [\"get\", \"n\"], 1]]", false,
  )
  assert_eq(nan, strs(["c", "e", "b", "a", "d"]))
  assert_eq(@tableops.orderby(sample(), []).length(), 5)
  assert_eq(
    @tableops.orderby(@geom.Table::new(), [(expr("1"), false)]).length(),
    0,
  )
}

///|
test "orderby compares strings by code units and other pairs as JavaScript numbers" {
  let b = @geom.TableBuilder::new()
  let values : Array[@geom.Prop] = [
    Str("b"),
    Str("B"),
    Str("aa"),
    Str("a"),
    Str("é"),
    Str(""),
  ]
  for v in values {
    b.prop("v", v)
    b.end_feature(NoGeometry)
  }
  let sorted = @tableops.orderby(b.finish(), [(expr("[\"get\", \"v\"]"), false)])
  assert_eq(
    sorted.column("v").unwrap().values,
    strs(["", "B", "a", "aa", "b", "é"]),
  )
  let m = @geom.TableBuilder::new()
  let mixed : Array[@geom.Prop] = [
    Num(2.0),
    Bool(true),
    Str("10"),
    Bool(false),
    Num(-1.0),
  ]
  for v in mixed {
    m.prop("v", v)
    m.end_feature(NoGeometry)
  }
  let sorted = @tableops.orderby(m.finish(), [(expr("[\"get\", \"v\"]"), false)])
  assert_eq(sorted.column("v").unwrap().values, [
    Some(Num(-1.0)),
    Some(Bool(false)),
    Some(Bool(true)),
    Some(Num(2.0)),
    Some(Str("10")),
  ])
}

///|
test "Hooks::default computes with MoonBit's functions" {
  let hooks = @tableops.Hooks::default()
  assert_eq((hooks.number_text)(1.5), "1.5")
  assert_eq((hooks.text_number)("2"), 2.0)
  assert_true(((hooks.trig.sin)(0.0) - 0.0).abs() < @double.min_positive)
}
