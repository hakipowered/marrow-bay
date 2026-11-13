// Smoke-test a web export in headless Chromium: loads the page, taps
// "ENTER THE CITY", waits for the title menu, saves screenshots and prints
// every console error. Exit code 1 if the engine never starts or crashes.
//   node tools/web/smoke.js [url=http://localhost:8060/] [outdir=/tmp/websmoke] [seconds=40]
const { chromium } = require('playwright');
const fs = require('fs');

const url = process.argv[2] || 'http://localhost:8060/';
const out = process.argv[3] || '/tmp/websmoke';
const secs = Number(process.argv[4] || 40);
fs.mkdirSync(out, { recursive: true });

(async () => {
	const browser = await chromium.launch({
		args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
	});
	// Galaxy Z Fold inner screen, in CSS pixels.
	const ctx = await browser.newContext({ viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });
	const page = await ctx.newPage();
	const log = [];
	let exited = null;
	page.on('console', (m) => { log.push(`[${m.type()}] ${m.text()}`); });
	page.on('pageerror', (e) => log.push(`[pageerror] ${e.message}`));
	page.on('crash', () => { exited = 'page crashed'; });
	const t0 = Date.now();
	await page.goto(url);
	await page.waitForSelector('#play', { state: 'visible', timeout: 15 * 60 * 1000 });
	console.log(`loaded in ${((Date.now() - t0) / 1000).toFixed(1)}s, isolated=${await page.evaluate(() => crossOriginIsolated)}`);
	await page.screenshot({ path: `${out}/0_loaded.png` });
	await page.tap('#play');
	for (let i = 1; i * 10 <= secs && !exited; i++) {
		await page.waitForTimeout(10000);
		const msg = await page.$eval('#msg', (e) => e.textContent).catch(() => '');
		if (/stopped/.test(msg)) { exited = msg; }
		await page.screenshot({ path: `${out}/${i}_t${i * 10}s.png` });
	}
	const mem = await page.evaluate(() => (performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : -1));
	console.log(`JS heap ${mem} MB`);
	fs.writeFileSync(`${out}/console.log`, log.join('\n'));
	const errs = log.filter((l) => /error|SCRIPT ERROR|pageerror|ERROR/i.test(l));
	console.log(`${log.length} console lines, ${errs.length} errors`);
	errs.slice(0, 60).forEach((l) => console.log('  ' + l.slice(0, 300)));
	await browser.close();
	if (exited) { console.log('FAILED: ' + exited); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
