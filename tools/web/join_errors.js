// Joining in the browser: a wrong room code must say so within seconds and
// stay said, and the right code must still get in. Two pages of the web
// build through a relay (the live one, or a local one).
//   node tools/web/join_errors.js [url=http://localhost:8060/] [relay=ws://localhost:8787] [outdir=/tmp/webjoin]
// Serve the build with tools/web/serve.py; for a local relay run
// PORT=8787 node relay/local_relay.js (needs `npm i ws`).
const { chromium } = require('playwright');
const fs = require('fs');
const url = process.argv[2] || 'http://localhost:8060/';
const relay = process.argv[3] || 'ws://localhost:8787';
const out = process.argv[4] || '/tmp/webjoin';
fs.mkdirSync(out, { recursive: true });
const T0 = Date.now();
const say = (m) => console.log(`[${((Date.now() - T0) / 1000).toFixed(0)}s] ${m}`);
let failures = 0;
const check = (ok, what) => { if (!ok) failures++; say(`${ok ? 'ok' : 'FAIL'}: ${what}`); };

async function open(ctx, name, query) {
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
	page.note = (k) => page.evaluate((k) => (window.ragoon || {})[k], k).catch(() => undefined);
	page.waitNote = async (k, secs, test = (v) => !!v) => {
		for (let i = 0; i < secs * 4; i++) { const v = await page.note(k); if (test(v)) return v; await page.waitForTimeout(250); }
		throw new Error(`${name}: no ${k} after ${secs}s (last ${JSON.stringify(await page.note(k))})`);
	};
	page.shot = (n) => page.screenshot({ path: `${out}/${name}_${n}.png`, timeout: 240000 }).catch(() => {});
	say(`${name} loaded`);
	return page;
}

const newCtx = (browser) => browser.newContext({ viewport: { width: 904, height: 800 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });

(async () => {
	const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
	const pages = [];
	try {
		const host = await open(await newCtx(browser), 'host', `?relay=${encodeURIComponent(relay)}`);
		pages.push(host);
		await host.waitForTimeout(10000);
		await host.tapAt(452, 445);           // Co-op: Invite a Friend
		await host.waitForTimeout(1500);
		await host.tapAt(452, 491);           // Create Room
		const code = await host.waitNote('room', 30);
		await host.waitNote('room_open', 30);
		check(/^[0-9]{6}$/.test(code), `host room ${code} is six numbers and open`);
		await host.shot('1_room');

		// The host's code with one digit wrong.
		const wrong = code[0] + ((+code[1] + 5) % 10) + code.slice(2);
		const guestCtx = await newCtx(browser);
		const guest = await open(guestCtx, 'guest', `?join=${wrong}&relay=${encodeURIComponent(relay)}`);
		pages.push(guest);
		await guest.waitForTimeout(10000);
		// Join menu: title, code box, Paste Invite, Join, status, Back.
		const t0 = Date.now();
		await guest.tapAt(452, 438);          // Join
		const said = await guest.waitNote('status', 20, (v) => typeof v === 'string' && v.startsWith('No game is open'));
		const secs = (Date.now() - t0) / 1000;
		check(secs < 6, `wrong code ${wrong}: "${said}" after ${secs.toFixed(1)} s`);
		await guest.shot('2_wrong_code');
		await guest.waitForTimeout(14000);
		const later = await guest.note('status');
		check(later === said, `wrong code: still the same message 14 s later (${later})`);

		// The right code (the invite link) gets in.
		await guest.goto(url + `?join=${code}&relay=${encodeURIComponent(relay)}`);
		await guest.waitForSelector('#play', { state: 'visible', timeout: 10 * 60 * 1000 });
		await guest.tap('#play');
		await guest.waitForTimeout(10000);
		await guest.tapAt(452, 438);          // Join
		await guest.waitNote('connected', 30);
		await host.waitNote('partner', 30);
		check(true, 'right code: guest connected, host sees partner');
		await guest.shot('3_connected');
		await host.shot('3_partner');
	} catch (e) {
		check(false, e.message);
	}
	pages.forEach((p, i) => fs.writeFileSync(`${out}/${i ? 'guest' : 'host'}.log`, p.log.join('\n')));
	await browser.close();
	say(failures ? `FAILED (${failures})` : 'PASSED');
	process.exit(failures ? 1 : 0);
})();
