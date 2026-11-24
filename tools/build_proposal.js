#!/usr/bin/env node
// 企画書の原稿（docs/submission/proposal/index.html）を PDF とページごとの見本 PNG にする。
// 使い方は docs/submission/proposal-build.md。
//
//   node tools/build_proposal.js              PDF を build/proposal/ に書き、見本 PNG を docs/submission/proposal-preview/ に書く
//   node tools/build_proposal.js --no-preview PDF だけ
//   node tools/build_proposal.js --final      本人が埋める印（【要確認】【記入】【未決】）が残っていたら失敗する（提出の前に使う）
//
// 必要なもの: Node.js 18 以上と Playwright の Chromium（npx playwright install chromium）。
// 書体はリポジトリの assets/fonts（Zen Maru Gothic）を読むので、ネットにつながなくても同じ見た目になる。
"use strict";

const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const ROOT = path.resolve(__dirname, "..");
const SOURCE = path.join(ROOT, "docs/submission/proposal/index.html");
const OUT_DIR = path.join(ROOT, "build/proposal");
const PDF_PATH = path.join(OUT_DIR, "proposal.pdf");
const PREVIEW_DIR = path.join(ROOT, "docs/submission/proposal-preview");
const MAX_PAGES = 15; // 公式の条件: 15 ページ以内の PDF
const PAGE_W_PX = 1123; // A4 横（297mm）を 96dpi で
const PAGE_H_PX = 794; // 210mm
const PREVIEW_SCALE = 0.6; // 見本は低い解像度（約 674×476）にしてリポジトリを重くしない
const MARKS = ["【要確認】", "【記入】", "【未決】"];

function loadPlaywright() {
  try {
    return require("playwright");
  } catch (_) {
    // リポジトリの外に入れた Playwright（グローバル）も探す
    try {
      const { execSync } = require("child_process");
      const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
      return require(path.join(globalRoot, "playwright"));
    } catch (_) {
      console.error("Playwright が見つからない。docs/submission/proposal-build.md の「準備」を参照。");
      process.exit(2);
    }
  }
}

