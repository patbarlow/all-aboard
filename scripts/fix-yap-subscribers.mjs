/**
 * Resets All Aboard users whose plan was incorrectly set to "pro" via a
 * Yap subscription. Run this once after deploying the webhook fix.
 *
 * Usage:
 *   STRIPE_SECRET_KEY=sk_live_... STRIPE_PRICE_ID=price_... node scripts/fix-yap-subscribers.mjs
 *
 * Dry-run by default — pass --apply to actually write to the DB.
 */

const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY;
const STRIPE_PRICE_ID = process.env.STRIPE_PRICE_ID;
const APPLY = process.argv.includes("--apply");

if (!STRIPE_SECRET_KEY || !STRIPE_PRICE_ID) {
  console.error("Set STRIPE_SECRET_KEY and STRIPE_PRICE_ID env vars.");
  process.exit(1);
}

// Fetch all active/trialing All Aboard subscription IDs from Stripe.
async function fetchValidSubscriptionIds() {
  const ids = new Set();
  let startingAfter = null;

  while (true) {
    const params = new URLSearchParams({
      "price": STRIPE_PRICE_ID,
      "status": "all",
      "limit": "100",
    });
    if (startingAfter) params.set("starting_after", startingAfter);

    const res = await fetch(`https://api.stripe.com/v1/subscriptions?${params}`, {
      headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
    });
    if (!res.ok) throw new Error(`Stripe error: ${await res.text()}`);
    const data = await res.json();
    for (const sub of data.data) ids.add(sub.id);
    if (!data.has_more) break;
    startingAfter = data.data.at(-1).id;
  }

  return ids;
}

const validIds = await fetchValidSubscriptionIds();
console.log(`Found ${validIds.size} valid All Aboard subscription(s) in Stripe.`);

// Build the SQL to find and fix affected users.
// Users with plan=pro whose subscription ID is NOT a valid All Aboard one.
const placeholders = [...validIds].map(() => "?").join(", ");
const findSql = validIds.size > 0
  ? `SELECT id, email, stripe_subscription_id FROM users WHERE plan = 'pro' AND (stripe_subscription_id IS NULL OR stripe_subscription_id NOT IN (${placeholders}));`
  : `SELECT id, email, stripe_subscription_id FROM users WHERE plan = 'pro';`;

const fixSql = validIds.size > 0
  ? `UPDATE users SET plan = 'free', stripe_subscription_id = NULL, trial_end = NULL WHERE plan = 'pro' AND (stripe_subscription_id IS NULL OR stripe_subscription_id NOT IN (${placeholders}));`
  : `UPDATE users SET plan = 'free', stripe_subscription_id = NULL, trial_end = NULL WHERE plan = 'pro';`;

const args = [...validIds].map((id) => `'${id}'`).join(", ");

console.log("\n--- Step 1: Find affected users ---");
console.log("Run this to see who will be changed:\n");
if (validIds.size > 0) {
  console.log(`wrangler d1 execute trainboard --remote --command "${findSql.replace(/"/g, '\\"').replace(placeholders, args)}"`);
} else {
  console.log(`wrangler d1 execute trainboard --remote --command "${findSql}"`);
}

console.log("\n--- Step 2: Apply the fix ---");
console.log("Run this to reset affected users to free:\n");
if (validIds.size > 0) {
  console.log(`wrangler d1 execute trainboard --remote --command "${fixSql.replace(/"/g, '\\"').replace(placeholders, args)}"`);
} else {
  console.log(`wrangler d1 execute trainboard --remote --command "${fixSql}"`);
}

console.log("\nReplace the IN(...) placeholder values above with the actual subscription IDs listed by the script output if needed.");
console.log("\nValid All Aboard subscription IDs:");
for (const id of validIds) console.log(" ", id);
