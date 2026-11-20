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
fn cells(t : @geom.Table, name : String) -> Array[@geom.Prop?] {
  t.column(name).unwrap().values
}

///|
fn nums(values : Array[Double]) -> Array[@geom.Prop?] {
  values.map(x => Some(@geom.Prop::Num(x)))
}

///|
fn rolled(
  t : @geom.Table,
  how : @tableops.Aggregate,
  value : String,
) -> Array[@geom.Prop?] {
  let by = [("kind", expr("[\"get\", \"kind\"]"))]
  cells(@tableops.rollup(t, by, [("x", how, expr(value))]), "x")
}

///|
test "rollup gives a row without geometry per group, groups in the order they first come" {
  let t = @tableops.rollup(sample(), [("kind", expr("[\"get\", \"kind\"]"))], [
    ("rows", Count, expr("null")),
  ])
  assert_eq(t.columns.map(c => c.name), ["kind", "rows"])
  assert_eq(cells(t, "kind"), strs(["park", "school"]))
  assert_eq(cells(t, "rows"), nums([3.0, 2.0]))
  assert_true(t.kinds is [NoGeometry, NoGeometry])
  assert_eq(t.coords.length(), 0)
}

///|
test "rollup without keys gives one row, of an empty table too" {
  let outputs = [
    ("rows", @tableops.Aggregate::Count, expr("null")),
    ("sum", Sum, expr("[\"get\", \"n\"]")),
  ]
  let t = @tableops.rollup(sample(), [], outputs)
  assert_eq(cells(t, "rows"), nums([5.0]))
  assert_eq(cells(t, "sum"), nums([6.0]))
  let empty = @tableops.rollup(@geom.Table::new(), [], outputs)
  assert_eq(cells(empty, "rows"), nums([0.0]))
  assert_eq(cells(empty, "sum"), [Some(Null)])
  let by = [("kind", expr("[\"get\", \"kind\"]"))]
  assert_eq(@tableops.rollup(@geom.Table::new(), by, outputs).length(), 0)
}

///|
test "rollup groups null with a missing key, apart from other values, and a later name replaces an earlier" {
  let t = @tableops.rollup(
    sample(),
    [
      ("n", expr("[\"get\", \"n\"]")),
      ("big", expr("[\">\", [\"get\", \"n\"], 1]")),
    ],
    [("rows", Count, expr("null")), ("big", Any, expr("[\"get\", \"name\"]"))],
  )
  assert_eq(t.columns.map(c => c.name), ["n", "big", "rows"])
  assert_eq(cells(t, "n"), [
    Some(Num(3.0)),
    Some(Num(1.0)),
    Some(Null),
    Some(Num(2.0)),
  ])
  assert_eq(cells(t, "rows"), nums([1.0, 1.0, 2.0, 1.0]))
  assert_eq(cells(t, "big"), strs(["a", "b", "c", "d"]))
}

///|
test "aggregates skip null and missing values, and are null without a value" {
  let n = "[\"get\", \"n\"]"
  assert_eq(rolled(sample(), Valid, n), nums([2.0, 1.0]))
  assert_eq(rolled(sample(), Distinct, n), nums([3.0, 2.0]))
  assert_eq(rolled(sample(), Sum, n), nums([5.0, 1.0]))
  assert_eq(rolled(sample(), Product, n), nums([6.0, 1.0]))
  assert_eq(rolled(sample(), Mean, n), nums([2.5, 1.0]))
  assert_eq(rolled(sample(), Min, n), nums([2.0, 1.0]))
  assert_eq(rolled(sample(), Max, n), nums([3.0, 1.0]))
  assert_eq(rolled(sample(), Median, n), nums([2.5, 1.0]))
  assert_eq(rolled(sample(), Any, n), nums([3.0, 1.0]))
  assert_eq(rolled(sample(), Mode, n), nums([3.0, 1.0]))
  assert_eq(rolled(sample(), Variance, n), [Some(Num(0.5)), Some(Null)])
  assert_eq(rolled(sample(), Stdev, n), [Some(Num(0.5.sqrt())), Some(Null)])
  assert_eq(rolled(sample(), Sum, "[\"get\", \"nope\"]"), [
    Some(Null),
    Some(Null),
  ])
}

///|
test "quantile is linear between the sorted values around its rank, their ends outside 0 to 1" {
  let n = "[\"get\", \"n\"]"
  let all = (p : Double) => {
    cells(@tableops.rollup(sample(), [], [("q", Quantile(p), expr(n))]), "q")
  }
  assert_eq(all(0.0), nums([1.0]))
  assert_eq(all(-1.0), nums([1.0]))
  assert_eq(all(0.25), nums([1.5]))
  assert_eq(all(0.5), nums([2.0]))
  assert_eq(all(1.0), nums([3.0]))
  assert_eq(all(2.0), nums([3.0]))
}

