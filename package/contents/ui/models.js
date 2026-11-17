.pragma library

// The shapes the widget draws for each model: a side profile for the panel icon and a
// top-down plan for the card. One unit is 10 mm. Dimensions are Tesla's published figures;
// outlines follow the side and top views in the owner's manuals.

// ---------- which model ----------

// In the order of the Model setting's choices, after "Automatic".
const KEYS = ["s", "3", "x", "y", "cybertruck"];

// The key of the model to draw. setting 1 to 5 picks from KEYS; 0 uses TeslaMate's model
// topic ("S", "3", "X" or "Y"). Unknown or missing falls back to the Model 3.
function modelKey(setting, reported) {
    const choice = Math.round(Number(setting));
    if (choice >= 1 && choice <= KEYS.length) return KEYS[choice - 1];
    const name = String(reported === undefined || reported === null ? "" : reported)
        .toLowerCase().replace(/[^a-z0-9]/g, "").replace(/^tesla/, "").replace(/^model/, "");
    if (["s", "3", "x", "y"].includes(name)) return name;
    if (name === "c" || name === "ct" || name.startsWith("cyber")) return "cybertruck";
    return "3";
}

// The trim TeslaMate's trim_badging (the API's vehicle_config.trim_badging) names, as a
// key for QML to word: "plaid", "performance", "dual" (dual motor) or "". Only the clear
// patterns count: "74D" is dual motor, "P74D" performance, anything with "plaid" plaid.
// Anything else, such as "50" or "74", gives "" rather than a guess.
function trimKey(badging) {
    const b = String(badging === undefined || badging === null ? "" : badging).trim().toLowerCase();
    if (b.includes("plaid")) return "plaid";
    const match = /^(p?)\d+(d?)$/.exec(b);
    if (!match) return "";
    return match[1] ? "performance" : match[2] ? "dual" : "";
}

// A wheel_type such as "Pinwheel18" or "Induction20Black" as {name, inches}: the name split
// into words and the rim size in inches, without what follows the size. null for a value
// that doesn't start with a name and a size.
function wheelInfo(wheelType) {
    const match = /^([A-Za-z]+?)(\d{2})(?!\d)/.exec(String(wheelType === undefined || wheelType === null ? "" : wheelType).trim());
    if (!match) return null;
    let name = match[1].replace(/([a-z])([A-Z])/g, "$1 $2");
    // Tesla's own spelling.
    if (/^uber turbine$/i.test(name)) name = "Überturbine";
    return { name: name, inches: Number(match[2]) };
}

// Whether TeslaMate's spoiler_type (the API's vehicle_config.spoiler_type) means the car
// has a spoiler: anything but "None" or nothing, such as "Passive".
function hasSpoiler(spoilerType) {
    const t = String(spoilerType === undefined || spoilerType === null ? "" : spoilerType).trim().toLowerCase();
    return t !== "" && t !== "none" && t !== "<invalid>";
}

// ---------- paths ----------

function round2(v) { return Math.round(v * 100) / 100; }

// An SVG path from a chain of points. The first is [x, y]; after that [x, y] is a line
// to that point and [c1x, c1y, c2x, c2y, x, y] a cubic curve.
function chain(points) {
    const out = ["M", round2(points[0][0]), round2(points[0][1])];
    for (let i = 1; i < points.length; i++) {
        out.push(points[i].length === 2 ? "L" : "C");
        for (let j = 0; j < points[i].length; j++) out.push(round2(points[i][j]));
    }
    return out.join(" ");
}

// The end point of one piece of a chain, and of the whole chain.
function endOf(segment) { return [segment[segment.length - 2], segment[segment.length - 1]]; }
function chainEnd(points) { return endOf(points[points.length - 1]); }

// The path of the chain mirrored across a car w wide, run backwards.
function mirrored(w, points) {
    const out = [];
    for (let i = points.length - 1; i >= 1; i--) {
        const to = endOf(points[i - 1]);
        const p = points[i];
        if (p.length === 2) out.push("L", round2(w - to[0]), round2(to[1]));
        else out.push("C", round2(w - p[2]), round2(p[3]), round2(w - p[0]), round2(p[1]), round2(w - to[0]), round2(to[1]));
    }
    return out.join(" ");
}

