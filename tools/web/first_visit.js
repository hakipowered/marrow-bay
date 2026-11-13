// First visit and return visit of the browser version with content packs:
// a fresh browser profile opens the page, which downloads every pack into
// the browser's Cache Storage before "Enter the city" shows; the tap must
// reach the title menu. Then the page is reloaded and must reach the menu
// again without downloading anything. Prints timings and memory use.
//   python3 tools/web/serve.py build/web 8060 build/content &
//   node tools/web/first_visit.js [url=http://localhost:8060/] [outdir=/tmp/webfirst]
const { chromium } = require('playwright');
const fs = require('fs');
const { execSync } = require('child_process');
const url = process.argv[2] || 'http://localhost:8060/';
const out = process.argv[3] || '/tmp/webfirst';
fs.mkdirSync(out, { recursive: true });
const T0 = Date.now();
const say = (m) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s] ${m}`);
const rss = () => { try { return Math.round(Number(execSync("ps -C chrome-headless-shell -o rss= | awk '{s+=$1} END {print s}'").toString()) / 1024); } catch (e) { return -1; } };

(async () => {
	const dir = fs.mkdtempSync('/tmp/webprofile-');
	const ctx = await chromium.launchPersistentContext(dir, {
		args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
		viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true,
	});
	const page = ctx.pages()[0] || await ctx.newPage();
	const log = [];
	let requests = 0, bytes = 0;
	page.on('console', (m) => log.push(`[${((Date.now() - T0) / 1000).toFixed(0)}s ${m.type()}] ${m.text()}`));
	page.on('pageerror', (e) => log.push(`[pageerror] ${e.message}`));
	page.on('response', async (r) => { if (r.url().includes('/packs/') && r.url().endsWith('.pck')) { requests++; bytes += Number(r.headers()['content-length'] || 0); } });
	let failed = null;
	const visit = async (label, limitSecs) => {
		requests = 0; bytes = 0;
		const t = Date.now();
		await page.goto(url);
		await page.waitForSelector('#play:visible, #retry:visible', { timeout: limitSecs * 1000 });
		const shellMsg = await page.$eval('#msg', (e) => e.textContent).catch(() => '');
		if (await page.isVisible('#retry')) throw new Error(`${label}: page says "${shellMsg}" ${await page.$eval('#note', (e) => e.textContent).catch(() => '')}`);
		say(`${label}: page ready in ${((Date.now() - t) / 1000).toFixed(1)}s, ${requests} packs fetched (${(bytes / 1048576).toFixed(0)} MB), browser RSS ${rss()} MB`);
		await page.screenshot({ path: `${out}/${label}_ready.png` }).catch(() => {});
		await page.tap('#play');
		let n = 0;
		while ((Date.now() - t) / 1000 < limitSecs) {
			await page.waitForTimeout(5000);
			const menu = await page.evaluate(() => !!(window.ragoon && window.ragoon.menu)).catch(() => false);
			if (n++ % 6 === 0) await page.screenshot({ path: `${out}/${label}_${String(n).padStart(3, '0')}.png`, timeout: 120000 }).catch(() => {});
			if (menu) {
				say(`${label}: title menu after ${((Date.now() - t) / 1000).toFixed(0)}s, ${requests} packs fetched (${(bytes / 1048576).toFixed(0)} MB), browser RSS ${rss()} MB`);
				await page.screenshot({ path: `${out}/${label}_menu.png` }).catch(() => {});
				return;
			}
			const msg = await page.$eval('#msg', (e) => e.textContent).catch(() => '');
			if (/stopped|couldn/i.test(msg)) throw new Error(`${label}: ${msg}`);
		}
		throw new Error(`${label}: no title menu after ${limitSecs}s`);
	};
	try {
		await visit('first', 1800);
		const idb = await page.evaluate(async () => { const e = await navigator.storage.estimate(); return Math.round(e.usage / 1048576); });
		say(`stored in the browser: ${idb} MB`);
		await visit('return', 600);
		if (requests > 0) throw new Error(`return visit downloaded ${requests} packs`);
	} catch (e) {
		failed = e.message;
	}
	fs.writeFileSync(`${out}/console.log`, log.join('\n'));
	const errs = log.filter((l) => /error/i.test(l) && !/Blocking on the main thread|agent_max_climb|nav_mesh|push_warning|hound has no/.test(l));
	errs.slice(0, 30).forEach((l) => console.log('  ' + l.slice(0, 300)));
	await ctx.close();
	if (failed) { say('FAILED: ' + failed); process.exit(1); }
	say('first visit + return visit OK');
})();
