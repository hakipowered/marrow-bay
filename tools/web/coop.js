// Co-op in the browser: two pages of the web build play together through a
// relay. The first hosts a room, the second opens the invite link
// (/?join=CODE) and joins; both should load the level.
//   node tools/web/coop.js [url=http://localhost:8060/] [relay=ws://localhost:8787] [outdir=/tmp/webcoop]
// Run a relay first: PORT=8787 node relay/local_relay.js (needs `npm i ws`).
const { chromium } = require('playwright');
const fs = require('fs');
const url = process.argv[2] || 'http://localhost:8060/';
const relay = process.argv[3] || 'ws://localhost:8787';
const out = process.argv[4] || '/tmp/webcoop';
fs.mkdirSync(out, { recursive: true });
const T0 = Date.now();
const say = (m) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s] ${m}`);

async function open(browser, name, query) {
	const ctx = await browser.newContext({ viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });
	const page = await ctx.newPage();
	page.log = [];
	page.on('console', (m) => page.log.push(`[${m.type()}] ${m.text()}`));
	page.on('pageerror', (e) => page.log.push(`[pageerror] ${e.message}`));
	await page.goto(url + query);
	await page.waitForSelector('#play', { state: 'visible', timeout: 10 * 60 * 1000 });
	await page.tap('#play');
	const cdp = await ctx.newCDPSession(page);
	page.tapAt = async (x, y) => {
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
		await page.waitForTimeout(80);
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
		await page.waitForTimeout(500);
	};
	page.note = (k) => page.evaluate((k) => (window.ragoon || {})[k], k);
	page.waitNote = async (k, secs) => {
		for (let i = 0; i < secs; i++) { const v = await page.note(k).catch(() => undefined); if (v) return v; await page.waitForTimeout(1000); }
		throw new Error(`${name}: no ${k} after ${secs}s`);
	};
	page.shot = (n) => page.screenshot({ path: `${out}/${name}_${n}.png`, timeout: 240000 }).catch(() => {});
	say(`${name} loaded`);
	return page;
}

(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
	let failed = null;
	try {
		const host = await open(browser, 'host', `?relay=${encodeURIComponent(relay)}`);
		await host.waitForTimeout(10000);
		await host.tapAt(452, 445);           // Co-op: Invite a Friend
		await host.waitForTimeout(1500);
		await host.tapAt(452, 491);           // Create Room
		const code = await host.waitNote('room', 30);
		say(`host room ${code}`);
		await host.shot('1_room');
		const guest = await open(browser, 'guest', `?join=${code}&relay=${encodeURIComponent(relay)}`);
		await guest.waitForTimeout(10000);
		await guest.shot('1_join_menu');
		// Join menu: title, code box, Paste Invite, Join, status, Back.
		await guest.tapAt(452, 438);          // Join
		await guest.waitNote('connected', 30);
		say('guest connected');
		await host.waitNote('partner', 30);
		say('host sees partner');
		await host.shot('2_partner');
		await host.tapAt(452, 502);           // START appears under Cancel
		await host.waitNote('started', 60);
		await guest.waitNote('started', 60);
		say('both started the level');
		await host.waitForTimeout(60000);
		await host.shot('3_level');
		await guest.shot('3_level');
		for (const p of [host, guest]) fs.writeFileSync(`${out}/${p === host ? 'host' : 'guest'}.log`, p.log.join('\n'));
	} catch (e) {
		failed = e.message;
	}
	await browser.close();
	if (failed) { say('FAILED: ' + failed); process.exit(1); }
	say('co-op OK');
})();
