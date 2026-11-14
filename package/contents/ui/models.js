.pragma library

// The shapes of the cars the widget can draw: a side profile for the panel icon and a
// top-down plan for the card, for each model TeslaMate knows. Everything is in units of
// 10 mm and uses the cars' real length, width, height and wheelbase.

// ---------- which model ----------

// The models in the order of the settings' list, after "Automatic".
var KEYS = ["s", "3", "x", "y", "cybertruck"];

// The model to draw. setting is the settings' choice: 0 goes by what TeslaMate reports in
// its model topic ("S", "3", "X" or "Y"), and 1 to 5 name a model from KEYS. A missing or
// unknown report gives the Model 3, which is what the widget drew before it knew others.
function modelKey(setting, reported) {
    var i = Math.round(Number(setting));
    if (i >= 1 && i <= KEYS.length) return KEYS[i - 1];
    var s = String(reported === undefined || reported === null ? "" : reported)
        .toLowerCase().replace(/[^a-z0-9]/g, "").replace(/^tesla/, "").replace(/^model/, "");
    if (s === "s" || s === "x" || s === "y" || s === "3") return s;
    if (s === "c" || s === "ct" || s.indexOf("cyber") === 0) return "cybertruck";
    return "3";
}

// ---------- paths ----------

function r2(v) { return Math.round(v * 100) / 100; }

// A chain of lines and curves as an SVG path. points starts with [x, y]; after it [x, y]
// is a line to there and [c1x, c1y, c2x, c2y, x, y] a curve.
function chain(points) {
    var out = ["M", r2(points[0][0]), r2(points[0][1])];
    for (var i = 1; i < points.length; i++) {
        out.push(points[i].length === 2 ? "L" : "C");
        for (var j = 0; j < points[i].length; j++) out.push(r2(points[i][j]));
    }
    return out.join(" ");
}

function endOf(segment) { return [segment[segment.length - 2], segment[segment.length - 1]]; }

// The same chain on the other side of a car that is w wide, run backwards.
function mirrored(w, points) {
    var out = [];
    for (var i = points.length - 1; i >= 1; i--) {
        var to = endOf(points[i - 1]);
        var p = points[i];
        if (p.length === 2) out.push("L", r2(w - to[0]), r2(to[1]));
        else out.push("C", r2(w - p[2]), r2(p[3]), r2(w - p[0]), r2(p[1]), r2(w - to[0]), r2(to[1]));
    }
    return out.join(" ");
}

// A closed shape that is the same on both sides of the car, from its left half: a chain
// from the front to the rear. Where the chain doesn't start or end on the car's middle,
// top and bottom give the control point, on the left, of the curve that crosses over.
function symmetric(w, points, top, bottom) {
    var first = points[0];
    var last = endOf(points[points.length - 1]);
    var out = [chain(points)];
    if (Math.abs(last[0] - w / 2) > 0.001) {
        if (bottom) out.push("C", r2(bottom[0]), r2(bottom[1]), r2(w - bottom[0]), r2(bottom[1]), r2(w - last[0]), r2(last[1]));
        else out.push("L", r2(w - last[0]), r2(last[1]));
    }
    out.push(mirrored(w, points));
    if (Math.abs(first[0] - w / 2) > 0.001 && top)
        out.push("C", r2(w - top[0]), r2(top[1]), r2(top[0]), r2(top[1]), r2(first[0]), r2(first[1]));
    out.push("Z");
    return out.join(" ");
}

// A chain drawn on the left side of the car and again, mirrored, on the right.
function onBothSides(w, points, closed) {
    var other = points.map(function (p) {
        return p.length === 2 ? [w - p[0], p[1]] : [w - p[0], p[1], w - p[2], p[3], w - p[4], p[5]];
    });
    return chain(points) + (closed ? " Z " : " ") + chain(other) + (closed ? " Z" : "");
}

