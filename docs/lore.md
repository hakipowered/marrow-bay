# RaGoon City: Lore Bible

The canon for everything the game says out loud: cutscenes, files, call-outs,
signs, enemy names. The short version of the plot lives in the Story Bible doc
(https://claude.ai/artifact/DJQ4YLtABZuNTervV74aoU); this file fills in the
world underneath it so later chapters stay consistent. When a new scene, file or
level needs a fact, take it from here. If it isn't here, decide it once, write it
here, then use it.

The story is original. It shares a genre with the classic survival horror games
(one city, one night, two strangers, an outbreak someone covered up) but none of
their places, people, organisations, creatures, plot turns or lines. Don't
borrow names or dialogue from existing games, even reworded.

---

## 1. The city

**RaGoon City** (said *Rah-goon*) is an old river port of about 900,000 people,
built where the Ragoon River bends twice before the dam. Brick downtown, iron
bridges strung with festival lights, a flood-prone river district, and
a City Hall that has been run by the same few families for a century.

| Place | What it is | Where it shows up |
|---|---|---|
| **Ashgrove Street** | Downtown shopping street that runs to the Archive. Shuttered shops, a fire escape, the burning wreck. | Prologue |
| **RaGoon City Civic Archive** | 1902 granite records hall: births, deaths, deeds, court rolls, and the sealed 1891 quarantine files. Since the floods of 1974 it is also the district's official storm shelter. | Ch. 1–3 |
| **The Great Hall** | The Archive's public hall, two storeys, balcony, card catalogues. Turned into the shelter dormitory three days ago: cots, blankets, the count board. | Ch. 1 |
| **The reading room / west wing** | Long tables, green lamps, rolling ladders. The frosted pane in its south wall is where the Tallyman is first seen. | Ch. 1 |
| **Archivist's office** | Wood panelling, a desk, a TV, a wall clock. Hardass made it the shelter's office; it is the first safe room. | Ch. 1 |
| **Records vault** | Underground stacks, moving shelves, the vault elevator to the old service tunnels. Nasri's desk is down here. | Ch. 1–3 |
| **The river district / Night Market** | Floating stalls and food carts on the flood plain; floods every spring. | Ch. 4 |
| **St. Brennic Primary School** and **Pell's Toys** | Where Zaga used to live with her grandmother, two streets from the Archive. | Ch. 5 |
| **The Deep Tunnel** | A six-year flood-relief tunnel under the river district. The boring machine *Ruth* broke into the burial vault three weeks ago. | Ch. 6 |
| **RaGoon City Waterworks** | Victorian pumping station and treatment plant; Dr. Atsa's lab is in the old chlorination house. | Ch. 7 |
| **Halloran Dam and the floodgates** | Upstream of the city. Opening the gates floods the river district, which is the city's "dawn protocol". | Ch. 8 |

Weather: it rains the whole night. Thunder, no lightning in the first act (the
lightning arrives with the rooftop chapter). Everything is wet.

---

## 2. Timeline

| When | What happened |
|---|---|
| **1891, autumn** | The *Sleeping Fever* sweeps the river district: people sleep for two days and wake up hungry. 212 dead in five weeks. The city walls off the worst street, then buries the dead (and, the records hint, some who weren't dead) in a sealed quarantine vault under the riverbank. |
| **1891, winter** | The city's first archivist, **Josiah Pell**, keeps the burial ledger: every name, and a number. The ledger's final count is wrong by one. The question of who that missing person was runs under the whole game. |
| **1902** | The Civic Archive opens. The 1891 files go into a sealed case in the vault, stamped *NOT FOR PUBLIC INSPECTION*. |
| **1974** | Floods. The Archive becomes the district's designated storm shelter. |
| **Six years ago** | The Deep Tunnel flood project starts. Deputy Mayor Corwin Ibn el Naghal runs it; the contractor belongs to his family. |
| **Three weeks ago** | *Ruth*, the tunnel-boring machine, breaks into the 1891 burial vault. The crew of nine come home with a fever. |
| **Three weeks ago, +2 days** | The nine wake up. Two attack their families. The city quarantines the crew in a plastic-walled ward in the tunnel depot and tells the press it is a flu cluster. |
| **Two weeks ago** | Dr. Atsa (city epidemiologist) matches the symptoms to the 1891 records Nasri pulls for her. She writes to City Hall. Naghal has the files moved into the Archive vault and tells the Archive staff they are evidence in a legal case. |
| **Ten days ago** | The River Festival goes ahead. Two of the tunnel crew have escaped the ward; one is seen in the festival crowd. |
| **Three days ago** | Infections across the river district. The Archive opens as a shelter. Warden Hardass counts 41 people in. Nasri goes down to the vault and starts copying the files onto microfilm. |
| **Two days ago** | Nasri mails a sealed package to his sister, then goes back down to the vault and does not come up. The night keeper, Orrin Vell, goes down after him. |
| **Tonight, 23:10** | The quarantine at the depot fails. Downtown loses power. The emergency broadcast stops. The Archive stops answering the radio. |
| **Tonight, 23:40** | Zegan's ambulance and Obcera's bike meet on Ashgrove Street. *(Prologue starts.)* |
| **Dawn, 06:12** | The floodgates open. *(Game ends.)* |

---

## 3. The Sleeping Fever

What the characters know, in order of how much they understand it.

**Street knowledge (anyone):** people get a fever, sleep for two days, wake up
wrong and hungry. A bite or a scratch passes it on. The dead get up.

**Medical (Zegan, Hardass, Dr. Atsa):**
- Spread by blood and saliva. A bite or a deep scratch is enough; airborne
  spread has not been seen.
- **Stage 1, fever** (6 to 30 hours after exposure): high temperature, grey skin,
  dark veins at the temples, aching joints, a strange calm.
- **Stage 2, the sleep** (about two days, shorter after a deep bite): the body
  shuts down almost to death. Pulse so slow most people would call it none.
- **Stage 3, waking:** the person comes back without memory or speech, with a
  constant hunger and a fixation on movement and sound. Habits survive: a
  cleaner still pushes at a mop, a nurse still walks the ward. This is why the
  Tallyman still counts.
- **The dead get up too**, much faster: anyone who dies with the fever in their
  blood wakes within minutes. This is what happened in Zegan's ambulance.
- Fire and destroying the brain stop them. Cold slows them down.

**Dr. Atsa's notes (files, Ch. 7):** the agent is a soil organism that lives in
the clay under the river and reached the 1891 graves with the floodwater. It
feeds on the host's glucose and forces sleep while it rewires the nervous
system. It grows *colonies* in hosts that survive a long time, which is where
the special infected come from. Her cure candidate starves it; it only works
before stage 3, and she can make exactly one dose with what she has.

### Why there are so many kinds of infected

Most of the infected are **Shamblers**. The others are what the organism makes
out of a particular body, a particular habit or a long time:

| Infected | In-world explanation | Game id |
|---|---|---|
| **Shambler** | Ordinary turned person. Keeps a habit from life. | `shambler` |
| **Runner** | Turned young and fit; the organism burns everything for speed. Short-lived. | `runner` |
| **Crawler** | Legs broken or gone; drags itself, grabs ankles. | `crawler` |
| **Possum** | Wakes but stays still until something is close enough; a stage-2 body that never fully woke. | `possum` |
| **Bloater** | The organism colonised the gut. Swells with gas and bursts. | `bloater` |
| **Screamer** | Colony in the throat. Its shriek wakes every sleeper within a block. | `screamer` |
| **Riot Guard** | Police from the first night, still in riot gear, still holding the shield up. | `riot` |
| **Brute** | Big host, months of growth in three weeks: the first tunnel crew. Charges. | `brute` |
| **Grappler** | Long-armed, pins a person to the ground. Comes from the hospital wards. | `grappler` |
| **Ventling** | Small, thin bodies that crawl through ducts and drop from ceilings. Mostly the shelter's dead. | `ventling` |
| **Spitter** | Colony in the stomach that makes acid; spits it. | `spitter` |
| **Burner** | Infected that walked through fire and kept walking; they set things alight. | `burner` |
| **Rot Hound** | Dogs. The organism takes animals too. | `hound` |
| **Larva** | Spawn of the Brood Mother. | `larva` |
| **Rat swarm** | Rats from the burial vault. | (Ch. 6) |

---

## 4. Factions

**City Hall.** Mayor Elspeth Grady (seen only on posters; she left the city two
days ago "for talks"). **Deputy Mayor Corwin Ibn el Naghal** runs everything
that matters. Every broadcast is his calm, warm voice.

**The Sweepers.** Naghal's private cleanup contractor, *Halloran Site Services*
on paper: ex-military, grey hazard suits, gas masks with a white stripe,
flamethrowers and rifles. Their job tonight: recover the 1891 files and the
microfilm, then remove everyone who has seen them. Commander: **Major Rusk**.
They carry lists of names. Obcera's name is on one.

**The shelter.** 41 people who trusted the banner over the Archive's gate:
*ALL WELCOME. NO ONE TURNED AWAY.* Hardass counted them in. Most of them are
still in the building.

**The Waterworks.** Dr. Atsa and two technicians who barricaded the
chlorination house. They have a radio, a generator and a cure that only works
once.

---

## 5. Characters

### Zegan (playable)
Night-shift paramedic, 28. Grew up in the river district, eleven years on the
ambulances. Rough voice, dry humour, bad knees, steady hands. Says little when
it matters and makes a joke when it doesn't. Patches up everyone, including
Obcera, who hates it.
- **Tonight:** his last call was a tunnel worker found in a stairwell, no pulse.
  The man sat up in the back of the ambulance and Zegan could not stop him. That
  is the first thing he can't fix, and he wants to save one person before sunrise.
- **His secret:** the patient scratched him. He doesn't tell anyone until Dr.
  Atsa looks at him in Ch. 7 ("You've known since the ambulance.").
- **Pronunciation:** ZEH-gan.

### Obcera (playable)
Motorcycle courier, 27. Fast, loud, fearless, the best shot in any room. Knows
every alley in the city because she has ridden all of them at night. "Obi" to
her brother and to nobody else.
- **Tonight:** her estranged brother Nasri sent her a sealed package to deliver
  to the Archive by midnight. They haven't spoken in two years. She wants to put
  it in his hands and ask him why.
- **The package:** a lead-lined film can holding microfilm copies of the 1891
  burial ledger, the depot ward's medical reports, and the memo in which Naghal
  orders the files sealed. Nasri sent it to her because she is the one person
  who would actually ride through a riot to deliver something.
- **Pronunciation:** ob-SEH-ra.

### Nasri
Obcera's older brother, 34, records clerk at the Archive for nine years. Careful,
quiet, honest to the point of trouble. Pulled the 1891 files for Dr. Atsa,
understood them, and started copying everything. Went down to the vault two
days ago and didn't come back up. In Ch. 6 they find him under the river,
half changed and still trying to talk ("Obi... the count's wrong. It's always
been wrong.").

### Warden Jackson Hardass
Shelter coordinator, 58, ex-army medic, twenty years running the Archive's
security desk. Built like a door. Kept the shelter alive for three days, counted
41 people in, and got bitten on the second night pulling a child out of the
reading room. Hides it with a rag around the wrist so the others won't panic.
- **Tonight:** stays behind in the office "to keep the count", gives them the
  vault elevator key card. He knows exactly what is happening to him.
- **Ch. 2:** he is already down in the Undercroft, barred into the shelter
  staff's muster room with the generator's starting handle on his belt. Over
  the tannoy he tells them where it is and unbars the door. When they get
  there he counts the shelter one last time ("Not one of them went out.") and
  turns in front of them, in his riot gear, with the steel truncheon and the
  riot shield he drilled with for twenty years. The bite on his back has
  swollen into a glowing growth. Boss: *The Last Warden*.
- **Voice:** hoarse, commanding, exhausted (Eleven v4, voice "Clyde").

### Zaga Sagheera
10 years old, has lived in the Archive's air ducts for three days with a
slingshot and a tin of biscuits. Knows every secret route in the building.
Trusts nobody over twelve until Zegan patches her hand. Lived with her
grandmother over Pell's Toys.

### Dr. Atsa
City epidemiologist, 45. First to name the fever, first to be ignored. Sharp,
tired, funny in a bleak way. Holed up in the Waterworks with a cure candidate.
Makes one dose and gives it to Zegan, not Obcera.

### Deputy Mayor Corwin Ibn el Naghal (villain)
52, smiling, reasonable, the voice on every broadcast ("Stay inside. Help is
coming. Your city has not forgotten you."). Ran the Deep Tunnel project, knew
about the vault from his family's papers, and ordered the cover-up. In the
finale he injects himself with pure fever to stop them leaving with the
evidence. Pell's ledger is wrong by one because the missing name in 1891 was a
Naghal: his great-grandfather, who bought his way off the list and out of the
quarantine. That is why the Tallyman turns on him at the end: his name is the
one that was missing from the count.

### The Tallyman
**Orrin Vell**, the Archive's night keeper for 31 years. Kept the building's
visitor ledger by hand and knew every regular by name. Went down to the vault
after Nasri two days ago, was bitten, and came back changed: over two metres
tall now, in the sealed black rubber flood coat and riveted brass respirator
from the vault's 1974 flood kit, dragging the hooked iron pole the archivists
use to pull boxes off the high shelves.
- Still doing his job: counting everyone in the building, and correcting the
  count. He mutters numbers ("...forty-one... forty-two...") and lines from the
  job ("The Archive is closed. You are late.").
- He can't be killed until the finale. Enough damage drops him to one knee for
  about four seconds. He opens ordinary doors; locked doors, co-op doors and
  safe rooms stop him.
- **First seen** in Ch. 1 through the reading room's frosted glass. **Hunts**
  in Ch. 2, 3 and 8. **Unmasked** in Ch. 8 (boss 9).

---

## 6. The count

The story's one motif. Use it, don't explain it.

- The narrator: "Every city keeps a ledger. Births. Deaths. Debts."
- Pell's 1891 ledger: 212 names, numbered, and a total that is off by one.
- Hardass: "Forty-one people came here for shelter. I counted them in. Count
  yourselves out."
- The count board in the Great Hall: 41, then tally marks crossed out.
- The Tallyman counts out loud. In co-op he says the players' number too.
- Nasri: "The count's wrong. It's always been wrong."
- The ending: "They left as the only two people who knew the true count."
- Collectibles: **12 burial records** from 1891 hidden through the game. Find
  all 12 to unlock the secret boss, *The First Sleeper* (patient zero, awake
  under the river).

---

## 7. Chapter beats and where they live in the code

| # | Chapter | Cutscene id / file | State |
|---|---|---|---|
| 0 | **Last Call** (prologue) | `intro` in `scripts/story/chapter1_story.gd`: narrated film `assets/story/video/intro_a.ogv`, crash and dialogue `intro_b.ogv`, then the burning wreck in the engine | done |
| 1 | **Shelter** | `gates`: the gates and banner, faces at the windows, chapter card | done |
| 1 | | `warden`: Hardass in the office, gives the vault elevator key card (`vault_card`) | done |
| 1 | | `glass`: the Tallyman behind the frosted pane | done |
| 2 | **The Count** | `scripts/story/chapter2_story.gd` (the Undercroft, see `docs/chapter2.md`): `c2_arrival` the lift opens on the service level; `c2_hall` the flood door and the dead generator; `c2_hunt` the master clock strikes and the Tallyman starts hunting; `c2_intercom` Hardass on the tannoy; `c2_warden` Hardass has turned (boss 1, `WardenBoss`); `c2_end` Nasri's staff card and his chalk in the deep stacks | done |
| 3 | **Paper Trail** | Nasri's office in the vault, the recording; the Bookbinder (boss 2) | to do |
| 4 | **Night Market** | Naghal's broadcast; the Sweepers arrive | to do |
| 5 | **Zaga** | the grate and the slingshot; Taken | to do |
| 6 | **Deep Tunnel** | the burial vault; Nasri | to do |
| 7 | **The Cure** | One dose | to do |
| 8 | **Floodgate** | Dawn protocol; the ending | to do |

Story flags (in `GameState.world_flags`, saved with the game): `story_intro`,
`story_gates`, `story_warden`, `story_glass`, plus `objective` (the text on the
objective banner). Chapter 2 adds `story_c2_arrival`, `story_c2_hall`,
`story_c2_hunt`, `story_c2_intercom`, `story_c2_warden`, `story_c2_end` and its
world flags (`docs/chapter2.md`).

---

## 8. How the cutscenes work (for writers)

- A scene is a list of steps in the chapter's story script (see the header of
  `scripts/story/cutscenes.gd` for every step type). Voice lines live in
  `assets/audio/voice/story/<line id>.ogg`.
- **The world changes in `on_cutscene_end()`**, never in the middle of a
  scene, so skipping is always safe.
- **Co-op:** the host starts a scene for both phones once both have loaded. Each
  phone plays it locally. Skip needs both players: the first tap shows
  "Waiting for partner...", the partner sees "Your partner wants to skip".
- **Two kinds of scene:** full-motion film for things the engine can't stage
  (the city from the air, the crash), and in-engine scenes for everything in
  the levels, with real character animation and moving cameras. No slideshows.
- The narrator speaks only at the start and end of each act.

## 9. Voices

| Who | Voice | Notes |
|---|---|---|
| Narrator | Gemini TTS "Charon", slow and close | Write "Rah-goon" in the text. |
| Zegan | Eleven v4 | See `tools/voice/cast.json`. |
| Obcera | Eleven v4 | Screams also on v4. |
| Tallyman | masked with a filter | Breathing and speech never overlap. |
| Hardass | Eleven v4 "Clyde" (`2EiwWnXFnvU5JabPnv8n`) | hoarse, commanding, exhausted; `[weak, rasping]` as he turns |
| Hardass on the tannoy | same voice, `hardass_pa` in `cast.json` | through a speaker filter (chapter 2 intercom) |

Generate new lines with `tools/voice/say.py`. The fal content filter rejects
violent wording ("shoot you"): rephrase rather than fight it.

## 10. Writing rules

- Short lines. People under pressure don't make speeches.
- Zegan understates; Obcera says the thing out loud; Hardass gives orders;
  Naghal reassures; the Tallyman counts.
- No exposition dumps in dialogue. Put the detail in files and let the scenes
  carry feeling.
- Every chapter ends on a question the next one answers.
- Keep it original: no names, places, organisations, creatures or lines from
  other games.
