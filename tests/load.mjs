// Loads one of the widget's ".pragma library" scripts for the tests.
import { readFileSync } from "node:fs";

// The scripts are plain functions behind a QML pragma, so the pragma is dropped and the
// source runs in this realm, which keeps deepEqual's prototype checks meaningful. Returns
// the script's top-level functions by name.
export function load(file) {
    const src = readFileSync(new URL("../package/contents/ui/" + file, import.meta.url), "utf8")
        .replace(/^\.pragma library\s*$/m, "");
    const names = [...src.matchAll(/^function (\w+)\s*\(/gm)].map(m => m[1]);
    return new Function(src + "\nreturn {" + names.join(",") + "};")();
}