// Where a chain that runs down the car's left side is at y, across the car. Along each of
// its pieces y only grows, so the place on a curve is found by halving.
function edgeAt(points, y) {
    for (var i = 1; i < points.length; i++) {
        var from = endOf(points[i - 1]);
        var p = points[i];
        var to = endOf(p);
        if (y < from[1] || y > to[1]) continue;
        if (p.length === 2)
            return to[1] === from[1] ? from[0] : from[0] + (to[0] - from[0]) * (y - from[1]) / (to[1] - from[1]);
        var along = function (axis, t) {
            var s = 1 - t;
            return s * s * s * from[axis] + 3 * s * s * t * p[axis] + 3 * s * t * t * p[2 + axis] + t * t * t * to[axis];
        };
        var before = 0;
        var after = 1;
        for (var k = 0; k < 16; k++) {
            var t = (before + after) / 2;
            if (along(1, t) < y) before = t;
            else after = t;
        }
        return along(0, (before + after) / 2);
    }
    return endOf(points[points.length - 1])[0];
}

function circlePath(cx, cy, r) {
    return ["M", r2(cx - r), r2(cy), "A", r, r, 0, 1, 0, r2(cx + r), r2(cy),
            "A", r, r, 0, 1, 0, r2(cx - r), r2(cy), "Z"].join(" ");
}

// ---------- side profiles ----------

// Where the line through p with direction d meets the line through a and b.
function meet(p, d, a, b) {
    var ex = b[0] - a[0];
    var ey = b[1] - a[1];
    var t = ((a[0] - p[0]) * ey - (a[1] - p[1]) * ex) / (d[0] * ey - d[1] * ex);
    return [p[0] + d[0] * t, p[1] + d[1] * t];
}

function pt(p) { return r2(p[0]) + " " + r2(p[1]); }

// A side profile, nose right, for a battery icon: an outline, the part of the body below
// the windows as the fill, the same fill with a bolt-shaped gap through it, and the bolt.
// s gives:
//   width, height   the icon's box
//   wheels          [rear, front] axle, with wheelY the height of both
//   tire, hub       the radius of the wheel's outline and of the dot in the fill
//   body            the outline from the rear wheel arch over the roof to the front one
//   sill            the outline's bottom edge between the arches, [from, to, y]
//   fillY, fillArch the fill's bottom edge and the radius it keeps clear around a wheel
//   rear            the fill from its rear arch up to where the straight edge under the
//                   windows starts, belt its two ends, front the fill from there down to
//                   the front arch
//   bolt            [x, y, scale]: its middle and its size, 1 being 90 high
function profile(s) {
    var xr = s.wheels[0];
    var xf = s.wheels[1];
    var dy = s.fillY - s.wheelY;
    var dx = Math.sqrt(s.fillArch * s.fillArch - dy * dy);
    var arch = function (x) {
        return "L " + r2(x + dx) + " " + s.fillY + " A " + s.fillArch + " " + s.fillArch + " 0 1 0 " + r2(x - dx) + " " + s.fillY;
    };
    var hubs = " " + circlePath(xr, s.wheelY, s.hub) + " " + circlePath(xf, s.wheelY, s.hub);
    var from = s.belt[0];
    var to = s.belt[1];

    // The bolt, drawn around (240, 73), moved and scaled.
    var place = function (x, y) { return [s.bolt[0] + (x - 240) * s.bolt[2], s.bolt[1] + (y - 73) * s.bolt[2]]; };
    var bolt = [[254, 28], [218, 80], [236, 80], [226, 118], [262, 64], [244, 64]]
        .map(function (p) { return pt(place(p[0], p[1])); });
    // The gap around it: on its left the bolt's own edges moved out, on its right one line.
    var floor = [[0, s.fillY], [1, s.fillY]];
    var a = place(202.7, 88);
    var b = place(225.7, 88);
    var c = place(234.3, 120);
    var topLeft = meet(a, [36, -52], from, to);
    var bottomLeft = meet(b, [-10, 38], floor[0], floor[1]);
    var topRight = meet(c, [36, -54], from, to);
    var bottomRight = meet(c, [36, -54], floor[0], floor[1]);

    return {
        boxWidth: s.width,
        boxHeight: s.height,
        outlinePath: s.body + " M " + s.sill[0] + " " + s.sill[2] + " L " + s.sill[1] + " " + s.sill[2]
            + " " + circlePath(xr, s.wheelY, s.tire) + " " + circlePath(xf, s.wheelY, s.tire),
        fillPath: "M " + pt(from) + " L " + pt(to) + " " + s.front + " " + arch(xf) + " " + arch(xr)
            + " " + s.rear + " Z" + hubs,
        chargingFillPath: "M " + pt(from) + " L " + pt(topLeft) + " L " + pt(a) + " L " + pt(b)
            + " L " + pt(bottomLeft) + " " + arch(xr) + " " + s.rear + " Z"
            + " M " + pt(topRight) + " L " + pt(to) + " " + s.front + " " + arch(xf)
            + " L " + pt(bottomRight) + " Z" + hubs,
        boltPath: "M " + bolt.join(" L ") + " Z"
    };
}

