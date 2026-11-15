///|
/// A city to fly to: `key` names its button (`go-<key>`), `name` is its local name and `zh`, `ja`, `en`
/// its names in Chinese, Japanese and English (the keys `name:zh`, `name:ja`, `name:en` of OpenMapTiles).
priv struct City {
  key : String
  name : String
  zh : String
  ja : String
  en : String
  center : @mbtmap.LngLat
  zoom : Double
}

///|
let cities : Array[City] = [
  {
    key: "beijing",
    name: "北京",
    zh: "北京",
    ja: "北京",
    en: "Beijing",
    center: @mbtmap.lnglat(116.3913, 39.9075),
    zoom: 15.0,
  },
  {
    key: "shanghai",
    name: "上海",
    zh: "上海",
    ja: "上海",
    en: "Shanghai",
    center: @mbtmap.lnglat(121.5010, 31.2397),
    zoom: 15.0,
  },
  {
    key: "shenzhen",
    name: "深圳",
    zh: "深圳",
    ja: "深圳",
    en: "Shenzhen",
    center: @mbtmap.lnglat(114.0553, 22.5405),
    zoom: 15.0,
  },
  {
    key: "hongkong",
    name: "香港",
    zh: "香港",
    ja: "香港",
    en: "Hong Kong",
    center: @mbtmap.lnglat(114.1588, 22.2810),
    zoom: 15.0,
  },
  {
    key: "chengdu",
    name: "成都",
    zh: "成都",
    ja: "成都",
    en: "Chengdu",
    center: @mbtmap.lnglat(104.0657, 30.6574),
    zoom: 15.0,
  },
  {
    key: "hangzhou",
    name: "杭州",
    zh: "杭州",
    ja: "杭州",
    en: "Hangzhou",
    center: @mbtmap.lnglat(120.1551, 30.2741),
    zoom: 14.0,
  },
  {
    key: "tokyo",
    name: "東京",
    zh: "东京",
    ja: "東京",
    en: "Tokyo",
    center: @mbtmap.lnglat(139.7671, 35.6812),
    zoom: 15.0,
  },
  {
    key: "osaka",
    name: "大阪",
    zh: "大阪",
    ja: "大阪",
    en: "Osaka",
    center: @mbtmap.lnglat(135.4959, 34.7025),
    zoom: 15.0,
  },
]

///|
/// The cities as GeoJSON points, named as OpenMapTiles names places.
fn cities_geojson() -> Json {
  let features = cities.map(city => {
    let feature : Json = {
      "type": "Feature",
      "properties": {
        "name": city.name,
        "name:zh": city.zh,
        "name:ja": city.ja,
        "name:en": city.en,
        "class": "city",
      },
      "geometry": {
        "type": "Point",
        "coordinates": [city.center.lng, city.center.lat],
      },
    }
    feature
  })
  { "type": "FeatureCollection", "features": Json::array(features) }
}
