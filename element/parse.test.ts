import assert from "node:assert/strict";
import test from "node:test";
import { MAX_PITCH, MAX_ZOOM, checkBoolean, checkPadding, parseBearing, parseBoolean, parseCenter, parsePadding, parsePitch, parseWorkerCount, parseZoom } from "./parse.ts";

test("center is two in-range decimals", () => {
  assert.deepEqual(parseCenter("139.7671,35.6812"), { lng: 139.7671, lat: 35.6812 });
  assert.deepEqual(parseCenter(" -180 , 90 "), { lng: -180, lat: 90 });
  for (const bad of ["", "1", "1,2,3", "181,0", "0,-91", "1e2,0", "0x10,0", "NaN,0", "Infinity,0", "1,,2", "a,b"]) {
    assert.equal(parseCenter(bad), null, bad);
  }
});

test("zoom is a decimal from 0 to MAX_ZOOM", () => {
  assert.equal(parseZoom("14.5"), 14.5);
  assert.equal(parseZoom(String(MAX_ZOOM)), MAX_ZOOM);
  for (const bad of ["", "-1", "23", "1e1", "Infinity", "NaN", "12px", " "]) {
    assert.equal(parseZoom(bad), null, bad);
  }
});

test("worker count is 0 to MAX_WORKERS", () => {
  assert.equal(parseWorkerCount("0"), 0);
  assert.equal(parseWorkerCount("4"), 4);
  for (const bad of ["5", "-1", "1.0", "", "01"]) {
    assert.equal(parseWorkerCount(bad), null, bad);
  }
});

test("bearing is any decimal; pitch is a decimal from 0 to MAX_PITCH", () => {
  assert.equal(parseBearing("-45.5"), -45.5);
  assert.equal(parseBearing("720"), 720);
  assert.equal(parsePitch("30"), 30);
  assert.equal(parsePitch(String(MAX_PITCH)), MAX_PITCH);
  for (const bad of ["", "1e1", "NaN", "Infinity", "10deg"]) assert.equal(parseBearing(bad), null, bad);
  for (const bad of ["", "-1", "86", "1e1", "NaN"]) assert.equal(parsePitch(bad), null, bad);
});

test("parseBoolean: only true and false", () => {
  assert.equal(parseBoolean("true"), true);
  assert.equal(parseBoolean("false"), false);
  for (const bad of ["", "TRUE", "1", "no", " false"]) assert.equal(parseBoolean(bad), null);
});

test("checkBoolean: the render-world-copies property takes booleans only", () => {
  assert.equal(checkBoolean(true), true);
  assert.equal(checkBoolean(false), false);
  for (const bad of [0, 1, null, undefined, "yes", {}]) assert.equal(checkBoolean(bad), null);
});

test("padding is four pixel counts, 0 or more, or one for all four", () => {
  assert.deepEqual(parsePadding("0, 20,40,320"), { top: 0, right: 20, bottom: 40, left: 320 });
  assert.deepEqual(parsePadding("12.5"), { top: 12.5, right: 12.5, bottom: 12.5, left: 12.5 });
  for (const bad of ["", "1,2", "1,2,3", "1,2,3,4,5", "-1", "0,0,0,-5", "1e2", "10px", "a,b,c,d", "Infinity", "1,,2,3"]) {
    assert.equal(parsePadding(bad), null, bad);
  }
  assert.deepEqual(checkPadding(8), { top: 8, right: 8, bottom: 8, left: 8 });
  assert.deepEqual(checkPadding({ top: 1, right: 2, bottom: 3, left: 4 }), { top: 1, right: 2, bottom: 3, left: 4 });
  assert.equal(checkPadding({ top: 1, right: 2, bottom: 3 } as never), null);
  assert.equal(checkPadding({ top: NaN, right: 0, bottom: 0, left: 0 }), null);
  assert.equal(checkPadding(-1), null);
});