var PROFILES = {
    // 4694 long, 1443 high, 2875 between the axles.
    "3": {
        width: 477.4, height: 148.3, wheels: [102, 389.5], wheelY: 114.9, tire: 29.4, hub: 14,
        body: "M 56 131.4 C 44 130 32 126.5 20 120 C 12 108 6 90 4 70 C 4 60 7 50 11 44 C 12 42 14 41 18 41 C 64 34 124 8 224 4 C 266 4 300 24 330 40 C 338 44.5 349 47 362 49 C 389 53 424 60 449 70 C 461 75 469 86 472 95 C 474 104 473 116 467 124 C 463 130 456 132 449 132 L 435.4 132",
        sill: [147.9, 343.6, 132], fillY: 120, fillArch: 41.4,
        rear: "L 54 120 C 44 119 37 116 32 112 C 26 103 20 89 17.5 72 C 17 66 18 60 22 56 C 34 52 46 48 58 47",
        belt: [[58, 47], [326, 58]],
        front: "C 344 59.5 354 60 362 61 C 389 65 416 70.5 442 81 C 451 85 456 92 459 99 C 461 105 461 112 456 116 C 453 119 449 120 444 120",
        bolt: [240, 73, 1]
    },
    // 4970 long, 1445 high, 2960 between the axles: lower and longer, with a long hood
    // and a roof that runs out into the tail.
    "s": {
        width: 505, height: 148.5, wheels: [112, 408], wheelY: 114, tire: 30.5, hub: 14.5,
        body: "M 65 131.5 C 50 130.5 34 127 22 120.5 C 13 110 6 94 4 77 C 3.5 68 6 59 10 54 C 12 51.5 15 50.5 19 50 C 76 42 150 9 244 4 C 288 4 322 25 354 43 C 363 47.5 376 49.5 390 51.5 C 420 55.5 455 62 480 72 C 491 77 498 88 500.5 97 C 502 106 501 117.5 495 125 C 491 130.5 484 132 477 132 L 455 132",
        sill: [159, 361, 132], fillY: 120, fillArch: 42.5,
        rear: "L 62 120 C 50 119 41 116 35 112 C 28 104 21 92 18 78 C 17.5 72 19 67 23 64 C 35 60 48 57 60 56",
        belt: [[60, 56], [350, 61.5]],
        front: "C 368 62.5 380 63.5 390 64.5 C 420 68.5 447 73.5 472 83.5 C 481 87.5 486 94 488 101 C 490 107 489.5 113 485 117 C 482 119.5 478 120 473 120",
        bolt: [258, 74, 1]
    },
    // 5057 long, 1680 high, 2965 between the axles: one arc from the hood to the tail.
    "x": {
        width: 513.7, height: 172, wheels: [117, 413.5], wheelY: 136, tire: 32, hub: 15,
        body: "M 68.5 155 C 54 154 38 150.5 24 143 C 14 130 7 108 5 86 C 4.5 72 6.5 60 10.5 54 C 12.5 51.5 15.5 50.5 19.5 50 C 56 32 138 6 252 4 C 300 4 338 28 372 54 C 381 60 393 63.5 407 66 C 434 71 465 78 487 89 C 498 95 505 105 508 115 C 510 125 509 138 503 147 C 499 153.5 492 155.5 485 155.5 L 462 155.5",
        sill: [165.5, 365, 155.5], fillY: 143.5, fillArch: 44,
        rear: "L 66 143.5 C 54 142.5 44 139 37 134 C 30 123 22 106 19 88 C 18.5 81 20 75 24 71.5 C 36 67.5 49 64.5 62 63.5",
        belt: [[62, 63.5], [368, 74]],
        front: "C 385 76 397 77.5 407 79 C 433 84 459 90.5 480 100.5 C 489 105 494 112 496 119 C 498 126 497.5 133.5 492.5 138.5 C 489.5 142 485.5 143.5 480.5 143.5",
        bolt: [265, 84, 1.14]
    },
    // 4751 long, 1624 high, 2890 between the axles: the Model 3's nose under a taller
    // cabin that ends in a hatch.
    "y": {
        width: 483.1, height: 166.4, wheels: [102, 391], wheelY: 131.5, tire: 31, hub: 14.5,
        body: "M 54.5 149.5 C 42 148.5 30 145 19 138 C 11 125 6 102 5 80 C 5 66 7 55 11 49.5 C 13 47 16 46 20 45.5 C 54 28 118 6 228 4 C 272 4 308 26 340 50 C 348 55.5 360 58.5 374 61 C 402 65.5 433 72.5 455 83 C 467 89 475 100 478 110 C 480 120 479 133 473 141.5 C 469 148 462 150 455 150 L 438.5 150",
        sill: [149.5, 343.5, 150], fillY: 138, fillArch: 43,
        rear: "L 52 138 C 43 137 36 134 31 130 C 25 120 20 103 18.5 83 C 18 76 19.5 70 23.5 67 C 35 63 47 60 58 59",
        belt: [[58, 59], [336, 69.5]],
        front: "C 353 71.5 365 73 374 74.5 C 401 79 427 85 449 95 C 458 99.5 463 107 465.5 114 C 467.5 121 467 128.5 462 133.5 C 459 136.5 455 138 450 138",
        bolt: [247, 80, 1.1]
    },
    // 5683 long, 1791 high, 3635 between the axles: straight lines to a peak over the
    // front seats, and a bed behind the cabin whose sides rise to the roof.
    "cybertruck": {
        width: 576.3, height: 183, wheels: [117, 480.5], wheelY: 142, tire: 37, hub: 17,
        body: "M 63 163 L 34 163 L 7 133 L 5 56 L 12 51 L 346 4 L 356 4 L 478 60 L 566 82 L 572 90 L 572 135 L 553 163 L 534.5 163",
        sill: [171, 426.5, 163], fillY: 151, fillArch: 49,
        rear: "L 40 151 L 19 128 L 17.5 64 L 196 39 L 222 76",
        belt: [[222, 76], [468, 76]],
        front: "L 474 73 L 558 94 L 560 97 L 560 131 L 547 151",
        bolt: [320, 90, 1.12]
    }
};