// A closed, left-right symmetric shape from its left half: a chain from front to rear.
// If the chain doesn't start or end on the centerline, top and bottom give the left
// control point of the curve that crosses over (a straight line if omitted).
function symmetric(w, points, top, bottom) {
    const first = points[0];
    const last = chainEnd(points);
    const out = [chain(points)];
    if (Math.abs(last[0] - w / 2) > 0.001) {
        if (bottom) out.push("C", round2(bottom[0]), round2(bottom[1]), round2(w - bottom[0]), round2(bottom[1]), round2(w - last[0]), round2(last[1]));
        else out.push("L", round2(w - last[0]), round2(last[1]));
    }
    out.push(mirrored(w, points));
    if (Math.abs(first[0] - w / 2) > 0.001 && top)
        out.push("C", round2(w - top[0]), round2(top[1]), round2(top[0]), round2(top[1]), round2(first[0]), round2(first[1]));
    out.push("Z");
    return out.join(" ");
}

// The chain with every x coordinate passed through moveX.
function mapX(points, moveX) {
    return points.map(p => p.map((value, i) => i % 2 === 0 ? moveX(value) : value));
}

// The chain on the left side and, mirrored, on the right.
function onBothSides(w, points, closed) {
    const other = mapX(points, x => w - x);
    return chain(points) + (closed ? " Z " : " ") + chain(other) + (closed ? " Z" : "");
}

// The x of a chain running down the car's left side, at a given y. y only increases
// along each piece, so a curve is solved by bisection.
function edgeAt(points, y) {
    for (let i = 1; i < points.length; i++) {
        const from = endOf(points[i - 1]);
        const p = points[i];
        const to = endOf(p);
        if (y < from[1] || y > to[1]) continue;
        if (p.length === 2)
            return to[1] === from[1] ? from[0] : from[0] + (to[0] - from[0]) * (y - from[1]) / (to[1] - from[1]);
        const along = (axis, t) => {
            const s = 1 - t;
            return s * s * s * from[axis] + 3 * s * s * t * p[axis] + 3 * s * t * t * p[2 + axis] + t * t * t * to[axis];
        };
        let before = 0;
        let after = 1;
        for (let k = 0; k < 16; k++) {
            const t = (before + after) / 2;
            if (along(1, t) < y) before = t;
            else after = t;
        }
        return along(0, (before + after) / 2);
    }
    return chainEnd(points)[0];
}

function circlePath(cx, cy, r) {
    return ["M", round2(cx - r), round2(cy), "A", r, r, 0, 1, 0, round2(cx + r), round2(cy),
            "A", r, r, 0, 1, 0, round2(cx - r), round2(cy), "Z"].join(" ");
}

// ---------- side profiles ----------

// The intersection of the line through p with direction d and the line through a and b.
function meet(p, d, a, b) {
    const ex = b[0] - a[0];
    const ey = b[1] - a[1];
    const t = ((a[0] - p[0]) * ey - (a[1] - p[1]) * ex) / (d[0] * ey - d[1] * ex);
    return [p[0] + d[0] * t, p[1] + d[1] * t];
}

function xy(p) { return round2(p[0]) + " " + round2(p[1]); }

