# bench/table/parquet/*.parquet and expected.json: Parquet files written by pyarrow with the encodings,
# page versions and codecs writers use, and the rows mbt-map/table must read of each (computed here
# from the values, not read back). The files are committed; bench/table/parquet-golden.mjs reads them.
# Usage: python3 bench/data/parquet-fixtures.py (needs pyarrow and shapely; made with pyarrow 23.0.1)
import datetime
import decimal
import json
import random
import struct

import pyarrow as pa
import pyarrow.parquet as pq
import shapely
import shapely.geometry

OUT = "bench/table/parquet/"
random.seed(20261119)
N = 300
WORDS = ["", "a", "park", "é", "東京", "😀", "10", "a longer word shared", "a longer word sharing", "a longer world"]


def maybe(make):
    return None if random.random() < 0.12 else make()


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def iso(ms, utc):
    t = datetime.datetime(1970, 1, 1) + datetime.timedelta(milliseconds=ms)
    text = t.strftime("%Y-%m-%dT%H:%M:%S") + (".%03d" % (ms % 1000) if ms % 1000 else "")
    return text + ("Z" if utc else "")


def shape(kind, i):
    x, y = round(random.uniform(-170, 170), 6), round(random.uniform(-80, 80), 6)
    ring = [(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1), (x, y)]
    if kind == "Point":
        return shapely.geometry.Point(x, y)
    if kind == "LineString":
        return shapely.geometry.LineString(ring[: 2 + i % 3])
    if kind == "Polygon":
        return shapely.geometry.Polygon(ring)
    if kind == "MultiPoint":
        return shapely.geometry.MultiPoint(ring[: 1 + i % 3])
    if kind == "MultiLineString":
        return shapely.geometry.MultiLineString([ring[:2], ring[2:4]])
    return shapely.geometry.MultiPolygon([shapely.geometry.Polygon(ring), shapely.geometry.Polygon([(x + 5, y) for x, y in ring])])


def geojson(g):
    if g is None:
        return None
    m = shapely.geometry.mapping(g)
    return json.loads(json.dumps(m))


