.pragma library

// The shapes of the cars the widget can draw: a side profile for the panel icon and a
// top-down plan for the card, for each model TeslaMate knows. Everything is in units of
// 10 mm. The lengths, widths, heights, overhangs and wheelbases are Tesla's own figures,
// and the outlines follow the side and top views in Tesla's owner's manuals.

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
    // 5021 long, 1431 high, 2960 between the axles: lower and longer, with a long hood
    // and a roof that runs out into a lip over the tail.
    "s": {
        width: 510.1, height: 147.1, wheels: [114.0, 410.0], wheelY: 111.9, tire: 31.2, hub: 15,
        body: "M 66.3 133 C 52 132.5 36 130.5 24 126.5 C 16 124 8 121 5.5 115 C 3.5 108 3 98 4.5 92 C 6 87 10 83.5 11.5 77 C 13.5 69 14.5 60 14 52 C 13.8 48 13 45.5 13 44 C 22 43 32 42 41 40 C 56 36 70 29.5 86 24 C 126 11 172 4 216 4 C 244 4 262 6.5 280 11 C 308 18.5 336 31 362 43.5 C 368 46.5 376 49 386 50.5 C 410 54 432 56.5 452 61 C 470 65.5 486 73 498 80.5 C 503 84 506 89 506.5 95 C 507 103 506.5 112 505 119 C 503.5 125 499 129.5 492 131 C 482 133 470 133 457.7 133",
        sill: [161.7, 362.3, 133], fillY: 121, fillArch: 43.2,
        rear: "C 54.5 120.7 32.4 119.6 17 110.7 C 12 94.5 19.2 94 22.8 81.2 C 25.2 72.7 26.1 63.9 26.1 55.1 C 31.8 53.4 37.8 53.2 43.5 51.7 C 51.1 49.8 58.5 47.1 65.8 44.4",
        belt: [[65.8, 44.4], [426.1, 68.4]],
        front: "C 447.4 71.8 466.6 76.5 485.6 87.1 C 488.3 88.6 492 90.1 493.7 93 C 495.7 96.6 494.8 102.3 494.5 106.2 C 494.3 110.2 494.3 114.7 492.1 118.1 C 483.1 122.3 462.2 121 452.2 121",
        bolt: [256, 76, 0.99]
    },
    // 5057 long, 1680 high, 2965 between the axles: one arc from the hood to the
    // spoiler, over tall windows.
    "x": {
        width: 513.7, height: 172.0, wheels: [114.4, 410.9], wheelY: 134.8, tire: 33.2, hub: 16,
        body: "M 64.7 149 C 54 148 40 144.5 26 141 C 17 138.5 10 134 8 127 C 5.5 120 4 110 4.5 101 C 5 92 7 84 7.3 76 C 7.6 66 7 56 6.5 48 C 6.2 43 5.5 40 6.5 37 C 13 35 20 34 27 33.5 C 40 32 52 28.5 64 24.5 C 104 11.5 150 4 200 4 C 232 4 252 5.5 270 8.5 C 304 15 334 26.5 364 40 C 370 43 376 47 384 49.5 C 404 53.5 424 57 442 60.5 C 462 65 480 71.5 496 78.5 C 503 82 508 88 509 95 C 510 106 510 118 509.5 128 C 509 135 505 140 498 142 C 487 145.5 474 149 460.6 149",
        sill: [164.1, 361.2, 149], fillY: 137, fillArch: 45.2,
        rear: "C 59.8 136.6 26.2 131.2 20.4 125.1 C 19.1 123.7 18.6 121 18.2 119.2 C 14.6 104.7 18.4 92.1 19.2 77.8 C 19.7 69.6 19.3 61.3 18.8 53.1",
        belt: [[18.8, 53.1], [464.2, 79.1]],
        front: "C 471.4 81.5 494.2 87.9 496.8 95.4 C 498.2 99.6 497.7 105.5 497.8 109.9 C 497.9 116.1 498.6 123.3 496.9 129.2 C 485.4 135.3 468.9 136.9 456 137",
        bolt: [256, 84, 1.16]
    },
    // 4750 long, 1624 high, 2890 between the axles: the Model 3's nose under a taller
    // cabin that ends in a hatch.
    "y": {
        width: 483.0, height: 166.4, wheels: [102.6, 391.6], wheelY: 130.8, tire: 31.6, hub: 15,
        body: "M 54.5 149 C 44 146.5 30 141 18 136 C 12 134 8 131 6.5 126 C 4.5 119 3.5 106 5 96 C 6.5 90 10 84 11.5 76 C 12.5 68 12 58 10 50 C 9.5 46.5 9 44 9.5 42.5 C 13 40.5 19 40.5 25 39.5 C 37 36.5 49 31.5 61 27.5 C 100 15 150 4 200 4 C 232 4 250 7 268 11 C 296 19 322 33 346 45 C 352 48.5 358 51.5 366 54 C 384 58 402 62 420 66.5 C 438 71.5 454 79 468 86.5 C 474 90 478 95 479 101 C 479.5 110 479 120 478 128 C 477 135 474 140 468 143 C 460 146.5 450 148.5 439.7 149",
        sill: [150.7, 343.5, 149], fillY: 137, fillArch: 43.6,
        rear: "L 54.8 136.7 C 48.9 136 23.5 126 18.2 122.8 C 16.3 115.6 15 104.6 17.1 97.3 C 19 90.9 22.2 85 23.3 78.4 C 24.7 69.8 24.1 60.9 22.7 52.4 L 33.4 49.7",
        belt: [[33.4, 49.7], [390.0, 71.7]],
        front: "C 414.3 77.3 432.6 82 455.1 93.3 C 459 95.3 464.4 97.1 466.6 101.3 C 468.4 104.7 466.9 119.2 466.4 123.6 C 466.2 125.8 466.1 128.6 464.8 130.5 C 461.1 135.8 440.7 136.9 434.8 137",
        bolt: [241, 85, 1.12]
    },
    // 5683 long, 1791 high, 3635 between the axles: straight lines to a peak over the
    // front seats, and a bed behind the cabin whose sides rise to the roof.
    "cybertruck": {
        width: 576.3, height: 183.1, wheels: [121, 484.5], wheelY: 139.2, tire: 39.9, hub: 19,
        body: "M 64.6 154 L 50 151.5 L 24 148.5 L 12 144 L 4.5 138 L 4.5 115 L 12.5 108.5 L 8.5 49 C 8.5 48 9.5 47.3 11 47 L 290 7 C 310 4.3 322 3.5 337 3.5 L 342 4 L 488 49 L 566 78.5 C 569.5 80 571.5 82 571.5 85 L 572 124 L 564 128 L 563 146 L 547 150.5 L 540.9 154",
        sill: [177.4, 428.1, 154], fillY: 142, fillArch: 51.9,
        rear: "L 52 139.7 L 26.5 136.6 L 16.5 132.5 L 16.5 120.7 L 20.1 117.8 C 23 115.5 24.6 111.5 24.5 107.7 L 21.1 57.6 L 204.2 31.4 L 199.1 52.7",
        belt: [[199.1, 52.7], [510.7, 70.4]],
        front: "L 559.5 88.9 L 560 117 L 552 121.5 L 551.3 137 L 546 139 L 536.3 142",
        bolt: [296, 84, 1.23]
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

// A closed chain moved dx across the car, for the left side, or its mirror image on the
// right side of a car that is w wide.
function placed(points, dx, w) {
    var moved = points.map(function (p) {
        var q = p.slice();
        for (var i = 0; i < q.length; i += 2) q[i] = w === undefined ? q[i] + dx : w - (q[i] + dx);
        return q;
    });
    return chain(moved) + " Z";
}

// A chain of which the part outside the flank is drawn only share of the way out: 0
// leaves it on the flank and 1 where the chain has it. For the left side, or mirrored on
// the right side of a car that is w wide.
function reached(points, flank, share, w, closed) {
    var moved = points.map(function (p) {
        var q = p.slice();
        for (var i = 0; i < q.length; i += 2) {
            var x = q[i] < flank ? flank - (flank - q[i]) * share : q[i];
            q[i] = w === undefined ? x : w - x;
        }
        return q;
    });
    return chain(moved) + (closed ? " Z" : "");
}

// A mirror's outline as a path inside its door, which is w wide: the mirror swings with
// it. points gives [out, along]: how far out from the body's flank, and how far behind the
// door's front edge. base is how far the flank is outside the door's own outer edge.
function mirrorPath(points, base, w, onLeft) {
    var moved = points.map(function (p) {
        var q = p.slice();
        for (var i = 0; i < q.length; i += 2) q[i] = onLeft ? -(base + q[i]) : w + base + q[i];
        return q;
    });
    return chain(moved);
}

// The plan of a car, nose up, in a box that ends at the mirror tips. Across the car x
// starts at the left mirror's tip, and along it y starts at the nose. A plan is built
// from:
//   w, length       the box across, and the car's length
//   flank           x of the body's side along the doors, which is straight. The fenders
//                   in front of it and the haunches behind it stand out a little further
//   belt            x of the side windows' outer edge
//   frontAxle, rearAxle, tire   where the wheels are, and half a tire's length
//   body            the body's left outline from the nose to the tail, as a function of
//                   where the flank really is: whoever draws the car moves that long
//                   straight edge onto whole pixels
//   hood, trunk     the lids, as { points, top, bottom } for symmetric()
//   creases         lines pressed into the hood, on the left side
//   panes, beams    the windshield and the glass over the cabin, and the beams between
//                   them. rear is the rear window: with hatch set it is part of the trunk
//                   lid and opens with it
//   sidePanes       glass over the cabin that does not reach across its middle, on the
//                   left side
//   frontWindow, rearWindow   the two side windows that open, and quarter the fixed
//                   glass, as closed chains whose outer edge is on the belt
//   frontDoor, rearDoor       where each door starts and ends along the car
//   headlight, taillight      a lens on the left side, and headlightLine, taillightLine
//                   the light in it
//   mirror          its outline for mirrorPath()
//   port            where the charge port is
//   sentryY, lockY  where the two signs go on the glass
//   falcon          for rear doors that lift like wings: see the Model X
//   trim            black parts outside the body, on the left side
//   slats           lines across the trunk lid
function makePlan(s) {
    var w = s.w;
    var sym = function (o) { return symmetric(w, o.points, o.top, o.bottom); };
    var each = function (list, closed) {
        return (list || []).map(function (c) { return onBothSides(w, c, closed); }).join(" ");
    };
    var base = s.panes[0];
    // All the glass over the cabin and the beams in it, as one outline: the left edges of
    // the pieces that reach the cabin's side, one after the other from the windshield's
    // foot. A body that is not opaque has this cut out of it in one piece, since the edges
    // of holes that touch would show as hairlines.
    var sides = (s.sidePanes || []).map(function (c) {
        return c.filter(function (q, i) { return i === 0 || endOf(q)[0] < w / 4; });
    });
    var edge = [];
    s.panes.concat(s.beams, [s.rear]).map(function (o) { return o.points; }).concat(sides)
        .filter(function (c) { return c[0][0] < w / 4; })
        .sort(function (a, b) { return a[0][1] - b[0][1]; })
        .forEach(function (c) {
            c.forEach(function (q, i) {
                var last = edge.length ? endOf(edge[edge.length - 1]) : null;
                if (i === 0 && last && last[0] === q[0] && last[1] === q[1]) return;
                edge.push(q);
            });
        });
    return {
        boxWidth: w,
        boxHeight: Math.ceil(s.length),
        length: s.length,
        flank: s.flank,
        belt: s.belt,
        wheelInset: s.wheelInset === undefined ? 4 : s.wheelInset,
        tire: s.tire,
        frontAxle: s.frontAxle,
        rearAxle: s.rearAxle,
        frontDoor: s.frontDoor,
        rearDoor: s.rearDoor,
        sentryY: s.sentryY,
        lockY: s.lockY,
        port: s.port,
        hatch: !!s.hatch,
        falcon: s.falcon || null,
        mirror: s.mirror,
        frontWindow: s.frontWindow,
        rearWindow: s.rearWindow,
        // How long the windshield is, which is all the room a sign on it has.
        windshieldLength: endOf(base.points[base.points.length - 1])[1] - base.points[0][1],
        // From where to where, along the car, the light on the hood, on the trunk lid and
        // on the glass is spread.
        hoodSpan: [s.hood.points[0][1], endOf(s.hood.points[s.hood.points.length - 1])[1]],
        trunkSpan: [s.trunk.points[0][1], endOf(s.trunk.points[s.trunk.points.length - 1])[1]],
        glassSpan: [base.points[0][1], endOf(s.rear.points[s.rear.points.length - 1])[1]],
        bodyLeft: s.body,
        bodyPath: function (flank) { return symmetric(w, s.body(flank)); },
        frunkPath: sym(s.hood),
        trunkPath: sym(s.trunk),
        creasePath: each(s.creases, false),
        slatPath: s.slats || "",
        trimPath: each(s.trim, true),
        glassPath: s.panes.map(sym).concat(each(s.sidePanes, true)).join(" "),
        rearGlassPath: sym(s.rear),
        canopyPath: symmetric(w, edge, base.top, s.rear.bottom),
        beamPath: s.beams.map(sym).join(" "),
        quarterPath: s.quarter ? onBothSides(w, s.quarter, true) : "",
        headlightPath: onBothSides(w, s.headlight, true),
        headlightLine: onBothSides(w, s.headlightLine, false),
        taillightPath: onBothSides(w, s.taillight, true),
        taillightLine: onBothSides(w, s.taillightLine, false)
    };
}

var PLANS = {};

// 4694 long, 1850 wide, 2875 between the axles. A round nose, a windshield that bows
// forward, glass from there to a short trunk lid, with one beam over the front seats'
// backs.
PLANS["3"] = function () {
    return makePlan({
        w: 209, length: 469.4, flank: 14.25, belt: 27, frontAxle: 84, rearAxle: 371.5, tire: 33,
        body: function (f) {
            return [[104.5, 0],
                    [88, 0, 56, 10.5, 33, 24], [23, 31.5, 15.5, 44, 12.8, 60], [11.9, 72, 12.3, 84, 12.3, 98],
                    [12.3, 120], [12.3, 132, f, 138, f, 150],
                    [f, 333], [f, 343, 12.9, 346, 12.9, 356], [12.9, 392],
                    [12.9, 402, 14.6, 412, 17.5, 420], [20.3, 428, 25.5, 440, 32.5, 450],
                    [39, 459, 52, 463.5, 68, 466], [80, 468, 92, 469.4, 104.5, 469.4]];
        },
        hood: { points: [[104.5, 9], [88, 9, 66, 12, 54, 21], [48, 32, 40.5, 62, 35.5, 92], [31.5, 123]], bottom: [62, 99] },
        creases: [[[57, 104], [59, 80, 66, 48, 76, 22]]],
        panes: [
            { points: [[32.5, 127], [35, 140, 40.5, 178, 43.5, 200], [44.5, 208, 45.2, 215, 45.5, 222]], top: [64, 102.3], bottom: [72, 210] },
            { points: [[46.2, 227], [47, 290]], top: [72, 215], bottom: [75, 290] }
        ],
        beams: [
            { points: [[45.5, 222], [46.2, 227]], top: [72, 210], bottom: [72, 215] },
            { points: [[47, 290], [47.2, 296]], top: [75, 290], bottom: [75, 296] }
        ],
        rear: { points: [[47.2, 296], [47.6, 320, 49, 355, 51, 388], [52.5, 401, 57, 413, 66, 420.5]], top: [75, 296], bottom: [86, 433] },
        trunk: { points: [[63, 422.5], [42.5, 442], [43, 449, 62, 453.5, 104.5, 453.5]], top: [85, 436] },
        frontWindow: [[27, 141], [29.5, 151, 33.5, 186, 36, 206], [37.3, 220, 38.4, 245, 38.6, 266], [27, 266]],
        rearWindow: [[27, 272], [38.7, 272], [39.1, 295, 39.9, 320, 40.7, 338], [27, 338]],
        quarter: [[27, 343], [40.9, 343], [41.6, 362, 41.9, 385, 40.6, 398], [36, 386, 28, 366, 27, 343]],
        frontDoor: [152, 268], rearDoor: [270, 340],
        headlight: [[58, 15.2], [48, 18.8, 36, 25, 28, 32.5], [22.5, 38, 18.5, 45.5, 18.3, 52], [18.2, 58, 22, 64.5, 27.5, 66],
                    [30, 58, 36, 48, 42, 40], [47, 33.5, 52.5, 26, 58, 21]],
        headlightLine: [[54, 18.3], [45, 21.5, 36, 27, 29.5, 33.5], [26, 37, 23.5, 41, 21.5, 45.5]],
        taillight: [[18, 408], [19.5, 420, 25, 436, 34.5, 448.7], [43, 457, 58, 462.5, 76, 465.2], [76, 459.5],
                    [60, 457.5, 46, 451, 37.5, 441.5], [31, 433, 26.5, 420, 25, 410], [22.5, 408.5, 20, 408, 18, 408]],
        taillightLine: [[22.5, 417], [26, 430, 33, 442.5, 42, 451], [50, 456.5, 60, 459.5, 70, 461.3]],
        mirror: [[0, 11], [4, 13.5, 9, 18, 12.8, 22.5], [13.8, 25.5, 13.5, 28.5, 12, 29.5], [8, 26.5, 4, 23, 0, 21]],
        port: [20.8, 414], sentryY: 166, lockY: 258
    });
};

// 4750 long, 1921 wide, 2890 between the axles. A blunter nose than the Model 3's, wide
// haunches, and one pane of glass from the windshield to the hatch.
PLANS["y"] = function () {
    return makePlan({
        w: 216.1, length: 475, flank: 13.9, belt: 25.5, frontAxle: 87.4, rearAxle: 376.4, tire: 35,
        body: function (f) {
            return [[108.05, 0],
                    [86, 0, 60, 5.5, 40, 16.8], [30, 22, 20.5, 27.5, 16.8, 36.2], [15.2, 42.5, f, 51, f, 62],
                    [f, 322], [f, 334, 12.2, 338, 12.2, 350], [12.2, 398],
                    [12.2, 408, 14.2, 418, 17.6, 426], [20.5, 433.5, 23.5, 441.5, 28.2, 448],
                    [33, 454, 40, 456.5, 48.2, 459.5], [56, 462.5, 64, 468, 73.4, 471.2], [84, 474.3, 96, 475, 108.05, 475]];
        },
        hood: { points: [[108.05, 10], [90, 10, 70, 13, 58, 21], [48, 31, 40, 56, 36.5, 84], [33, 124]], bottom: [62, 94.7] },
        creases: [[[58, 102], [60, 78, 67, 48, 77, 23]]],
        panes: [
            { points: [[33.5, 129], [35.5, 142, 39, 172, 41.3, 198], [41.6, 203, 41.8, 207, 41.9, 211]], top: [64, 96.2], bottom: [72, 199.3] },
            { points: [[42.2, 216], [43.5, 238, 46, 280, 48.7, 335], [49.3, 345, 49.8, 353, 50.1, 360]], top: [72, 204.3], bottom: [76, 360] }
        ],
        beams: [
            { points: [[41.9, 211], [42.2, 216]], top: [72, 199.3], bottom: [72, 204.3] },
            { points: [[50.1, 360], [50.4, 366]], top: [76, 360], bottom: [76, 366] }
        ],
        rear: { points: [[50.4, 366], [51.3, 382, 52.6, 400, 54.3, 420], [55.5, 434, 60, 444, 70, 451]], top: [76, 366], bottom: [88, 459] },
        hatch: true,
        trunk: { points: [[66, 453.5], [48.5, 462], [50.5, 466.5, 72, 468.5, 108.05, 468.5]], top: [88, 461.5] },
        frontWindow: [[25.5, 143], [28, 153, 32.5, 186, 35, 206], [36.5, 222, 37.8, 246, 38.3, 266], [25.5, 266]],
        rearWindow: [[25.5, 272], [38.6, 272], [39.4, 292, 41, 318, 42.3, 340], [32.5, 340], [30, 318, 25.5, 296, 25.5, 272]],
        quarter: [[33.2, 345], [42.6, 345], [43.5, 362, 44.6, 382, 44.5, 398], [41, 385, 36, 362, 33.2, 345]],
        frontDoor: [152, 270], rearDoor: [272, 343],
        headlight: [[57.5, 15.5], [48, 18, 37, 22.5, 30, 28], [25, 32, 21.5, 38, 21, 45], [20.8, 50.5, 22.5, 56, 26, 58],
                    [28.5, 50, 34, 42, 40, 35.5], [45.5, 29.5, 51.5, 24.5, 57.5, 20.5]],
        headlightLine: [[54, 18.5], [46, 21, 37, 25, 31.5, 29.5], [27.5, 33, 24.5, 38, 23.5, 44]],
        taillight: [[16.5, 412], [18.5, 424, 23.5, 437.5, 30.5, 446.5], [38, 453.5, 50, 458, 63, 463.5], [63, 458],
                    [52, 454.5, 42, 448.5, 35.5, 440], [29.5, 431.5, 25.5, 421, 24, 412], [21.5, 410.5, 18.5, 410.5, 16.5, 412]],
        taillightLine: [[21, 420], [24.5, 432, 30, 442, 37.5, 448.5], [44, 453, 52, 456.5, 60, 459.5]],
        mirror: [[0, -2], [4, 0, 9, 6, 12, 13], [13, 17, 12.6, 21.5, 11, 23], [7, 19.5, 3.5, 15.5, 0, 12]],
        port: [19.5, 414], sentryY: 160, lockY: 285
    });
};

// 5021 long, 1987 wide, 2960 between the axles. A long hood, slim lights, and glass that
// narrows all the way to a lip over the tail.
PLANS["s"] = function () {
    return makePlan({
        w: 222.7, length: 502.1, flank: 15.6, belt: 22.5, frontAxle: 96.1, rearAxle: 392.1, tire: 35,
        body: function (f) {
            return [[111.35, 0],
                    [98, 0, 86, 0.8, 76, 3], [50, 9, 29.7, 22.4, 20.9, 40], [18, 46, 14.8, 52, 13.8, 60],
                    [13.4, 66, 13.6, 70, 13.6, 76], [13.6, 118], [13.6, 130, f, 134, f, 146],
                    [f, 332], [f, 344, 12.2, 350, 12.2, 362], [12.2, 418],
                    [12.4, 425, 15.5, 430, 17.9, 436], [19.2, 443.5, 23.8, 464.9, 29.4, 469.5],
                    [34.4, 473.6, 40.7, 475.7, 46.4, 478.5], [53, 481.8, 61, 489.3, 68.1, 492.8], [80, 498.6, 95, 502.1, 111.35, 502.1]];
        },
        hood: { points: [[111.35, 9.5], [92, 9.5, 72, 12, 60, 17], [47, 24, 36, 38, 33.5, 58], [31.5, 80, 31, 110, 31.5, 138]], bottom: [62, 105.3] },
        creases: [[[66, 112], [70, 80, 82, 40, 96, 18]]],
        panes: [
            { points: [[32, 142], [33, 160, 35, 188, 37, 208], [37.3, 212, 37.6, 216, 37.8, 219]], top: [66, 107.3], bottom: [74, 206.3] },
            { points: [[38.2, 224], [40.3, 243, 43.5, 300, 46.3, 345], [46.9, 355, 47.3, 364, 47.6, 372]], top: [74, 211.3], bottom: [80, 372] }
        ],
        beams: [
            { points: [[37.8, 219], [38.2, 224]], top: [74, 206.3], bottom: [74, 211.3] },
            { points: [[47.6, 372], [47.9, 378]], top: [80, 372], bottom: [80, 378] }
        ],
        rear: { points: [[47.9, 378], [48.6, 392, 49.6, 407, 50.7, 420], [52, 436, 56, 447, 66, 457]], top: [80, 378], bottom: [90, 469] },
        hatch: true,
        trunk: { points: [[62, 459.5], [45, 474], [47, 482, 70, 487, 111.35, 487]], top: [90, 472] },
        frontWindow: [[22.5, 150], [24.5, 160, 28.5, 190, 31.5, 212], [34, 232, 35.8, 258, 36.6, 281], [22.5, 281]],
        rearWindow: [[22.5, 287], [36.9, 287], [37.6, 310, 38.4, 335, 38.8, 356], [27.5, 356], [25.5, 334, 22.8, 310, 22.5, 287]],
        quarter: [[28, 361], [38.9, 361], [39.3, 378, 39.6, 393, 39, 405], [36, 395, 31, 378, 28, 361]],
        frontDoor: [160, 284], rearDoor: [286, 358],
        headlight: [[63, 9.8], [52, 13, 40, 20.5, 31, 30], [25.5, 36, 21, 43, 18.8, 50], [20, 52.5, 21.5, 53, 23, 52],
                    [26, 43.5, 31, 36.5, 36, 31.5], [44, 24, 53, 19, 63, 15.5]],
        headlightLine: [[59, 13], [49, 16.5, 39, 23.5, 32, 31], [28, 35.5, 24.5, 41, 22, 46.5]],
        taillight: [[20, 452], [22.5, 462, 28, 470.5, 36, 475.5], [44, 480, 52, 485, 62, 489.5], [62, 484],
                    [53, 480, 45, 475.5, 39, 471], [32, 465.5, 28, 458, 26.5, 451], [24, 449.5, 21.5, 450, 20, 452]],
        taillightLine: [[24.5, 458], [28, 466, 33, 472, 40, 476.5], [47, 480.5, 53, 483.5, 59, 486]],
        mirror: [[0, 10], [4, 13, 9, 20, 12, 28], [13, 32, 12.6, 36.5, 11, 37.5], [7, 33, 3.5, 27, 0, 23]],
        port: [23, 444], sentryY: 172, lockY: 270
    });
};

// 5057 long, 1999 wide, 2965 between the axles. The windshield reaches back over the
// front seats, the rear doors carry the roof's glass on either side of a spine, and the
// side windows lean far in.
PLANS["x"] = function () {
    return makePlan({
        w: 223.9, length: 505.7, flank: 16, belt: 22.5, frontAxle: 98.8, rearAxle: 395.3, tire: 37,
        body: function (f) {
            return [[111.95, 0],
                    [98, 0, 92, 0.6, 87.5, 1.5], [75.5, 3.5, 64.5, 7, 53.5, 12.5], [44, 17.5, 33, 23, 28, 29],
                    [23.8, 34.2, 21.9, 40.2, 19, 46], [16.3, 51.3, 14.3, 57.1, 13.3, 63], [12.4, 68, 12, 74, 12, 82],
                    [12, 112], [12, 124, f, 128, f, 140],
                    [f, 338], [f, 348, 11.6, 352, 11.6, 362], [11.6, 424],
                    [11.8, 432, 15.5, 438, 18.6, 446.3], [20.3, 456.1, 23.5, 475.3, 31.3, 481.7],
                    [36.8, 486.2, 44.2, 489, 50.5, 492.2], [56.3, 495.1, 62.9, 499.1, 69.5, 500.2], [79, 501.8, 92, 505.7, 111.95, 505.7]];
        },
        hood: { points: [[111.95, 10], [92, 10, 72, 12.5, 60, 18], [46, 25, 33, 38, 29.5, 58], [27.5, 78, 27.5, 100, 29, 119]], bottom: [62, 99] },
        creases: [[[64, 100], [68, 74, 80, 40, 94, 19]]],
        panes: [
            { points: [[30.5, 123], [31, 150, 35, 180, 38.7, 200], [42, 222, 44.5, 255, 45.3, 286]], top: [64, 100.3], bottom: [74, 283] }
        ],
        sidePanes: [[[45.6, 291], [46.3, 320, 47.6, 360, 49, 395], [102, 395], [102, 291]]],
        beams: [
            { points: [[45.3, 286], [45.6, 291]], top: [74, 283] },
            { points: [[102, 291], [102, 395]] },
            { points: [[49, 395], [49.3, 401]] }
        ],
        rear: { points: [[49.3, 401], [50.5, 425, 52.5, 450, 55.3, 470], [57, 476, 62, 479.5, 69, 480.5]], bottom: [92, 484.3] },
        hatch: true,
        trunk: { points: [[66, 484], [49, 487.5], [51, 493, 72, 496, 111.95, 496]], top: [92, 487.6] },
        frontWindow: [[22.5, 142], [25.5, 150, 30.5, 178, 34, 200], [37, 220, 39.5, 250, 40.8, 280], [22.5, 280]],
        rearWindow: [[22.5, 288], [41.2, 288], [42.5, 310, 43.2, 360, 43.5, 396], [31.5, 396], [29, 370, 24, 318, 22.5, 288]],
        quarter: [[32.5, 402], [43.6, 402], [44, 418, 44.3, 434, 43.8, 445], [41, 436, 35.5, 418, 32.5, 402]],
        frontDoor: [156, 284], rearDoor: [286, 398],
        // The rear doors are hinged along the spine and lift like wings, in two leaves:
        // the upper one, with the roof's glass, stands up steeply, and the lower one,
        // the door's side, lies out flat above the roof and over the body's side, about
        // 30 further than the body. wing is an open door from above, on the left. Its
        // tip is the sill it left, which is shorter than the door because the door is
        // cut around the rear wheel. fold is where the two leaves meet, glass the pane in
        // each of them, seam how far across the roof a closed door's edges run, and back
        // where an open door ends beside the body.
        falcon: {
            wing: [[102, 290], [-8, 293], [-12, 293, -12, 297, -12, 301], [-12, 334], [-12, 342, -6, 350, 2, 358],
                   [10, 367, 16, 384, 24, 396], [102, 395]],
            fold: [[88, 290.5], [88, 395]],
            glass: [[[99, 296], [91.5, 296], [91.5, 390], [99, 390]],
                    [[84.5, 296], [47, 296.5], [47, 381], [84.5, 390]]],
            seam: 45.6, back: 358
        },
        headlight: [[62, 11], [54, 14, 44, 19.5, 36, 25], [29.5, 29.5, 24.5, 36, 21, 44.5], [22, 47, 23.5, 47.5, 25, 46.5],
                    [28, 40, 33, 34.5, 39, 30.5], [47, 25, 55, 20.5, 62, 17.5]],
        headlightLine: [[58.5, 14.5], [50, 18, 42, 22.5, 36, 27.5], [31, 31.5, 27, 36.5, 24.5, 42]],
        taillight: [[20.5, 458], [22, 468, 26.5, 478, 33.5, 483], [41, 487.5, 50, 491.5, 60, 495.5], [60, 490],
                    [51, 486.5, 43, 482.5, 37.5, 478.5], [31.5, 473.5, 28.5, 466, 27, 457.5], [24.5, 456, 22, 456.3, 20.5, 458]],
        taillightLine: [[25, 463.5], [27.5, 471.5, 31.5, 477.5, 38, 481.5], [44.5, 485.5, 51, 488.5, 57, 491]],
        mirror: [[0, -3], [4, 0, 9, 8, 12.5, 17], [13.5, 21, 13, 25.5, 11.5, 27], [7.5, 22, 3.5, 16, 0, 12]],
        port: [22.5, 452], sentryY: 170, lockY: 240
    });
};

// 5683 long, 2032 wide over its fender flares, 3635 between the axles. Flat steel
// with no curve in it: a light bar across the nose, a windshield from the hood to the
// roof's peak, and behind the cabin the bed under its cover, which is the trunk here.
PLANS["cybertruck"] = function () {
    var slats = [];
    for (var y = 403; y < 550; y += 13) slats.push("M 51 " + y + " H 190.3");
    return makePlan({
        w: 241.3, length: 568.3, flank: 22.5, belt: 33.5, frontAxle: 87.8, rearAxle: 451.3, tire: 44, wheelInset: 16,
        body: function (f) {
            return [[120.65, 0.5], [84, 2.5], [54, 10], [35, 22], [24.5, 35], [f, 46], [f, 557], [26, 568.3], [120.65, 568.3]];
        },
        hood: { points: [[120.65, 7.5], [85, 9], [57, 16], [40, 27], [31, 38.5], [31, 71]], bottom: [70, 58.3] },
        panes: [
            { points: [[31.5, 75], [50, 236]], top: [70, 61] },
            { points: [[50, 242], [49.5, 358]] }
        ],
        beams: [
            { points: [[50, 236], [50, 242]] },
            { points: [[49.5, 358], [49.5, 364]] }
        ],
        rear: { points: [[49.5, 364], [50.5, 386]] },
        trunk: { points: [[47, 390], [47, 553]] },
        slats: slats.join(" "),
        trim: [[[24.5, 33], [20.3, 45], [19.5, 57], [19.5, 120], [20.3, 132], [24.5, 144]],
               [[24.5, 396], [20.3, 408], [19.5, 420], [19.5, 484], [20.3, 496], [24.5, 508]]],
        quarter: [[33.5, 95], [36.5, 115, 38.5, 135, 40.8, 150], [33.5, 150]],
        frontWindow: [[33.5, 154], [41.2, 154], [42.3, 165, 43.5, 172, 43.5, 180], [43.5, 258], [33.5, 258]],
        rearWindow: [[33.5, 264], [43.5, 264], [43.3, 356], [33.5, 356]],
        frontDoor: [152, 260], rearDoor: [262, 362],
        headlight: [[120.65, 2.5], [98, 3, 77, 5.3, 58, 10.5], [45, 14.5, 33, 24.5, 26, 35.5], [28.5, 37],
                    [35, 27, 46.5, 17.5, 59.5, 13.3], [78, 8.3, 99, 6, 120.65, 5.6]],
        headlightLine: [[119, 4], [98, 4.6, 77, 6.8, 58.8, 11.9], [46, 16, 34.5, 25.5, 27.7, 35.6]],
        taillight: [[120.65, 566.3], [28.5, 566.3], [25, 560.5], [27, 559.5], [30, 563.3], [120.65, 563.3]],
        taillightLine: [[119, 564.8], [30, 564.8]],
        mirror: [[0, 0], [7, 7, 15, 17, 20.5, 24.5], [21.8, 26.5, 21.5, 29, 20, 29.5], [13, 25, 6, 20, 0, 16.5]],
        port: [26, 516], sentryY: 150, lockY: 300
    });
};

var planCache = {};

// The plan of a model from KEYS.
function plan(key) {
    var k = PLANS[key] ? key : "3";
    if (!planCache[k]) planCache[k] = PLANS[k]();
    return planCache[k];
}