var profileCache = {};

// The side profile of a model from KEYS: { boxWidth, boxHeight, outlinePath, fillPath,
// chargingFillPath, boltPath }.
function sideProfile(key) {
    var k = PROFILES[key] ? key : "3";
    if (!profileCache[k]) profileCache[k] = profile(PROFILES[k]);
    return profileCache[k];
}

// ---------- plans ----------

// The plan of a car, nose up, in a box that ends at the mirror tips: the body starts 12
// units in from the left, so what lies on the left flank (doors, side windows, mirrors,
// the charge port) is at the same place across every model, and the right side mirrors it.
//
// A plan has numbers (boxWidth, boxHeight, length, frontAxle, rearAxle, the doors' and
// windows' ends along the car, where the glyphs go) and paths. Its long straight edges
// are moved onto whole pixels by whoever draws it, so the paths that have such an edge are
// functions: of flank, where the body's left edge is, or of roofEdge, where the glass
// over the cabin starts.
//
// The four models that share the Model 3's lines take its nose and tail, stretched to
// their own width and length:
//   w, length       the box across, and the car's length
//   nose, tail      how much longer the curves of the nose and of the tail are than on
//                   the Model 3
//   frunk           where the hood ends
//   glass           six rows across the cabin, [x, y, bow, control]: the foot and top of
//                   the windshield, the two ends of the roof glass and of the rear window.
//                   x is where the row starts on the left, or null for roofEdge, bow how
//                   far its middle lies behind its ends, control where its curve's
//                   control point is
//   spine           half the width of a roof beam along the middle of the roof glass
//   trunk           [x, y] where the lid starts on the left
function sedanPlan(s) {
    var w = s.w;
    var mid = w / 2;
    var len = s.length;
    var kx = (w - 24) / 185;
    var X = function (x) { return 12 + (x - 12) * kx; };
    var N = function (y) { return y * s.nose; };
    var T = function (y) { return len - (469.4 - y) * s.tail; };

    var bodyLeft = function (flank) {
        return [[mid, 0],
                [X(64), 0, X(29), N(6), X(20.5), N(34)],
                [X(15.5), N(50), X(13), N(72), flank, N(104)],
                [flank, T(330)],
                [flank, T(385), X(13.5), T(422), X(16.5), T(441)],
                [X(20.5), T(459), X(44), T(466.5), X(74), T(468.5)],
                [X(86), len, X(96), len, mid, len]];
    };
    var row = function (i, roofEdge) {
        var g = s.glass[i];
        return [g[0] === null ? roofEdge : g[0], g[1], g[2], g[3]];
    };
    // The glass between two rows, or with a spine the two panes beside it.
    var pane = function (a, b, spine) {
        if (spine) {
            var left = [[a[0], a[1]], [mid - spine, a[1] + a[2] * 0.75], [mid - spine, b[1] + b[2] * 0.75], [b[0], b[1]]];
            return onBothSides(w, left, true);
        }
        return ["M", a[0], a[1], "C", a[3], a[1] + a[2], w - a[3], a[1] + a[2], w - a[0], a[1],
                "L", w - b[0], b[1], "C", w - b[3], b[1] + b[2], b[3], b[1] + b[2], b[0], b[1], "Z"].join(" ");
    };

    return {
        boxWidth: w,
        boxHeight: Math.ceil(len),
        length: len,
        frontAxle: s.frontAxle,
        rearAxle: s.rearAxle,
        frontDoor: s.frontDoor,
        rearDoor: s.rearDoor,
        frontWindow: s.frontWindow,
        rearWindow: s.rearWindow,
        sentryY: s.sentryY,
        lockY: s.lockY,
        windshieldLength: s.glass[1][1] - s.glass[0][1] - 2,
        hoodSpan: [N(9), s.frunk + 6],
        trunkSpan: [s.trunk[1], T(459)],
        glassSpan: [s.glass[0][1], s.glass[5][1] + s.glass[5][2]],
        bodyLeft: bodyLeft,
        bodyPath: function (flank) { return symmetric(w, bodyLeft(flank)); },
        frunkPath: symmetric(w, [[mid, N(9)], [X(70), N(9), X(40), N(14), X(33), N(38)], [X(35), s.frunk]],
                             null, [X(67), s.frunk + 6]),
        trunkPath: symmetric(w, [[s.trunk[0], s.trunk[1]], [X(35), T(436)], [X(45), T(453), X(72), T(459), mid, T(459)]],
                             [s.trunk[0] + 25, s.trunk[1] + 5]),
        glassPath: function (roofEdge) {
            return [pane(row(0, roofEdge), row(1, roofEdge)),
                    pane(row(2, roofEdge), row(3, roofEdge), s.spine),
                    pane(row(4, roofEdge), row(5, roofEdge))].join(" ");
        },
        beamPath: function (roofEdge) {
            return [pane(row(1, roofEdge), row(2, roofEdge)), pane(row(3, roofEdge), row(4, roofEdge))].join(" ");
        },
        headlightPath: onBothSides(w, [[X(70.3), N(3.8)],
                                       [X(52), N(6.7), X(30.1), N(11.6), X(22.2), N(34.5)],
                                       [X(21.2), N(38), X(20.4), N(41.5), X(19.7), N(45.5)],
                                       [X(23.5), N(43.5), X(28.5), N(41), X(31.6), N(37.6)],
                                       [X(37.3), N(20.1), X(51.8), N(13.8), X(68.7), N(10.3)]], true),
        headlightLine: onBothSides(w, [[X(64.5), N(7.7)], [X(51.9), N(10.3), X(33.7), N(15.9), X(27.2), N(33.5)]], false),
        taillightPath: onBothSides(w, [[X(16.2), T(420)],
                                       [X(16.7), T(428), X(17.4), T(435), X(18.3), T(440.7)],
                                       [X(23.7), T(459.9), X(48), T(464.7), X(74.1), T(466.7)],
                                       [X(74.1), T(466.7), X(73.2), T(459.2), X(73.2), T(459.2)],
                                       [X(52), T(457.5), X(31.5), T(451.5), X(25), T(436.5)],
                                       [X(22.5), T(430.5), X(18.5), T(424.5), X(16.2), T(420)]], true),
        taillightLine: onBothSides(w, [[X(21), T(434)], [X(25.5), T(455), X(49), T(461), X(70), T(462.8)]], false)
    };
}

