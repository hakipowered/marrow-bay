// A new version comes out while the browser version's page is open: the page
// has installed set A, the game's own check then sees set B and reloads the
// page, which must load B (no pack downloads when only the build changed);
// after the player taps "Enter the city" again it must reach the title menu. Uses a copy of the content dir whose
// manifest the test rewrites.
//   C=$(mktemp -d); cp build/content/manifest.json $C/; ln -s $PWD/build/content/packs $C/packs
//   python3 tools/web/serve.py build/web 8061 $C &
//   node tools/web/new_version_visit.js http://localhost:8061/ $C [outdir=/tmp/webnew]
const { chromium } = require('playwright');
const fs = require('fs');
const url = process.argv[2] || 'http://localhost:8061/';
const content = process.argv[3];
const out = process.argv[4] || '/tmp/webnew';
fs.mkdirSync(out, { recursive: true });
const T0 = Date.now();
const say = (m) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s] ${m}`);
const manifestPath = `${content}/manifest.json`;
const original = fs.readFileSync(manifestPath, 'utf8');

(async () => {
	const dir = fs.mkdtempSync('/tmp/webprofile-');
	const ctx = await chromium.launchPersistentContext(dir, {
		args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
		viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true,
	});
	const page = ctx.pages()[0] || await ctx.newPage();
	const log = [];
	let packs = 0;
	page.on('console', (m) => { const l = `[${((Date.now() - T0) / 1000).toFixed(0)}s ${m.type()}] ${m.text()}`; log.push(l); if (process.env.LIVE) console.log(l.slice(0, 300)); });
	page.on('pageerror', (e) => log.push(`[pageerror] ${e.message}`));
	page.on('response', (r) => { if (r.url().includes('/packs/') && r.url().endsWith('.pck')) packs++; });
	let failed = null;
	try {
		await page.goto(url);
		await page.waitForSelector('#play:visible, #retry:visible', { timeout: 30 * 60 * 1000 });
		if (await page.isVisible('#retry')) throw new Error('page: ' + await page.$eval('#msg', (e) => e.textContent));
		say(`set A installed, ${packs} packs fetched`);
		// A new build goes up (same packs, new build id) before the player taps.
		const m = JSON.parse(original);
		m.build += '-next';
		m.version += '.1';
		fs.writeFileSync(manifestPath, JSON.stringify(m));
		packs = 0;
		await page.tap('#play');
		const t = Date.now();
		const within = (p, ms, v) => Promise.race([p, new Promise((r) => setTimeout(() => r(v), ms))]);
		for (let n = 0; ; n++) {
			await page.waitForTimeout(5000);
			const s = await within(page.evaluate(() => ({ menu: !!(window.ragoon && window.ragoon.menu), restarts: window.ragoonRestarts, msg: document.getElementById('msg').textContent, boot: document.getElementById('boot').style.display })).catch(() => ({})), 20000, { stuck: true });
			if (process.env.LIVE) say(JSON.stringify(s));
			if (await within(page.isVisible('#play').catch(() => false), 20000, false)) {
				say(`page reloaded for the new version (${packs} packs fetched), tapping Enter again`);
				await page.tap('#play');
			}
			if (n % 4 === 0) await page.screenshot({ path: `${out}/wait_${String(n).padStart(3, '0')}.png`, timeout: 60000 }).catch(() => {});
			if (s.menu) {
				say(`title menu after ${((Date.now() - t) / 1000).toFixed(0)}s, ${s.restarts} restart(s), ${packs} packs fetched`);
				await page.screenshot({ path: `${out}/menu.png` }).catch(() => {});
				if (s.restarts !== 1) throw new Error(`expected 1 restart, got ${s.restarts}`);
				if (packs) throw new Error(`${packs} packs downloaded for a build-only change`);
				break;
			}
			if ((Date.now() - t) / 1000 > 900) throw new Error('no title menu after 900s');
			const msg = await page.$eval('#msg', (e) => e.textContent).catch(() => '');
			if (await page.isVisible('#retry').catch(() => false)) throw new Error('page: ' + msg);
		}
		const installed = await page.evaluate(async () => (await (await caches.open('ragoon-packs-v1')).match('installed.json').then((r) => r.json())).build);
		if (!installed.endsWith('-next')) throw new Error('page kept build ' + installed);
	} catch (e) {
		failed = e.message;
	} finally {
		fs.writeFileSync(manifestPath, original);
	}
	fs.writeFileSync(`${out}/console.log`, log.join('\n'));
	log.filter((l) => /error/i.test(l) && !/Blocking on the main thread|agent_max_climb|nav_mesh|push_warning/.test(l)).slice(0, 20).forEach((l) => console.log('  ' + l.slice(0, 300)));
	await ctx.close();
	if (failed) { say('FAILED: ' + failed); process.exit(1); }
	say('new version while the page was open: OK');
})();
