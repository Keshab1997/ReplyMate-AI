# Zero-bill smart features — what to build next

Written for a constraint, not a wish: **no Firebase billing.** That rules out
Cloud Functions (Blaze-only, card required) and therefore the server-side proxy.
Everything below is client-side only, and every item is judged on the two
currencies this app actually spends:

- **Firestore reads/writes** — free tier is 50K reads + 20K writes/day. Today
  the app uses almost none. Fine.
- **AI tokens** — this is the real money. Not Firebase, but the reason a
  "free" app still costs something. Every item is scored on what it saves here.

Rule of thumb used to rank: *a feature that saves tokens is worth more than one
that spends them, and a feature that works with no key at all is worth most.*

---

## The security question, answered honestly for a no-bill app

The README's stated risk is that any signed-in client can read the key pool out
of Firestore. With no proxy, the options are:

| Option | Leak surface | Bill | Verdict |
|---|---|---|---|
| Current shared pool in Firestore | any signed-in client | provider tokens | acceptable only for a personal app |
| Server proxy | none | **Blaze required** | off the table — you said no bill |
| **BYOK: the user pastes their own key** | **none** | **none** | **best move available** |

**BYOK is the real answer here, not a weaker proxy.** If the key lives in the
user's own device storage (Hive, already a dependency) and never enters
Firestore, there is nothing to leak: no rules to get wrong, no pool to rotate,
no quota for someone else to burn. The app's admin pool then becomes optional —
useful for *you* testing on several devices, not required to use the app.

It also removes the "guest mode" awkwardness: today `google-services.json`
absent means no AI at all. With BYOK, **no Firebase account can still mean a
working app** — which is a stronger privacy story than the current README.

> Ask: BYOK first, pool second. That is a product decision, so it is listed as
> item 7 rather than done unasked.

---

## Tier 1 — frugal wins (all client-side, all cheap to build)

### 1. Reply cache by message hash — *saves the most tokens*
The same message arrives repeatedly: "ok", "hi", "kal asbo?", a delivery ping.
Cache `hash(message + tone + language + length + suggestionCount) → replies` in
Hive with a TTL (say 7 days), and serve a hit without calling the provider.

- Where: a `ReplyCache` in front of `ReplyRepository.generate`.
- Why it is safe: the hash is over *content the user already sent to the AI*,
  so nothing new leaves the device, and a cache hit sends nothing at all.
- Honest limit: cached replies go stale for anything time-sensitive ("kal"),
  which is why the TTL is short and why a hit is labelled **"from cache"** with
  a *Regenerate* button that bypasses it. Never pretend a cached reply is fresh.
- Expected saving: for chat use, 20–40% of taps are repeats.

### 2. A per-day AI budget the app enforces itself — *protects the wallet*
`ApiKeyManager` protects against *dead* keys; nothing protects against *usage*.
Add a local counter: N requests/day (configurable, default ~50), kept in Hive.
At the limit the app says so plainly and offers the offline suggestions below,
instead of an error or, worse, a silent provider bill.

- This is the only thing standing between "free" and "a surprise invoice".
- Per-device, not per-account — be honest about that in the UI copy.

### 3. On-device reply suggestions — *works with no key, no Firebase, no network*
The message itself usually implies the answer. A tiny local layer can offer 2–3
candidates with zero tokens:

- A question mark → "হ্যাঁ, ঠিক আছে", "না, পরে বলছি", "একটু ভাবি"
- A greeting → greeting reply in the chosen tone
- "ok / thik ache / done" → acknowledgment
- A date/time mention → "আমি দেখে জানাচ্ছি"

Not a model, and it must not pretend to be one: label the section
**"Offline suggestions"** and keep the AI button right beside it. This is the
feature that makes the app work on a plane, on a dead key, or with no Firebase
at all — and it costs nothing ever.

### 4. Spend less per request (no new screen, just defaults)
- **One suggestion by default, not three.** Three completions is three times the
  output tokens for one line the user picks. A "more options" tap spends them
  only when asked.
- **Cap `max_tokens`** at what a chat reply needs (~200, not the model default).
- **Trim the prompt**: today it carries tone description, language rules, memory
  examples and the message. Send memory examples only when the user explicitly
  wants "their voice"; otherwise it is the largest block of input tokens.
- Expected saving: 40–60% per call, invisible to the user.

---

## Tier 2 — the "smart" part (still free, still client-side)

### 5. Local intent + tone suggestion
Classify the incoming message on-device (question / thanks / apology / greeting
/ plan / complaint) with plain heuristics — no model, no tokens. Use it to
pre-select the tone chip and to order the offline suggestions. A tap saved is
the cheapest feature there is.

### 6. Detect the incoming language, reply in it by default
The app has `ReplyLanguage` as a setting. A script-based detector (Bengali vs
Devanagari vs Latin) is a few lines and removes a wrong setting the user would
otherwise fix by hand. This is the single most "smart"-feeling change per line
of code in this list.

### 7. BYOK — bring your own key *(the security item above)*
Settings → "Use my own AI key": the key goes to Hive, never to Firestore; the
app skips the pool entirely. Consequences: no shared secret to leak, and the
admin section becomes optional for anyone but the owner.

### 8. Smart regenerate before spending tokens
When the user taps *Regenerate*, first offer a **free variant**: re-order or
re-punctuate the offline/template candidates. Only escalate to a paid call when
that is refused. Saves the most common wasteful tap: "not quite right" → new
request.

### 9. Reply history that respects the memory rules
Conversation memory already exists with four walls (off by default, allowlist,
device-only, capped). Reuse it: when a contact has memory, the tone suggestion
can use the last tone the user actually picked. No new storage, no new risk.

---

## Deliberately not proposed

| Idea | Why not |
|---|---|
| Server proxy / rate limiting | needs Blaze + card |
| Firestore-backed analytics per reply | writes cost reads later, and answers nothing the error log doesn't |
| Multi-device sync of settings | Firestore writes for a per-device truth |
| Push notifications via FCM | FCM is free, but the app's whole point is *not* nagging |
| Auto-send anything | the app's one non-negotiable rule |

---

## Suggested order

| # | Item | Why first | Rough size |
|---|---|---|---|
| 1 | ~~Reply cache + "from cache" label~~ **done** | biggest token saving, no UI redesign | small |
| 2 | ~~Daily AI budget + honest limit state~~ **done** | the safety net for "no bill" | small |
| 3 | ~~One suggestion by default + `max_tokens` + prompt trim~~ **done** | pure saving, invisible | small |
| 4 | Offline suggestions | makes the app usable with no key at all | medium |
| 5 | Language auto-detect + intent chips | the "smart" feel | small |
| 6 | BYOK | the real security answer here | medium |

1–3 are one batch and can ship together. 4 is the one that changes what the app
*is* (works with no Firebase, no key, no network), so it deserves its own
commit and its own device test.

## What this does NOT fix

The key-pool leak stays as it is until either BYOK lands or a proxy exists.
Nothing in this document makes the current shared-pool design safer — it only
makes the app cheaper to run, and adds a path (BYOK) where the leak cannot
happen at all.