///|
test "min, max, mode and any keep strings, ordered by code units" {
  let name = "[\"get\", \"name\"]"
  assert_eq(rolled(sample(), Min, name), strs(["a", "b"]))
  assert_eq(rolled(sample(), Max, name), strs(["d", "e"]))
  assert_eq(
    rolled(sample(), Mode, "[\"get\", \"kind\"]"),
    strs(["park", "school"]),
  )
  assert_eq(rolled(sample(), Sum, name), [Some(Null), Some(Null)])
}

///|
test "Aggregate::coded follows the enumeration's order, Count for another code" {
  let names = (0)
    .until(15)
    .map(code => {
      match @tableops.Aggregate::coded(code, 0.25) {
        Count => "count"
        Valid => "valid"
        Distinct => "distinct"
        Sum => "sum"
        Mean => "mean"
        Min => "min"
        Max => "max"
        Median => "median"
        Any => "any"
        Variance => "variance"
        Stdev => "stdev"
        Quantile(p) => "quantile \{p}"
        Mode => "mode"
        Product => "product"
      }
    })
  assert_eq(names.collect(), [
    "count", "valid", "distinct", "sum", "mean", "min", "max", "median", "any", "variance",
    "stdev", "quantile 0.25", "mode", "product", "count",
  ])
}

///|
/// Rows keyed by `kind` (one twice, one that no row of `sample` has, one null) with `n` and `v`.
fn lookup() -> @geom.Table {
  let t = @geom.Table::new()
  let rows : Array[(@geom.Prop, Double)] = [
    (Str("school"), 10.0),
    (Str("park"), 20.0),
    (Str("pool"), 30.0),
    (Str("school"), 40.0),
    (Null, 50.0),
  ]
  for row in rows {
    t.push_row(None, [
      ("kind", Some(row.0)),
      ("n", Some(Num(row.1))),
      ("v", Some(Num(row.1 + 1.0))),
    ])
    |> ignore
  }
  t
}

///|
test "join pairs rows with equal keys, keeping the left geometry and renaming shared columns" {
  let t = @tableops.join(sample(), lookup(), [("kind", "kind")]).unwrap()
  assert_eq(t.columns.map(c => c.name), ["name", "n_1", "kind", "n_2", "v"])
  assert_eq(names(t), strs(["a", "b", "b", "c", "d", "e", "e"]))
  assert_eq(cells(t, "n_2"), nums([20.0, 10.0, 40.0, 20.0, 20.0, 10.0, 40.0]))
  assert_eq(cells(t, "v"), nums([21.0, 11.0, 41.0, 21.0, 21.0, 11.0, 41.0]))
  assert_true(t.kinds is [Point, Point, Point, NoGeometry, Point, Point, Point])
  assert_eq(t.coords[0:4], [0.0, 10.0, 1.0, 10.0][:])
}

///|
test "join scans the table with more rows, and keeps unmatched left rows last when asked" {
  let few = @tableops.slice(sample(), 0, 2)
  let t = @tableops.join(few, lookup(), [("kind", "kind")]).unwrap()
  assert_eq(names(t), strs(["b", "a", "b"]))
  let other = @tableops.join(lookup(), sample(), [("n", "n")], keep_left=true).unwrap()
  assert_eq(other.length(), 5)
  assert_eq(cells(other, "name"), [None, None, None, None, None])
  assert_eq(other.columns.map(c => c.name), [
    "kind_1", "n", "v", "name", "kind_2",
  ])
}

///|
test "join matches by type and value, never null, on every key" {
  let t = @tableops.join(lookup(), lookup(), [("kind", "kind"), ("n", "n")]).unwrap()
  assert_eq(cells(t, "v_1"), nums([11.0, 21.0, 31.0, 41.0]))
  assert_eq(t.columns.map(c => c.name), ["kind", "n", "v_1", "v_2"])
  let crossed = @tableops.join(lookup(), lookup(), [("kind", "n")]).unwrap()
  assert_eq(crossed.length(), 0)
}

