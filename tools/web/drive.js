// Drive a web export through a list of steps and screenshot along the way.
//   node tools/web/drive.js <url> <outdir> '<json steps>'
// Steps: ["tap", x, y] | ["wait", ms] | ["shot", "name"] | ["hold", x, y, ms] | ["drag", x1, y1, x2, y2, ms]
//        ["eval", "js"] | ["fps"] (prints Godot's frames-per-second via the page's rAF rate)
const { chromium } = require('playwright');
const fs = require('fs');
const [url, out, stepsJson] = process.argv.slice(2);
const steps = JSON.parse(stepsJson || '[]');
const T0 = Date.now();
fs.mkdirSync(out, { recursive: true });
(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
	const ctx = await browser.newContext({ viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });
	const page = await ctx.newPage();
	const log = [];
	page.on('console', (m) => { const l = `[${((Date.now() - T0) / 1000).toFixed(0)}s ${m.type()}] ${m.text()}`; log.push(l); if (process.env.LIVE) console.log(l.slice(0, 300)); });
	page.on('pageerror', (e) => log.push(`[pageerror] ${e.message}`));
	await page.goto(url);
	await page.waitForSelector('#play', { state: 'visible', timeout: 15 * 60 * 1000 });
	await page.tap('#play');
	await page.waitForTimeout(8000);
	const cdp = await ctx.newCDPSession(page);
	const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
	for (const s of steps) {
		const [k, ...a] = s;
		if (k === 'tap') { await touch('touchStart', a[0], a[1]); await page.waitForTimeout(80); await touch('touchEnd'); await page.waitForTimeout(400); }
		else if (k === 'hold') { await touch('touchStart', a[0], a[1]); await page.waitForTimeout(a[2]); await touch('touchEnd'); }
		else if (k === 'drag') {
			await touch('touchStart', a[0], a[1]);
			const n = 10; for (let i = 1; i <= n; i++) { await touch('touchMove', a[0] + (a[2] - a[0]) * i / n, a[1] + (a[3] - a[1]) * i / n); await page.waitForTimeout(a[4] / n); }
			await touch('touchEnd');
		}
		else if (k === 'wait') await page.waitForTimeout(a[0]);
		else if (k === 'log') console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s] step: ${a[0]}`);
		else if (k === 'shot') { const t = Date.now(); await page.screenshot({ path: `${out}/${a[0]}.png`, timeout: 240000 }).catch((e) => console.log('shot failed', a[0], e.message.split('\n')[0])); console.log('shot', a[0], ((Date.now() - t) / 1000).toFixed(1) + 's'); }
		else if (k === 'eval') console.log('eval:', JSON.stringify(await page.evaluate(a[0])));
		else if (k === 'fps') console.log('fps:', await page.evaluate(() => new Promise((r) => { let n = 0; const t = performance.now(); const f = () => { n++; if (performance.now() - t < 3000) requestAnimationFrame(f); else r((n / 3).toFixed(1)); }; requestAnimationFrame(f); })));
	}
	fs.writeFileSync(`${out}/console.log`, log.join('\n'));
	const errs = log.filter((l) => /error|ERROR/.test(l));
	console.log(`${log.length} console lines, ${errs.length} errors`);
	errs.slice(0, 40).forEach((l) => console.log('  ' + l.slice(0, 400)));
	await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