# Columns: a name, the Arrow array's values and type, and what each value reads as (None: left out).
def columns(n):
    ints = [maybe(lambda: random.randint(-100, 100)) for _ in range(n)]
    runs = [maybe(lambda: i // 50) for i in range(n)]
    big = [maybe(lambda: random.randint(-(2**40), 2**40)) for _ in range(n)]
    reals = [maybe(lambda: random.choice([0.5, -2.25, 1e10, 3.0, 0.1])) for _ in range(n)]
    words = [maybe(lambda: random.choice(WORDS)) for _ in range(n)]
    sorted_words = sorted(w for w in (random.choice(WORDS) + str(i % 7) for i in range(n)))
    flags = [maybe(lambda: random.random() < 0.5) for _ in range(n)]
    days = [maybe(lambda: random.randint(-20000, 30000)) for _ in range(n)]
    times = [maybe(lambda: random.randint(-(2**40), 2**41)) for _ in range(n)]
    cents = [maybe(lambda: random.randint(-999999, 999999)) for _ in range(n)]
    dec = lambda v, scale: None if v is None else decimal.Decimal(v).scaleb(-scale)
    num = lambda v, scale: None if v is None else float(decimal.Decimal(v).scaleb(-scale))
    date = lambda d: None if d is None else datetime.date(1970, 1, 1) + datetime.timedelta(days=d)
    return [
        ("i8", ints, pa.int8(), ints),
        ("i16", ints, pa.int16(), ints),
        ("i32", ints, pa.int32(), ints),
        ("runs", runs, pa.int32(), runs),
        ("i64", big, pa.int64(), big),
        ("u8", [None if v is None else v + 100 for v in ints], pa.uint8(), [None if v is None else v + 100 for v in ints]),
        ("u16", [None if v is None else v + 60000 for v in ints], pa.uint16(), [None if v is None else v + 60000 for v in ints]),
        ("u32", [None if v is None else v + 4294967000 for v in ints], pa.uint32(), [None if v is None else v + 4294967000 for v in ints]),
        ("u64", [None if v is None else v + 2**63 for v in ints], pa.uint64(), [None if v is None else float(v + 2**63) for v in ints]),
        ("f32", reals, pa.float32(), [None if v is None else f32(v) for v in reals]),
        ("f64", reals, pa.float64(), reals),
        ("flag", flags, pa.bool_(), flags),
        ("text", words, pa.string(), words),
        ("large", words, pa.large_string(), words),
        ("sorted", sorted_words, pa.string(), sorted_words),
        ("coded", words, pa.dictionary(pa.int16(), pa.string()), words),
        ("day", [date(d) for d in days], pa.date32(), [None if d is None else date(d).isoformat() for d in days]),
        ("seconds", [None if t is None else t // 1000 for t in times], pa.timestamp("s"), [None if t is None else iso(t // 1000 * 1000, False) for t in times]),
        ("millis", times, pa.timestamp("ms", tz="UTC"), [None if t is None else iso(t, True) for t in times]),
        ("micros", [None if t is None else t * 1000 + 7 for t in times], pa.timestamp("us"), [None if t is None else iso(t, False) for t in times]),
        ("nanos", [None if t is None else t * 1000000 + 7 for t in times], pa.timestamp("ns", tz="Asia/Tokyo"), [None if t is None else iso(t, True) for t in times]),
        ("money", [dec(v, 2) for v in cents], pa.decimal128(9, 2), [num(v, 2) for v in cents]),
        ("wide", [dec(v, 4) for v in big], pa.decimal128(18, 4), [num(v, 4) for v in big]),
        ("huge", [dec(None if v is None else v * 10**12, 5) for v in big], pa.decimal128(36, 5), [num(None if v is None else v * 10**12, 5) for v in big]),
        ("nothing", [None] * n, pa.null(), [None] * n),
        ("clock", [None if v is None else abs(v) for v in ints], pa.time32("s"), None),
        ("blob", [None if w is None else w.encode() for w in words], pa.binary(), None),
        ("list", [None if v is None else [v, v] for v in ints], pa.list_(pa.int32()), None),
        ("pair", [None if v is None else {"p": v, "q": "s"} for v in ints], pa.struct([("p", pa.int32()), ("q", pa.string())]), None),
    ]


CRS = {"type": "ProjectedCRS", "name": "JGD2011 / Japan Plane Rectangular CS IX", "id": {"authority": "EPSG", "code": 6677}}
KINDS = ("Point", "LineString", "Polygon", "MultiPoint", "MultiLineString", "MultiPolygon")
# One set of rows per row count, shared by the files: expected.json holds each once.
DATA = {}
expected = {"data": {}, "files": {}}


def data(n):
    if n not in DATA:
        DATA[n] = (columns(n), [maybe(lambda: shape(KINDS[i % len(KINDS)], i)) for i in range(n)])
        cols, shapes = DATA[n]
        expected["data"][str(n)] = [{"geometry": geojson(shapes[i]), "properties": {c[0]: c[3][i] for c in cols if c[3] is not None}} for i in range(n)]
    return DATA[n]


def write(name, shaped=True, n=N, geometry="geometry", geo=True, crs=None, only=None, **options):
    cols = [c for c in data(n)[0] if only is None or c[0] in only]
    shapes = data(n)[1] if shaped else None
    arrays = {c[0]: pa.array(c[1], c[2]) for c in cols}
    metadata = {}
    if shapes is not None:
        arrays[geometry] = pa.array([None if g is None else shapely.to_wkb(g) for g in shapes], pa.binary())
        if geo:
            column = {"encoding": "WKB", "geometry_types": []}
            if crs is not None:
                column["crs"] = crs
            metadata["geo"] = json.dumps({"version": "1.1.0", "primary_column": geometry, "columns": {geometry: column}})
    table = pa.table(arrays).replace_schema_metadata(metadata)
    pq.write_table(table, OUT + name + ".parquet", **options)
    expected["files"][name] = {"rows": n, "columns": [c[0] for c in cols if c[3] is not None], "geometry": geometry if shaped else "", "crs": None if crs is None else 6677}


write("plain", compression="none", use_dictionary=False)
write("snappy", compression="snappy")
write("gzip", compression="gzip", row_group_size=250)
write("pages-v2", compression="snappy", data_page_version="2.0", data_page_size=600, row_group_size=300)
write("pages-v2-plain", compression="none", data_page_version="2.0", use_dictionary=False, data_page_size=900)
write("pages-v2-gzip", compression="gzip", data_page_version="2.0", data_page_size=2000)
write("small-pages", compression="snappy", data_page_size=300, dictionary_pagesize_limit=400, row_group_size=180)
write("delta", compression="snappy", use_dictionary=False, only=("i32", "runs", "i64", "u32", "text", "sorted", "large", "day", "millis"),
      column_encoding={"i32": "DELTA_BINARY_PACKED", "runs": "DELTA_BINARY_PACKED", "i64": "DELTA_BINARY_PACKED", "u32": "DELTA_BINARY_PACKED", "day": "DELTA_BINARY_PACKED",
                       "millis": "DELTA_BINARY_PACKED", "text": "DELTA_LENGTH_BYTE_ARRAY", "large": "DELTA_BYTE_ARRAY", "sorted": "DELTA_BYTE_ARRAY", "geometry": "DELTA_LENGTH_BYTE_ARRAY"})
write("split", compression="gzip", use_dictionary=False, only=("f32", "f64", "i32", "i64", "money", "huge"),
      column_encoding={"f32": "BYTE_STREAM_SPLIT", "f64": "BYTE_STREAM_SPLIT", "i32": "BYTE_STREAM_SPLIT", "i64": "BYTE_STREAM_SPLIT", "huge": "BYTE_STREAM_SPLIT", "money": "PLAIN", "geometry": "PLAIN"})
write("int96", compression="snappy", only=("seconds", "micros", "i32"), use_deprecated_int96_timestamps=True)
write("projected", compression="snappy", crs=CRS, n=40, only=("text", "i32"))
write("named", geometry="geom", geo=False, compression="snappy", n=40, only=("text",))
write("other-name", geometry="shape", compression="snappy", n=40, only=("text",))
write("no-geometry", shaped=False, compression="snappy", n=60)
write("empty", n=0, compression="snappy", only=("text", "i32"))
write("zstd", compression="zstd", n=40, only=("text",))
write("lz4", compression="lz4", n=40, only=("text",))
write("brotli", compression="brotli", n=40, only=("text",))
for name, why in (("zstd", "ZSTD-compressed pages are not supported"), ("lz4", "a codec that is not read (7)"), ("brotli", "a codec that is not read (4)")):
    expected["files"][name] = {"refused": why}

with open(OUT + "expected.json", "w") as f:
    json.dump(expected, f, ensure_ascii=False, separators=(",", ":"))