// The Cybertruck has no curve on it: a flat nose with a light bar across it, a cabin
// that is all glass from the hood to the bed, and the bed's cover as its trunk.
function truckPlan() {
    var w = 227;
    var mid = w / 2;
    var len = 568.3;
    var bodyLeft = function (flank) {
        return [[mid, 0], [37, 1.5], [21, 14], [flank, 42], [flank, 544], [19.5, 561], [33, len], [mid, len]];
    };
    var pane = function (a, b) {
        return ["M", a[0], a[1], "L", w - a[0], a[1], "L", w - b[0], b[1], "L", b[0], b[1], "Z"].join(" ");
    };
    return {
        boxWidth: w,
        boxHeight: Math.ceil(len),
        length: len,
        frontAxle: 92,
        rearAxle: 455.5,
        frontDoor: [150, 262],
        rearDoor: [266, 350],
        frontWindow: [176, 260],
        rearWindow: [268, 344],
        sentryY: 166,
        lockY: 282,
        windshieldLength: 116,
        hoodSpan: [10, 114],
        trunkSpan: [356, 548],
        glassSpan: [122, 346],
        bodyLeft: bodyLeft,
        bodyPath: function (flank) { return symmetric(w, bodyLeft(flank)); },
        frunkPath: symmetric(w, [[mid, 10], [42, 11], [32, 22], [34, 114]]),
        trunkPath: symmetric(w, [[mid, 356], [36, 356], [34, 358], [34, 546], [36, 548], [mid, 548]]),
        glassPath: function (roofEdge) {
            return [pane([38, 122], [roofEdge, 240]), pane([roofEdge, 246], [roofEdge, 320]),
                    pane([roofEdge, 326], [50, 346])].join(" ");
        },
        beamPath: function (roofEdge) {
            return [pane([roofEdge, 240], [roofEdge, 246]), pane([roofEdge, 320], [roofEdge, 326])].join(" ");
        },
        headlightPath: onBothSides(w, [[mid, 3.5], [38, 4.5], [24.5, 15], [22, 21.5], [27, 17.5], [39.5, 8], [mid, 7]], true),
        headlightLine: onBothSides(w, [[mid - 2, 5.3], [39, 6.3], [26, 16.5]], false),
        taillightPath: onBothSides(w, [[mid, 564.8], [34, 564.8], [23, 551], [26, 549.5], [35.5, 561.3], [mid, 561.3]], true),
        taillightLine: onBothSides(w, [[mid - 2, 563], [35, 563]], false)
    };
}

