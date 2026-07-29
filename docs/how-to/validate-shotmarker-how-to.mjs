import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = dirname(fileURLToPath(import.meta.url));
const htmlPath = join(currentDir, "shotmarker-how-to.html");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

assert(existsSync(htmlPath), "Missing docs/how-to/shotmarker-how-to.html");

const html = readFileSync(htmlPath, "utf8");

const requiredText = [
  "用 Apple Watch 给好球打点",
  "打开 iPhone 里的训练记录",
  "选择视频，生成集锦",
  "长按开始",
  "双击或转动数码表冠",
  "生成集锦",
];

for (const text of requiredText) {
  assert(html.includes(text), `Missing required copy: ${text}`);
}

assert(!/https?:\/\//.test(html), "HTML should not depend on external network URLs");

const imageMatches = [...html.matchAll(/<img\b[^>]*\bsrc="([^"]+)"/g)];
assert(imageMatches.length >= 4, "Expected at least four local images");

for (const [, src] of imageMatches) {
  assert(!src.startsWith("/"), `Image path should be relative: ${src}`);
  assert(!src.includes(".."), `Image path should stay inside docs/how-to: ${src}`);
  assert(existsSync(join(currentDir, src)), `Missing image asset: ${src}`);
}

console.log("ShotMarker how-to page validation passed.");