///|
test "join refuses no key, a missing column and a name twice in the result" {
  assert_true(
    @tableops.join(sample(), lookup(), []) is Err("no key to join on"),
  )
  assert_true(
    @tableops.join(sample(), lookup(), [("kind", "x")]) is Err("no column x"),
  )
  assert_true(
    @tableops.join(sample(), lookup(), [("x", "kind")]) is Err("no column x"),
  )
  assert_true(
    @tableops.join(sample(), lookup(), [("kind", "kind")], suffix=("", ""))
    is Err("a column twice in the joined table"),
  )
  let empty = @tableops.join(@geom.Table::new(), lookup(), [("x", "kind")])
  assert_eq(empty.unwrap().length(), 0)
}

///|
test "join_pairs puts the paired rows side by side in the pairs' order, unmatched left rows last" {
  let t = @tableops.join_pairs(sample(), lookup(), [3, 0, 0, 2, 0, 4]).unwrap()
  assert_eq(names(t), strs(["d", "a", "a"]))
  assert_eq(t.columns.map(c => c.name), [
    "name", "n_1", "kind_1", "kind_2", "n_2", "v",
  ])
  assert_eq(cells(t, "v"), nums([11.0, 31.0, 51.0]))
  assert_eq(cells(t, "kind_2"), [
    Some(Str("school")),
    Some(Str("pool")),
    Some(Null),
  ])
  let kept = @tableops.join_pairs(sample(), lookup(), [3, 0], keep_left=true).unwrap()
  assert_eq(names(kept), strs(["d", "a", "b", "c", "e"]))
  assert_eq(cells(kept, "v"), [Some(Num(11.0)), None, None, None, None])
  assert_true(kept.kinds is [Point, Point, Point, NoGeometry, Point])
}

///|
test "rollup_pairs aggregates the paired rows per left row, keeping every row and its geometry" {
  let outputs = [
    ("hits", @tableops.Aggregate::Count, expr("null")),
    ("n", Sum, expr("[\"get\", \"n\"]")),
  ]
  let t = @tableops.rollup_pairs(
    sample(),
    lookup(),
    [0, 0, 3, 1, 0, 2],
    outputs,
  ).unwrap()
  assert_eq(t.columns.map(c => c.name), ["name", "n", "kind", "hits"])
  assert_eq(cells(t, "hits"), nums([2.0, 0.0, 0.0, 1.0, 0.0]))
  assert_eq(cells(t, "n"), [
    Some(Num(40.0)),
    Some(Null),
    Some(Null),
    Some(Num(20.0)),
    Some(Null),
  ])
  assert_eq(t.coords, sample().coords)
}

///|
test "pairs out of the tables or without a second row are refused" {
  let bad : Array[Array[Int32]] = [[0], [5, 0], [0, 5], [-1, 0], [0, -1]]
  for pairs in bad {
    assert_true(
      @tableops.join_pairs(sample(), lookup(), pairs)
      is Err("a pair out of the tables"),
    )
    assert_true(
      @tableops.rollup_pairs(sample(), lookup(), pairs, [])
      is Err("a pair out of the tables"),
    )
  }
}

///|
test "column_groups groups rows as rollup does, null with a missing key" {
  let (groups, first) = @tableops.column_groups(sample(), ["kind"]).unwrap()
  assert_eq((groups, first), ([0, 1, 0, 0, 1], [0, 1]))
  let (groups, first) = @tableops.column_groups(sample(), ["n", "kind"]).unwrap()
  assert_eq((groups, first), ([0, 1, 2, 3, 4], [0, 1, 2, 3, 4]))
  let (groups, first) = @tableops.column_groups(sample(), ["n"]).unwrap()
  assert_eq((groups, first), ([0, 1, 2, 3, 2], [0, 1, 2, 3]))
  assert_true(@tableops.column_groups(sample(), ["x"]) is Err("no column x"))
  assert_true(
    @tableops.column_groups(@geom.Table::new(), ["x"]) is Ok(([], [])),
  )
  assert_true(
    @tableops.column_groups(sample(), []) is Ok(([0, 0, 0, 0, 0], [0])),
  )
}

///|
test "join and join_pairs refuse a result past a table's cells" {
  // 7 rows of 5 columns.
  let on = [("kind", "kind")]
  assert_true(@tableops.join(sample(), lookup(), on, max_cells=35) is Ok(_))
  assert_true(@tableops.join(sample(), lookup(), on, max_cells=34) is Err(_))
  assert_true(@tableops.join(sample(), lookup(), on, max_cells=6) is Err(_))
  let pairs = [0, 0, 0, 1]
  let cells = 2 * (sample().columns.length() + lookup().columns.length())
  assert_true(
    @tableops.join_pairs(sample(), lookup(), pairs, max_cells=cells) is Ok(_),
  )
  assert_true(
    @tableops.join_pairs(sample(), lookup(), pairs, max_cells=cells - 1)
    is Err(_),
  )
}
