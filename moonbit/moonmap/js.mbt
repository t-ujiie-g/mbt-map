///|
/// A JS value as moon-map's npm package gives or takes it.
#external
pub type JsValue

///|
extern "js" fn js_null() -> JsValue =
  #|() => null

///|
extern "js" fn js_undefined() -> JsValue =
  #|() => undefined

///|
extern "js" fn js_string(s : String) -> JsValue =
  #|(s) => s

///|
extern "js" fn js_number(n : Double) -> JsValue =
  #|(n) => n

///|
extern "js" fn js_bool(b : Bool) -> JsValue =
  #|(b) => b

///|
extern "js" fn js_array(items : FixedArray[JsValue]) -> JsValue =
  #|(items) => items

///|
extern "js" fn js_object(
  keys : FixedArray[String],
  values : FixedArray[JsValue],
) -> JsValue =
  #|(keys, values) => {
  #|  const o = {};
  #|  keys.forEach((k, i) => Object.defineProperty(o, k, { value: values[i], writable: true, enumerable: true, configurable: true }));
  #|  return o;
  #|}

///|
/// `j` as a plain JS value (object keys as own properties, so `__proto__` stays a key).
pub fn json_to_js(j : Json) -> JsValue {
  match j {
    Null => js_null()
    True => js_bool(true)
    False => js_bool(false)
    Number(n, ..) => js_number(n)
    String(s) => js_string(s)
    Array(items) =>
      js_array(FixedArray::from_iter(items.iter().map(json_to_js)))
    Object(o) => {
      let keys = FixedArray::make(o.length(), "")
      let values = FixedArray::make(o.length(), js_null())
      let mut i = 0
      for k, v in o {
        keys[i] = k
        values[i] = json_to_js(v)
        i += 1
      }
      js_object(keys, values)
    }
  }
}

///|
extern "js" fn js_to_json_with(
  v : JsValue,
  null_ : () -> Json,
  bool_ : (Bool) -> Json,
  num : (Double) -> Json,
  str : (String) -> Json,
  arr : (FixedArray[Json]) -> Json,
  obj : (FixedArray[String], FixedArray[Json]) -> Json,
) -> Json =
  #|(v, mkNull, mkBool, mkNum, mkStr, mkArr, mkObj) => {
  #|  const text = JSON.stringify(v);
  #|  if (text === undefined) return mkNull();
  #|  const build = (x) => {
  #|    if (x === null) return mkNull();
  #|    switch (typeof x) {
  #|      case "boolean": return mkBool(x);
  #|      case "number": return mkNum(x);
  #|      case "string": return mkStr(x);
  #|    }
  #|    if (Array.isArray(x)) return mkArr(x.map(build));
  #|    const keys = Object.keys(x);
  #|    return mkObj(keys, keys.map((k) => build(x[k])));
  #|  };
  #|  return build(JSON.parse(text));
  #|}

///|
/// The JSON value of `v`, as `JSON.parse(JSON.stringify(v))` gives it (null for undefined).
pub fn JsValue::to_json(self : JsValue) -> Json {
  js_to_json_with(
    self,
    () => Json::null(),
    b => Json::boolean(b),
    n => Json::number(n),
    s => Json::string(s),
    items => Json::array(items.iter().collect()),
    (keys, values) => {
      let m = @builtin.Map([])
      for i, k in keys {
        m[k] = values[i]
      }
      Json::object(m)
    },
  )
}

///|
extern "js" fn js_get(o : JsValue, key : String) -> JsValue =
  #|(o, k) => (o !== null && typeof o === "object" ? o[k] : undefined)

///|
extern "js" fn js_is_nullish(v : JsValue) -> Bool =
  #|(v) => v === null || v === undefined

///|
extern "js" fn js_as_number(v : JsValue) -> Double =
  #|(v) => (typeof v === "number" ? v : NaN)

///|
extern "js" fn js_as_string(v : JsValue) -> String =
  #|(v) => String(v)

///|
extern "js" fn js_items(v : JsValue) -> FixedArray[JsValue] =
  #|(v) => (Array.isArray(v) ? v : [])

///|
/// `target[name](...args)`.
extern "js" fn js_call(
  target : JsValue,
  name : String,
  args : FixedArray[JsValue],
) -> JsValue =
  #|(o, k, a) => o[k](...a)