// Builds a side profile (nose right) for the battery icon: the outline, the fill (the
// body below the windows), the fill with a bolt-shaped gap, and the bolt.
// spec:
//   width, height    the icon's box
//   wheels, wheelY   [rear, front] axle x, and their shared y
//   tire, hub        radius of the wheel's outline, and of the dot in the fill
//   body             outline path from the rear wheel arch, over the roof, to the front arch
//   sill             the outline's bottom edge between the arches, [from, to, y]
//   fillY, fillArch  the fill's bottom edge, and the radius it keeps clear around a wheel
//   rear, front      fill paths: rear arch up to the belt, and belt down to the front arch
//   belt             the two ends of the fill's straight top edge, under the windows
//   bolt             [x, y, scale]: its center and size (scale 1 is 90 high)
function profile(spec) {
    const [rearAxle, frontAxle] = spec.wheels;
    const [beltStart, beltEnd] = spec.belt;
    const [sillStart, sillEnd, sillY] = spec.sill;
    const [boltX, boltY, boltScale] = spec.bolt;
    const wheels = radius => `${circlePath(rearAxle, spec.wheelY, radius)} ${circlePath(frontAxle, spec.wheelY, radius)}`;
    // Where the fill's bottom edge goes around a wheel.
    const dy = spec.fillY - spec.wheelY;
    const dx = Math.sqrt(spec.fillArch * spec.fillArch - dy * dy);
    const arch = x => `L ${round2(x + dx)} ${spec.fillY} A ${spec.fillArch} ${spec.fillArch} 0 1 0 ${round2(x - dx)} ${spec.fillY}`;

    // The bolt is defined around (240, 73), then moved and scaled.
    const place = (x, y) => [boltX + (x - 240) * boltScale, boltY + (y - 73) * boltScale];
    const bolt = [[254, 28], [218, 80], [236, 80], [226, 118], [262, 64], [244, 64]]
        .map(([x, y]) => xy(place(x, y)));
    // The gap around the bolt: parallel to the bolt's edges on the left, one line on the right.
    const floor = [[0, spec.fillY], [1, spec.fillY]];
    const a = place(202.7, 88);
    const b = place(225.7, 88);
    const c = place(234.3, 120);
    const topLeft = meet(a, [36, -52], beltStart, beltEnd);
    const bottomLeft = meet(b, [-10, 38], floor[0], floor[1]);
    const topRight = meet(c, [36, -54], beltStart, beltEnd);
    const bottomRight = meet(c, [36, -54], floor[0], floor[1]);

    return {
        boxWidth: spec.width,
        boxHeight: spec.height,
        outlinePath: `${spec.body} M ${sillStart} ${sillY} L ${sillEnd} ${sillY} ${wheels(spec.tire)}`,
        fillPath: `M ${xy(beltStart)} L ${xy(beltEnd)} ${spec.front} ${arch(frontAxle)} ${arch(rearAxle)} ${spec.rear} Z`
            + ` ${wheels(spec.hub)}`,
        chargingFillPath: `M ${xy(beltStart)} L ${xy(topLeft)} L ${xy(a)} L ${xy(b)} L ${xy(bottomLeft)} ${arch(rearAxle)} ${spec.rear} Z`
            + ` M ${xy(topRight)} L ${xy(beltEnd)} ${spec.front} ${arch(frontAxle)} L ${xy(bottomRight)} Z`
            + ` ${wheels(spec.hub)}`,
        boltPath: `M ${bolt.join(" L ")} Z`
    };
}