function countPdfPages(buffer) {
  // Chromium の PDF はページごとに /Type /Page を 1 つ持つ（/Pages は除く）
  const text = buffer.toString("latin1");
  const matches = text.match(/\/Type\s*\/Page(?!s)/g);
  return matches ? matches.length : 0;
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const preview = !args.has("--no-preview");
  const final = args.has("--final");
  const { chromium } = loadPlaywright();

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({
      viewport: { width: PAGE_W_PX, height: PAGE_H_PX },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    const failed = [];
    page.on("requestfailed", (req) => failed.push(req.url()));
    page.on("response", (res) => {
      if (res.status() >= 400) failed.push(res.url());
    });
    await page.goto(pathToFileURL(SOURCE).href, { waitUntil: "load" });
    await page.evaluate(() => document.fonts.ready);

    // 読めなかった画像・書体があれば止める（パスの書き間違いに気づくため）
    const broken = await page.evaluate(() =>
      Array.from(document.images)
        .filter((img) => !img.complete || img.naturalWidth === 0)
        .map((img) => img.getAttribute("src")),
    );
    const fontOk = await page.evaluate(() => document.fonts.check('700 16px "Zen Maru Gothic"'));
    if (broken.length || failed.length || !fontOk) {
      console.error("読めなかったもの:", [...broken, ...failed], fontOk ? "" : "（書体 Zen Maru Gothic）");
      process.exitCode = 1;
      return;
    }

    // はみ出し（中身がページの外に切れている）を見つける
    const overflow = await page.evaluate(() => {
      const out = [];
      document.querySelectorAll(".page").forEach((p, i) => {
        const box = p.getBoundingClientRect();
        p.querySelectorAll("*").forEach((el) => {
          if (el.closest("svg") && el.tagName.toLowerCase() !== "svg") return;
          const r = el.getBoundingClientRect();
          if (r.width === 0 || r.height === 0) return;
          if (el.closest(".hero")) return;
          if (r.bottom > box.bottom + 1 || r.right > box.right + 1) {
            out.push(`${i + 1} ページ: <${el.tagName.toLowerCase()} class="${el.className.baseVal ?? el.className}">`);
          }
        });
        // 札の中の文字が札の外へあふれている
        p.querySelectorAll(".card").forEach((card) => {
          if (card.scrollHeight > card.clientHeight + 2) {
            const title = card.querySelector("h3");
            out.push(`${i + 1} ページ: 札「${title ? title.textContent.trim() : "?"}」の文字があふれている`);
          }
        });
      });
      return out;
    });
    if (overflow.length) {
      console.error("ページからはみ出している:\n  " + overflow.slice(0, 20).join("\n  "));
      process.exitCode = 1;
    }

    const pageCount = await page.locator(".page").count();

    // 本人が埋める印の一覧
    const marks = await page.evaluate((labels) => {
      const out = [];
      document.querySelectorAll(".page").forEach((p, i) => {
        // 印の凡例（.marks-legend）は数えない
        const legend = p.querySelector(".marks-legend");
        const text = legend ? p.innerText.replace(legend.innerText, "") : p.innerText;
        for (const label of labels) {
          let at = text.indexOf(label);
          while (at !== -1) {
            const line = text.slice(Math.max(0, at - 24), at + label.length + 24).replace(/\s+/g, " ");
            out.push({ page: i + 1, label, context: line });
            at = text.indexOf(label, at + 1);
          }
        }
      });
      return out;
    }, MARKS);

    fs.mkdirSync(OUT_DIR, { recursive: true });
    await page.emulateMedia({ media: "print" });
    const pdf = await page.pdf({
      path: PDF_PATH,
      preferCSSPageSize: true,
      printBackground: true,
    });
    const pdfPages = countPdfPages(pdf);

    if (preview) {
      fs.mkdirSync(PREVIEW_DIR, { recursive: true });
      for (const old of fs.readdirSync(PREVIEW_DIR)) {
        if (/^page-\d+\.png$/.test(old)) fs.unlinkSync(path.join(PREVIEW_DIR, old));
      }
      const small = await browser.newContext({
        viewport: { width: PAGE_W_PX, height: PAGE_H_PX },
        deviceScaleFactor: PREVIEW_SCALE,
      });
      const shotPage = await small.newPage();
      await shotPage.goto(pathToFileURL(SOURCE).href, { waitUntil: "load" });
      await shotPage.evaluate(() => document.fonts.ready);
      await shotPage.emulateMedia({ media: "print" });
      const pages = shotPage.locator(".page");
      for (let i = 0; i < pageCount; i++) {
        const file = path.join(PREVIEW_DIR, `page-${String(i + 1).padStart(2, "0")}.png`);
        await pages.nth(i).screenshot({ path: file });
      }
      await small.close();
    }

    const sizeMb = (pdf.length / 1024 / 1024).toFixed(1);
    console.log(`PDF: ${path.relative(ROOT, PDF_PATH)}（${pdfPages} ページ、${sizeMb} MB）`);
    if (preview) console.log(`見本: ${path.relative(ROOT, PREVIEW_DIR)}/page-01.png〜page-${String(pageCount).padStart(2, "0")}.png`);
    console.log(`本人が埋める・確かめる印: ${marks.length} 個`);
    for (const m of marks) console.log(`  p.${m.page} ${m.label} …${m.context}…`);

    if (pdfPages !== pageCount) {
      console.error(`PDF のページ数（${pdfPages}）が原稿の .page の数（${pageCount}）と違う。中身がページをまたいでいる`);
      process.exitCode = 1;
    }
    if (pdfPages > MAX_PAGES) {
      console.error(`${MAX_PAGES} ページを超えている（${pdfPages} ページ）`);
      process.exitCode = 1;
    }
    if (final && marks.length) {
      console.error("--final: 印が残っている。提出の前にすべて埋める");
      process.exitCode = 1;
    }
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
