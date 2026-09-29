# Independent W1 website consent review — 2026-09-29

Read-only review of canonical `/Users/alexander_markin/Documents/code/louppe/website/analytics-consent.js` and `scripts/analytics-consent.test.mjs`, after completing file safety implementation. Website/shared AGENTS.md read. No source edits, build output regeneration, deployments, commits, or changes to preexisting murlexander repository references.

## Final result: no confirmed remaining issue in the reviewed scope

Root resolved both independently reproduced withdrawal edge cases. Final script, existing tests, and independent probes were rerun after those fixes. This subagent remained read-only for website sources.

## Initial quota/reload finding — resolved

**Resolved by root: failed localStorage write caused explicit withdrawal to be undone by the ensuing reload.**

Source: `analytics-consent.js:32–36` (remember), `:94–99` (withdrawal/reload).

Trigger: a still-valid saved acceptance exists. localStorage.getItem works, but setItem fails, for example when origin storage is full and the serialized new rejection exceeds available quota. The visitor clicks “no analytics.” `remember` retains rejection only in visitOnlyChoice. Reconciliation disables the tag and reloads the page. That visit-only memory is lost; the accepted storage value remains. The new page reads it as accepted and requests/enables analytics again without another opt-in.

Reproduced using the actual current source and the test suite's browser helper extended solely to model write-only storage failure and a fresh page after reload:

```
before rejection: scripts=1, disabled=false, stored=accepted
rejection before reload: disabled=true, reloads=1, stored=accepted
after actual reload: scripts=1, disabled=false, bannerHidden=true, stored=accepted
```

Probe: `/private/tmp/louppe-fixes-2026-09-29/website-consent-write-blocked-probe.mjs`.

Root changed failed rejection persistence to remove stale saved acceptance where possible and retain a visit-only rejection. Automatic reload is suppressed while that fallback is active. The final quota probe shows disabled=true/reloads=0/staleAcceptancePresent=false, followed by scripts=0/disabled=true on a fresh page. Root was notified immediately; this subagent made no website edits.

The initial coverage gap which hid this bug was: the original blocked-storage test blocked both getItem and setItem, while reload only incremented a counter. Root added separate write-only and fully unpersistable regressions; the former creates a fresh page after stale acceptance removal, and the latter now delivers a storage event while the local refusal is active.

## Queued storage event race — resolved

The intermediate source cleared `visitOnlyChoice` unconditionally in the storage handler. If reads work but both write and removal fail, a locally rejected choice must remain effective for the current visit. A storage acceptance event queued by another tab before that local rejection can arrive afterward, clear the fallback rejection, and re-enable the unchanged older saved acceptance.

Actual-source reproduction: other tab accepts at t1, failed local rejection at t2, deliver queued earlier acceptance event. Before delivery disable=true/reloads=0; afterward disable=false and a download event is recorded. This does not require a manual navigation or reload, so it exceeds the acknowledged inability to persist a fully unpersistable choice beyond the visit.

Probe `/private/tmp/louppe-fixes-2026-09-29/website-consent-final-quota-probe.mjs`; log `/private/tmp/louppe-fixes-2026-09-29/website-consent-final-quota-probe.log`. Root fixed the storage handler to preserve `visitOnlyChoice === "rejected"` until this visitor explicitly chooses again. Final probe after delivering the older queued event: disabled=true, downloads=0, reloads=0. Explicit fresh local choice can still update or replace the fallback normally.

The same probe confirms root's first fix: quota failure removes stale acceptance, reloads=0, and a fresh write-blocked page requests no analytics script.

## Checked branches without another confirmed issue

- Cross-tab accepted → rejected, saved-key removal, storage.clear (`key=null`), and unrelated storage events: current storage state is reread, not trusted from a possibly stale event payload. Explicit rejection disables, queues denied consent, and reloads. Download interception also rechecks storage even if the storage event was missed.
- Missing, invalid value, corrupt JSON, nonfinite/invalid timestamps, future choice, and exact lifetime boundary: no initial tag script or download event; disable property starts true. Newly unavailable storage also fails closed.
- Expiry timer: maximum browser timeout is clamped, subsequent chunks recheck current acceptance, and expiry disables an otherwise continuously active accepted page. Reconciliation clears the previous timer; even an already queued stale callback reads the newest saved choice rather than expiring a renewed choice.
- Fully blocked read/write storage: no initial tag. Explicit acceptance is limited to in-memory visit choice, subsequent rejection disables, and a freshly created blocked-storage page requests no tag.
- Withdrawal while Google script is loading: disable is set before consent denial/reload. Reacceptance is explicit, grants consent again, and does not append a second script in the still-current page. The implementation contains no onload closure able to resurrect a stale accepted local choice.
- No opt-in request: initial undecided/rejected/expired branches do not construct or append the external tag. Repository HTML/JS search found no other GA tag, Google Analytics preconnect, or tagmanager preload bypass.
- Production host gate: exactly HTTPS `louppe.eu`. localhost, alternate copied hosts, `www.louppe.eu`, `louppe.eu.evil.test`, and HTTP production hostname never append the tag or emit download analytics.
- Download path preserves `/murlexander/louppe-media-culler/releases/latest/download/Louppe.zip` and GitHub hostname matching. Existing murlexander changes were preserved.

## Evidence and limits

`node --test scripts/analytics-consent.test.mjs`: **11 tests passed, 0 failures**. Log `/private/tmp/louppe-fixes-2026-09-29/website-consent-review-tests.log`.

Additional independent probes for initial choice values, host variants, stale callbacks, timer chunking, and fully blocked post-reload pages all passed. Source `/private/tmp/louppe-fixes-2026-09-29/website-consent-extra-probes.mjs`; log `/private/tmp/louppe-fixes-2026-09-29/website-consent-extra-probes.log`.

This was source/state-machine review and bounded Node VM execution. It did not load Google production code, inspect actual network beacons/cookie jars, or deploy a website. Both quota/reload and queued-storage-event findings are resolved, with no confirmed remaining issue in the requested code/state-machine scope. The final quota probe has passing assertions for no new script on a fresh page when stale acceptance can be removed and for disabled=true/downloads=0/reloads=0 after an older event when all writes/removal fail. Fully unpersistable consent changes can only survive the current visit: a manual navigation or reload destroys memory and cannot be made to remember a choice that the browser refuses to store. The implementation now avoids triggering that loss automatically and preserves refusal across focus, visibility, click, timers, and storage events within the same visit.
