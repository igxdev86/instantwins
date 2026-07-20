# INSTANTWINS — START HERE
### The whole plan in plain English. Four stages. Do them in order.

**The picture:** Your game files are posters. GitHub is the locker you keep
them in. Vercel is the shop window that shows whatever is in the locker.
Supabase is the real till — one shared memory of what's sold and who won.
Right now every player's phone has its own pretend till. Stage 3 swaps in
the real one.

---

## STAGE 1 — Put the posters in the window (get it live)

1. On your phone, open **github.com** and log in.
2. Top right **+** → **New repository**. Name it `instantwins`. Keep it
   **Private**. Tap **Create repository**.
3. Open the zip I gave you (**instantwins-games-site.zip**) in your Files
   app so the 13 files are loose.
4. In the new repo: **Add file → Upload files**. Pick all 13 files
   (files, not a folder). Tap **Commit changes**.
5. Open **vercel.com** → **Add New → Project** → Import `instantwins` →
   **Deploy**. Change nothing.
6. About 30 seconds later you get a link like `instantwins-xxx.vercel.app`.
   Tap it. That's your site, live. Tiles work, games work.
7. Later, to use the real name: Vercel → your project → **Settings →
   Domains** → add `instantwins.co.uk` → copy the two DNS lines it shows
   into your domain company's control panel.

*Everything on the live site is play-money. Nobody can spend or win
anything real yet. That's on purpose.*

---

## STAGE 2 — Bolt on the old rooms (your original 9-page site)

You have an older zip from our other chat: **instantwins-uk-site.zip**.
Inside it is a folder called `iwsite` with 9 pages plus `styles.css` and
`app.js`. Those are the Card, Results, Free entry, Fairness, Terms,
Privacy, Play safe, Account and About pages.

1. Unzip it. Go **inside** the `iwsite` folder.
2. **Before uploading**, rename its `index.html` to `card.html`
   (long-press the file → Rename). That's the old Card board moving to its
   new address — my homepage already has a "Card" button pointing there.
3. In GitHub: **Add file → Upload files** → pick those files → Commit.
4. Vercel redeploys itself. Done — the Card, Results, Free entry and
   Fairness buttons all come alive.

**One known wrinkle:** the 9 old pages have a menu button that says
"Card" but points at `index.html` (which is now the games homepage).
Nothing breaks — it's just the wrong label. Easiest fix: paste that old
zip into our chat and I'll hand you back corrected copies. Or skip it for
now; it's cosmetic.

---

## STAGE 3 — Install the real till (Supabase)

This makes pools REAL: one shared pool per game, real sold counts, real
prize allocation, the seed genuinely locked before anyone buys.

1. Open **supabase.com** → New project. Call it `instantwins`. Pick
   London. Wait for it to build (~2 mins).
2. Left menu → **SQL Editor** → **New query** → paste the whole of
   **supabase-schema.sql** (in this kit) → **Run**. You should see
   "Success". That just built the stockroom: 11 games, their prize
   tables, and the machine that opens pools, seals the seed, and hands
   out entries one by one.
3. Connect it to Vercel: Supabase → your project → **Integrations →
   Vercel** → connect to your `instantwins` Vercel project. This quietly
   posts the keys through the letterbox (same as racing1 — it sets
   SUPABASE_URL and the service key for you).
4. Give the shop a serving hatch — two tiny files that must live in a
   folder called `api`:
   - In GitHub: **Add file → Create new file**. In the name box type
     `api/pool.js` (typing the `/` creates the folder). Paste the
     contents of **pool.js** from this kit. Commit.
   - Repeat with `api/buy.js` and **buy.js**.
5. Vercel redeploys. Test the hatch: visit
   `your-site.vercel.app/api/pool?game=PL` — you should see live pool
   numbers, not an error.
6. Tell me "the API is up" and I'll rewire all 11 games to use the real
   till instead of the pretend one. One change, whole suite updates.

**Big honest warnings, in kid language:**
- The buy hatch currently gives entries away FREE. There's no card
  machine yet (Stripe) and no login (accounts). That's the next job
  after this. So don't post the link anywhere public yet.
- No real money moves anywhere in any of this. Before it ever does:
  solicitor sign-off on the Schedule 2 structure. Non-negotiable.

---

## STAGE 4 — Make the games feel great (your job, then mine)

Play every game on the live site on your actual phone and score each one
on three things:

1. **Speed** — does the reveal drag? (Plinko ~1.7s, Rocket up to ~6s on
   a top win. Too slow at £2-a-go pace?)
2. **The lose moment** — does "no win" feel fun enough to go again?
   (Claw slip, Pusher teeter, Ladder bust are the near-miss ones.)
3. **The win moment** — does a £2 money-back win feel like a win?

Send me a list like "Rocket too slow, Balloon boring, Claw perfect" and
I'll tune the lot in one pass — every game comes from one generator, so
fixes apply everywhere at once.

---

### Order of play from here
Stage 1 today (10 minutes). Stage 2 whenever you find the old zip.
Stage 3 when you've got 20 minutes with a cuppa. Stage 4 is ongoing.
After that: payments + accounts + solicitor, then it's a real business.