const PROFILES = {
    // 4694 long, 1443 high, 2875 wheelbase (mm).
    "3": {
        width: 477.4, height: 148.3, wheels: [102, 389.5], wheelY: 114.9, tire: 29.4, hub: 14,
        body: "M 56 131.4 C 44 130 32 126.5 20 120 C 12 108 6 90 4 70 C 4 60 7 50 11 44 C 12 42 14 41 18 41 C 64 34 124 8 224 4 C 266 4 300 24 330 40 C 338 44.5 349 47 362 49 C 389 53 424 60 449 70 C 461 75 469 86 472 95 C 474 104 473 116 467 124 C 463 130 456 132 449 132 L 435.4 132",
        sill: [147.9, 343.6, 132], fillY: 120, fillArch: 41.4,
        rear: "L 54 120 C 44 119 37 116 32 112 C 26 103 20 89 17.5 72 C 17 66 18 60 22 56 C 34 52 46 48 58 47",
        belt: [[58, 47], [326, 58]],
        front: "C 344 59.5 354 60 362 61 C 389 65 416 70.5 442 81 C 451 85 456 92 459 99 C 461 105 461 112 456 116 C 453 119 449 120 444 120",
        bolt: [240, 73, 1]
    },
    // 5021 long, 1431 high, 2960 wheelbase.
    "s": {
        width: 510.1, height: 147.1, wheels: [114.0, 410.0], wheelY: 111.9, tire: 31.2, hub: 15,
        body: "M 66.3 133 C 52 132.5 36 130.5 24 126.5 C 16 124 8 121 5.5 115 C 3.5 108 3 98 4.5 92 C 6 87 10 83.5 11.5 77 C 13.5 69 14.5 60 14 52 C 13.8 48 13 45.5 13 44 C 22 43 32 42 41 40 C 56 36 70 29.5 86 24 C 126 11 172 4 216 4 C 244 4 262 6.5 280 11 C 308 18.5 336 31 362 43.5 C 368 46.5 376 49 386 50.5 C 410 54 432 56.5 452 61 C 470 65.5 486 73 498 80.5 C 503 84 506 89 506.5 95 C 507 103 506.5 112 505 119 C 503.5 125 499 129.5 492 131 C 482 133 470 133 457.7 133",
        sill: [161.7, 362.3, 133], fillY: 121, fillArch: 43.2,
        rear: "C 54.5 120.7 32.4 119.6 17 110.7 C 12 94.5 19.2 94 22.8 81.2 C 25.2 72.7 26.1 63.9 26.1 55.1 C 31.8 53.4 37.8 53.2 43.5 51.7 C 51.1 49.8 58.5 47.1 65.8 44.4",
        belt: [[65.8, 44.4], [426.1, 68.4]],
        front: "C 447.4 71.8 466.6 76.5 485.6 87.1 C 488.3 88.6 492 90.1 493.7 93 C 495.7 96.6 494.8 102.3 494.5 106.2 C 494.3 110.2 494.3 114.7 492.1 118.1 C 483.1 122.3 462.2 121 452.2 121",
        bolt: [256, 76, 0.99]
    },
    // 5057 long, 1680 high, 2965 wheelbase.
    "x": {
        width: 513.7, height: 172.0, wheels: [114.4, 410.9], wheelY: 134.8, tire: 33.2, hub: 16,
        body: "M 64.7 149 C 54 148 40 144.5 26 141 C 17 138.5 10 134 8 127 C 5.5 120 4 110 4.5 101 C 5 92 7 84 7.3 76 C 7.6 66 7 56 6.5 48 C 6.2 43 5.5 40 6.5 37 C 13 35 20 34 27 33.5 C 40 32 52 28.5 64 24.5 C 104 11.5 150 4 200 4 C 232 4 252 5.5 270 8.5 C 304 15 334 26.5 364 40 C 370 43 376 47 384 49.5 C 404 53.5 424 57 442 60.5 C 462 65 480 71.5 496 78.5 C 503 82 508 88 509 95 C 510 106 510 118 509.5 128 C 509 135 505 140 498 142 C 487 145.5 474 149 460.6 149",
        sill: [164.1, 361.2, 149], fillY: 137, fillArch: 45.2,
        rear: "C 59.8 136.6 26.2 131.2 20.4 125.1 C 19.1 123.7 18.6 121 18.2 119.2 C 14.6 104.7 18.4 92.1 19.2 77.8 C 19.7 69.6 19.3 61.3 18.8 53.1",
        belt: [[18.8, 53.1], [464.2, 79.1]],
        front: "C 471.4 81.5 494.2 87.9 496.8 95.4 C 498.2 99.6 497.7 105.5 497.8 109.9 C 497.9 116.1 498.6 123.3 496.9 129.2 C 485.4 135.3 468.9 136.9 456 137",
        bolt: [256, 84, 1.16]
    },
    // 4750 long, 1624 high, 2890 wheelbase.
    "y": {
        width: 483.0, height: 166.4, wheels: [102.6, 391.6], wheelY: 130.8, tire: 31.6, hub: 15,
        body: "M 54.5 149 C 44 146.5 30 141 18 136 C 12 134 8 131 6.5 126 C 4.5 119 3.5 106 5 96 C 6.5 90 10 84 11.5 76 C 12.5 68 12 58 10 50 C 9.5 46.5 9 44 9.5 42.5 C 13 40.5 19 40.5 25 39.5 C 37 36.5 49 31.5 61 27.5 C 100 15 150 4 200 4 C 232 4 250 7 268 11 C 296 19 322 33 346 45 C 352 48.5 358 51.5 366 54 C 384 58 402 62 420 66.5 C 438 71.5 454 79 468 86.5 C 474 90 478 95 479 101 C 479.5 110 479 120 478 128 C 477 135 474 140 468 143 C 460 146.5 450 148.5 439.7 149",
        sill: [150.7, 343.5, 149], fillY: 137, fillArch: 43.6,
        rear: "L 54.8 136.7 C 48.9 136 23.5 126 18.2 122.8 C 16.3 115.6 15 104.6 17.1 97.3 C 19 90.9 22.2 85 23.3 78.4 C 24.7 69.8 24.1 60.9 22.7 52.4 L 33.4 49.7",
        belt: [[33.4, 49.7], [390.0, 71.7]],
        front: "C 414.3 77.3 432.6 82 455.1 93.3 C 459 95.3 464.4 97.1 466.6 101.3 C 468.4 104.7 466.9 119.2 466.4 123.6 C 466.2 125.8 466.1 128.6 464.8 130.5 C 461.1 135.8 440.7 136.9 434.8 137",
        bolt: [241, 85, 1.12]
    },
    // 5683 long, 1791 high, 3635 wheelbase.
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

const profileCache = {};

// The side profile for a key from KEYS: {boxWidth, boxHeight, outlinePath, fillPath,
// chargingFillPath, boltPath}.
function sideProfile(key) {
    const k = PROFILES[key] ? key : "3";
    if (!profileCache[k]) profileCache[k] = profile(PROFILES[k]);
    return profileCache[k];
}

// ---------- plans ----------

// A lip spoiler along the trunk lid's trailing edge: a band depth units deep at the middle
// that thins out toward the lid's corners, as a closed symmetric path. Its inner edge is
// the trailing edge moved forward, and meets the lid's side ahead of the corner. "" for a
// lid that doesn't end in a curve to the centerline, such as a bed cover.
function lipPath(w, trunk, depth) {
    const n = trunk.length;
    const tail = trunk[n - 1];
    if (n < 3 || tail.length !== 6 || Math.abs(tail[4] - w / 2) > 0.001) return "";
    const corner = endOf(trunk[n - 2]);
    const before = endOf(trunk[n - 3]);
    const side = corner[1] - before[1];
    if (side <= 0) return "";
    // Where the side is short, as on a Model X, the band is thinner.
    const d = Math.min(depth, side * 0.8);
    const inner = [corner[0] + (before[0] - corner[0]) * d / side, corner[1] - d];
    return symmetric(w, [[w / 2, tail[5] - d], [tail[2], tail[3] - d, tail[0], tail[1] - d, inner[0], inner[1]],
                         corner, tail]);
}

// A closed chain shifted by dx. With w, mirrored onto the right side of a car w wide.
function placed(points, dx, w) {
    return chain(mapX(points, x => w === undefined ? x + dx : w - (x + dx))) + " Z";
}

// A chain whose part outside the flank is pulled in: share 0 puts it on the flank, 1
// leaves it as drawn. With w, mirrored onto the right side.
function reached(points, flank, share, w, closed) {
    const moved = mapX(points, x => {
        const out = x < flank ? flank - (flank - x) * share : x;
        return w === undefined ? out : w - out;
    });
    return chain(moved) + (closed ? " Z" : "");
}

// A mirror's outline in the coordinates of its door (w wide), so it swings with the door.
// points are [out, along]: distance out from the flank, and back from the door's front
// edge. base is how far the flank is outside the door's outer edge.
function mirrorPath(points, base, w, onLeft) {
    return chain(mapX(points, out => onLeft ? -(base + out) : w + base + out));
}

// Builds the plan of a car, nose up, in a box that ends at the mirror tips. x runs across
// from the left mirror's tip, y along from the nose. Chains describe the left side.
// spec:
//   w, length          the box's width, and the car's length
//   flank              x of the body's straight side along the doors
//   belt               x of the side windows' outer edge
//   frontAxle, rearAxle, tire   axle positions, and half a tire's length
//   body(flank)        the left outline, nose to tail, for a given flank: the caller
//                      snaps that long straight edge to whole pixels
//   hood, trunk        the lids, as {points, top, bottom} for symmetric()
//   creases            lines pressed into the hood
//   panes, beams       the windshield and roof glass, and the beams between them
//   rear               the rear window. With hatch set it opens with the trunk lid
//   sidePanes          roof glass that doesn't cross the centerline
//   frontWindow, rearWindow, quarter   the opening side windows and the fixed glass,
//                      as closed chains with their outer edge on the belt
//   frontDoor, rearDoor   [start, end] of each door along the car
//   headlight, taillight, headlightLine, taillightLine   a lens, and the light in it
//   mirror             its outline, for mirrorPath()
//   port               [x, y] of the charge port
//   sentryY, lockY     where the two glyphs go on the glass
//   falcon             rear doors that lift like wings: see the Model X
//   trim               black parts outside the body
//   slats              lines across the trunk lid
// The plan's spoilerPath is a lip spoiler on the trunk lid, from lipPath().
function makePlan(spec) {
    const w = spec.w;
    const sym = o => symmetric(w, o.points, o.top, o.bottom);
    const each = (list, closed) => (list || []).map(c => onBothSides(w, c, closed)).join(" ");
    const base = spec.panes[0];
    // All the cabin glass and beams as one outline, built from the left edges of the pieces
    // in order from the windshield. A translucent body has this cut out as a single hole:
    // separate holes that touch would show hairlines between them.
    const sides = (spec.sidePanes || []).map(c => c.filter((q, i) => i === 0 || endOf(q)[0] < w / 4));
    const edge = [];
    spec.panes.concat(spec.beams, [spec.rear]).map(o => o.points).concat(sides)
        .filter(c => c[0][0] < w / 4)
        .sort((a, b) => a[0][1] - b[0][1])
        .forEach(c => {
            c.forEach((q, i) => {
                const last = edge.length ? chainEnd(edge) : null;
                if (i === 0 && last && last[0] === q[0] && last[1] === q[1]) return;
                edge.push(q);
            });
        });
    return {
        boxWidth: w,
        boxHeight: Math.ceil(spec.length),
        length: spec.length,
        flank: spec.flank,
        belt: spec.belt,
        wheelInset: spec.wheelInset === undefined ? 4 : spec.wheelInset,
        tire: spec.tire,
        frontAxle: spec.frontAxle,
        rearAxle: spec.rearAxle,
        frontDoor: spec.frontDoor,
        rearDoor: spec.rearDoor,
        sentryY: spec.sentryY,
        lockY: spec.lockY,
        port: spec.port,
        hatch: !!spec.hatch,
        falcon: spec.falcon || null,
        mirror: spec.mirror,
        frontWindow: spec.frontWindow,
        rearWindow: spec.rearWindow,
        // The room a glyph on the windshield has.
        windshieldLength: chainEnd(base.points)[1] - base.points[0][1],
        // The y range of the highlight gradient on the hood, the trunk lid and the glass.
        hoodSpan: [spec.hood.points[0][1], chainEnd(spec.hood.points)[1]],
        trunkSpan: [spec.trunk.points[0][1], chainEnd(spec.trunk.points)[1]],
        glassSpan: [base.points[0][1], chainEnd(spec.rear.points)[1]],
        bodyLeft: spec.body,
        bodyPath: flank => symmetric(w, spec.body(flank)),
        frunkPath: sym(spec.hood),
        trunkPath: sym(spec.trunk),
        spoilerPath: lipPath(w, spec.trunk.points, 4),
        creasePath: each(spec.creases, false),
        slatPath: spec.slats || "",
        trimPath: each(spec.trim, true),
        glassPath: spec.panes.map(sym).concat(each(spec.sidePanes, true)).join(" "),
        rearGlassPath: sym(spec.rear),
        canopyPath: symmetric(w, edge, base.top, spec.rear.bottom),
        beamPath: spec.beams.map(sym).join(" "),
        quarterPath: spec.quarter ? onBothSides(w, spec.quarter, true) : "",
        headlightPath: onBothSides(w, spec.headlight, true),
        headlightLine: onBothSides(w, spec.headlightLine, false),
        taillightPath: onBothSides(w, spec.taillight, true),
        taillightLine: onBothSides(w, spec.taillightLine, false)
    };
}

const PLANS = {};

// 4694 long, 1850 wide, 2875 wheelbase (mm).
PLANS["3"] = function () {
    return makePlan({
        w: 209, length: 469.4, flank: 14.25, belt: 27, frontAxle: 84, rearAxle: 371.5, tire: 33,
        body: f => [[104.5, 0],
                    [88, 0, 56, 10.5, 33, 24], [23, 31.5, 15.5, 44, 12.8, 60], [11.9, 72, 12.3, 84, 12.3, 98],
                    [12.3, 120], [12.3, 132, f, 138, f, 150],
                    [f, 333], [f, 343, 12.9, 346, 12.9, 356], [12.9, 392],
                    [12.9, 402, 14.6, 412, 17.5, 420], [20.3, 428, 25.5, 440, 32.5, 450],
                    [39, 459, 52, 463.5, 68, 466], [80, 468, 92, 469.4, 104.5, 469.4]],
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

// 4750 long, 1921 wide, 2890 wheelbase.
PLANS["y"] = function () {
    return makePlan({
        w: 216.1, length: 475, flank: 13.9, belt: 25.5, frontAxle: 87.4, rearAxle: 376.4, tire: 35,
        body: f => [[108.05, 0],
                    [86, 0, 60, 5.5, 40, 16.8], [30, 22, 20.5, 27.5, 16.8, 36.2], [15.2, 42.5, f, 51, f, 62],
                    [f, 322], [f, 334, 12.2, 338, 12.2, 350], [12.2, 398],
                    [12.2, 408, 14.2, 418, 17.6, 426], [20.5, 433.5, 23.5, 441.5, 28.2, 448],
                    [33, 454, 40, 456.5, 48.2, 459.5], [56, 462.5, 64, 468, 73.4, 471.2], [84, 474.3, 96, 475, 108.05, 475]],
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

// 5021 long, 1987 wide, 2960 wheelbase.
PLANS["s"] = function () {
    return makePlan({
        w: 222.7, length: 502.1, flank: 15.6, belt: 22.5, frontAxle: 96.1, rearAxle: 392.1, tire: 35,
        body: f => [[111.35, 0],
                    [98, 0, 86, 0.8, 76, 3], [50, 9, 29.7, 22.4, 20.9, 40], [18, 46, 14.8, 52, 13.8, 60],
                    [13.4, 66, 13.6, 70, 13.6, 76], [13.6, 118], [13.6, 130, f, 134, f, 146],
                    [f, 332], [f, 344, 12.2, 350, 12.2, 362], [12.2, 418],
                    [12.4, 425, 15.5, 430, 17.9, 436], [19.2, 443.5, 23.8, 464.9, 29.4, 469.5],
                    [34.4, 473.6, 40.7, 475.7, 46.4, 478.5], [53, 481.8, 61, 489.3, 68.1, 492.8], [80, 498.6, 95, 502.1, 111.35, 502.1]],
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

// 5057 long, 1999 wide, 2965 wheelbase. The rear doors carry the roof glass.
PLANS["x"] = function () {
    return makePlan({
        w: 223.9, length: 505.7, flank: 16, belt: 22.5, frontAxle: 98.8, rearAxle: 395.3, tire: 37,
        body: f => [[111.95, 0],
                    [98, 0, 92, 0.6, 87.5, 1.5], [75.5, 3.5, 64.5, 7, 53.5, 12.5], [44, 17.5, 33, 23, 28, 29],
                    [23.8, 34.2, 21.9, 40.2, 19, 46], [16.3, 51.3, 14.3, 57.1, 13.3, 63], [12.4, 68, 12, 74, 12, 82],
                    [12, 112], [12, 124, f, 128, f, 140],
                    [f, 338], [f, 348, 11.6, 352, 11.6, 362], [11.6, 424],
                    [11.8, 432, 15.5, 438, 18.6, 446.3], [20.3, 456.1, 23.5, 475.3, 31.3, 481.7],
                    [36.8, 486.2, 44.2, 489, 50.5, 492.2], [56.3, 495.1, 62.9, 499.1, 69.5, 500.2], [79, 501.8, 92, 505.7, 111.95, 505.7]],
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
        // The rear doors hinge along the roof's spine and open in two leaves: the upper
        // one (with the roof glass) stands up steeply, the lower one lies out flat,
        // reaching about 30 past the body.
        //   wing   an open door seen from above, left side. Its tip is shorter than the
        //          door because the door is cut around the rear wheel
        //   fold   where the two leaves meet
        //   glass  the pane in each leaf
        //   seam   how far across the roof a closed door's edges run
        //   back   y where an open door ends beside the body
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

// 5683 long, 2032 wide over the fender flares, 3635 wheelbase. The bed's cover is
// treated as the trunk.
PLANS["cybertruck"] = function () {
    const slats = [];
    for (let y = 403; y < 550; y += 13) slats.push("M 51 " + y + " H 190.3");
    return makePlan({
        w: 241.3, length: 568.3, flank: 22.5, belt: 33.5, frontAxle: 87.8, rearAxle: 451.3, tire: 44, wheelInset: 16,
        body: f => [[120.65, 0.5], [84, 2.5], [54, 10], [35, 22], [24.5, 35], [f, 46], [f, 557], [26, 568.3], [120.65, 568.3]],
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

const planCache = {};

// The plan for a key from KEYS.
function plan(key) {
    const k = PLANS[key] ? key : "3";
    if (!planCache[k]) planCache[k] = PLANS[k]();
    return planCache[k];
}
