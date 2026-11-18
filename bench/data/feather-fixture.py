# bench/npm/pages/data/stations.feather and stations.parquet: three stations in plane IX (EPSG:6677) as geopandas' `to_feather`
# lays a file out (WKB geometry, the `geo` metadata with a PROJJSON CRS, LZ4 buffers), written by pyarrow.
# The files are committed; this script only says how they were made.
# Usage: python3 bench/data/feather-fixture.py (needs pyarrow; made with 23.0.1)
import json
import struct

import pyarrow as pa
import pyarrow.feather as feather

# Name, x and y in EPSG:6677 (proj4js of the longitude and latitude in bench/data/pack-fixtures.mjs), riders.
ROWS = [("東京", -5995.185, -35367.230, 462589), ("有楽町", -6366.3, -36044.0, 169550), ("神田", -5651.2, -34191.3, 98560)]
CRS = {
    "$schema": "https://proj.org/schemas/v0.7/projjson.schema.json",
    "type": "ProjectedCRS",
    "name": "JGD2011 / Japan Plane Rectangular CS IX",
    "id": {"authority": "EPSG", "code": 6677},
}
GEO = {"primary_column": "geometry", "columns": {"geometry": {"encoding": "WKB", "crs": CRS, "geometry_types": ["Point"]}}, "version": "1.0.0"}

table = pa.table(
    {
        "name": [r[0] for r in ROWS],
        "riders": pa.array([r[3] for r in ROWS], pa.int64()),
        "opened": pa.array([0, 86400 * 365, None], pa.timestamp("s")),
        "geometry": pa.array([struct.pack("<BIdd", 1, 1, r[1], r[2]) for r in ROWS], pa.binary()),
    }
).replace_schema_metadata({"geo": json.dumps(GEO)})
feather.write_feather(table, "bench/npm/pages/data/stations.feather", compression="lz4")

# bench/npm/pages/data/stations.parquet: the same rows as GeoParquet (GZIP pages, so that the browser
# inflates them), in two row groups.
import pyarrow.parquet as pq

pq.write_table(table, "bench/npm/pages/data/stations.parquet", compression="gzip", row_group_size=2)
