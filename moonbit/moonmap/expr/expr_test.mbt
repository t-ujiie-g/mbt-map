///|
test "constants and lookups are MapLibre's JSON" {
  assert_eq(@expr.num(6).to_json(), 6)
  assert_eq(@expr.str("a").to_json(), "a")
  assert_eq(@expr.bool(true).to_json(), true)
  assert_eq(@expr.color("#2166ac").to_json(), "#2166ac")
  assert_eq(@expr.nums([2, 1]).to_json(), [2, 1])
  assert_eq(@expr.literal([1, 2]).to_json(), ["literal", [1, 2]])
  assert_eq(@expr.get("kind").to_json(), ["get", "kind"])
  assert_eq(@expr.has("kind").to_json(), ["has", "kind"])
  assert_eq(@expr.id().to_json(), ["id"])
  assert_eq(@expr.geometry_type().to_json(), ["geometry-type"])
  assert_eq(@expr.zoom().to_json(), ["zoom"])
  assert_eq(@expr.feature_state("hover").to_json(), ["feature-state", "hover"])
  assert_eq(@expr.global_state("mode").to_json(), ["global-state", "mode"])
  assert_eq(@expr.image("pin").to_json(), ["image", "pin"])
  assert_eq(@expr.raw(["slice", "abc", 1]).to_json(), ["slice", "abc", 1])
}

///|
test "match, case and coalesce put labels, conditions and the default in place" {
  assert_eq(
    @expr.match_(
      @expr.get("kind"),
      [("駅", @expr.color("#f00")), (["a", "b"], @expr.color("#0f0"))],
      default=@expr.color("#000"),
    ).to_json(),
    ["match", ["get", "kind"], "駅", "#f00", ["a", "b"], "#0f0", "#000"],
  )
  assert_eq(
    @expr.case_(
      [(@expr.has("a"), @expr.num(1)), (@expr.has("b"), @expr.num(2))],
      default=@expr.num(0),
    ).to_json(),
    ["case", ["has", "a"], 1, ["has", "b"], 2, 0],
  )
  assert_eq(@expr.coalesce([@expr.get("a"), @expr.str("")]).to_json(), [
    "coalesce",
    ["get", "a"],
    "",
  ])
}

///|
test "interpolate takes its curve, step its base, both their stops in order" {
  assert_eq(
    @expr.interpolate(@expr.zoom(), [(10, @expr.num(1)), (16, @expr.num(4))]).to_json(),
    ["interpolate", ["linear"], ["zoom"], 10, 1, 16, 4],
  )
  assert_eq(
    @expr.interpolate(
      @expr.zoom(),
      [(10, @expr.num(1))],
      curve=Exponential(1.5),
    ).to_json(),
    ["interpolate", ["exponential", 1.5], ["zoom"], 10, 1],
  )
  assert_eq(
    @expr.interpolate(
      @expr.get("v"),
      [(0, @expr.num(0))],
      curve=CubicBezier(0.42, 0, 0.58, 1),
    ).to_json(),
    ["interpolate", ["cubic-bezier", 0.42, 0, 0.58, 1], ["get", "v"], 0, 0],
  )
  assert_eq(
    @expr.step(@expr.zoom(), @expr.num(1), [(12, @expr.num(2))]).to_json(),
    ["step", ["zoom"], 1, 12, 2],
  )
}

///|
test "comparisons, logic, arithmetic and strings" {
  let a = @expr.get("a")
  let one = @expr.num(1)
  assert_eq(@expr.eq(a, one).to_json(), ["==", ["get", "a"], 1])
  assert_eq(@expr.ne(a, one).to_json(), ["!=", ["get", "a"], 1])
  assert_eq(@expr.lt(a, one).to_json(), ["<", ["get", "a"], 1])
  assert_eq(@expr.le(a, one).to_json(), ["<=", ["get", "a"], 1])
  assert_eq(@expr.gt(a, one).to_json(), [">", ["get", "a"], 1])
  assert_eq(@expr.ge(a, one).to_json(), [">=", ["get", "a"], 1])
  assert_eq(@expr.all([@expr.has("a"), @expr.not_(@expr.has("b"))]).to_json(), [
    "all",
    ["has", "a"],
    ["!", ["has", "b"]],
  ])
  assert_eq(@expr.any([@expr.has("a")]).to_json(), ["any", ["has", "a"]])
  assert_eq(@expr.in_(a, ["x", "y"]).to_json(), [
    "in",
    ["get", "a"],
    ["literal", ["x", "y"]],
  ])
  assert_eq(@expr.add(a, one).to_json(), ["+", ["get", "a"], 1])
  assert_eq(@expr.sub(a, one).to_json(), ["-", ["get", "a"], 1])
  assert_eq(@expr.mul(a, one).to_json(), ["*", ["get", "a"], 1])
  assert_eq(@expr.div(a, one).to_json(), ["/", ["get", "a"], 1])
  assert_eq(@expr.concat([a, @expr.str("!")]).to_json(), [
    "concat",
    ["get", "a"],
    "!",
  ])
  assert_eq(@expr.to_string(a).to_json(), ["to-string", ["get", "a"]])
  assert_eq(@expr.to_number(a).to_json(), ["to-number", ["get", "a"]])
}