var PLANS = {
    // 4694 long, 1850 wide, 2875 between the axles.
    "3": function () {
        return sedanPlan({
            w: 209, length: 469.4, nose: 1, tail: 1, frontAxle: 84, rearAxle: 371.5,
            frunk: 110, trunk: [50, 397],
            glass: [[37, 118, 6, 67], [null, 198, 4, 75], [null, 204, 4, 75],
                    [null, 292, 3, 75], [null, 298, 3, 75], [50, 390, 5, 75]],
            frontDoor: [152, 266], rearDoor: [270, 336], frontWindow: [178, 264], rearWindow: [272, 330],
            sentryY: 162, lockY: 250
        });
    },
    // 4970 long, 1964 wide, 2960 between the axles. A long hood, and a rear window that
    // runs most of the way to the tail and leaves a short lid.
    "s": function () {
        return sedanPlan({
            w: 220.4, length: 497, nose: 1.16, tail: 1.1, frontAxle: 93, rearAxle: 389,
            frunk: 128, trunk: [50, 438],
            glass: [[37, 136, 6, 68], [null, 218, 4, 78], [null, 224, 4, 78],
                    [null, 312, 3, 78], [null, 318, 3, 78], [50, 431, 5, 78]],
            frontDoor: [168, 284], rearDoor: [288, 356], frontWindow: [194, 282], rearWindow: [290, 350],
            sentryY: 180, lockY: 270
        });
    },
    // 5057 long, 1999 wide, 2965 between the axles. The windshield reaches back over the
    // front seats, and behind it the roof's glass is in the two rear doors, with a spine
    // between them.
    "x": function () {
        return sedanPlan({
            w: 223.9, length: 505.7, nose: 1.04, tail: 0.92, frontAxle: 96, rearAxle: 392.5,
            frunk: 120, trunk: [48, 446], spine: 13,
            glass: [[37, 128, 6, 69], [null, 262, 4, 79], [null, 268, 4, 79],
                    [null, 350, 3, 79], [null, 356, 3, 79], [48, 439, 5, 79]],
            frontDoor: [164, 280], rearDoor: [284, 358], frontWindow: [190, 278], rearWindow: [286, 352],
            sentryY: 172, lockY: 232
        });
    },
    // 4751 long, 1921 wide, 2890 between the axles. One long pane of glass over the
    // cabin, then the hatch: a short window and little of the tail behind it.
    "y": function () {
        return sedanPlan({
            w: 216.1, length: 475.1, nose: 0.98, tail: 0.88, frontAxle: 88, rearAxle: 377,
            frunk: 114, trunk: [48, 426],
            glass: [[37, 122, 6, 68], [null, 204, 4, 77], [null, 210, 4, 77],
                    [null, 334, 3, 77], [null, 340, 3, 77], [48, 419, 5, 77]],
            frontDoor: [158, 274], rearDoor: [278, 344], frontWindow: [184, 272], rearWindow: [280, 338],
            sentryY: 166, lockY: 272
        });
    },
    // 5683 long, 2032 wide, 3635 between the axles.
    "cybertruck": truckPlan
};

var planCache = {};

// The plan of a model from KEYS.
function plan(key) {
    var k = PLANS[key] ? key : "3";
    if (!planCache[k]) planCache[k] = PLANS[k]();
    return planCache[k];
}
