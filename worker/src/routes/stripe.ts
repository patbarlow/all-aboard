import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { setStripeCustomerId, updatePlanByStripeCustomer } from "../db";

/**
 * Look up an existing Stripe customer by email, or create one if none exists.
 * This ensures customers who subscribe to multiple products share a single
 * Stripe customer record and see all subscriptions in the billing portal.
 */
async function getOrCreateStripeCustomer(
  secretKey: string,
  email: string,
  userId: string,
): Promise<string> {
  // Search for an existing customer with this email across all products.
  const searchRes = await fetch(
    `https://api.stripe.com/v1/customers/search?query=${encodeURIComponent(`email:'${email}'`)}&limit=1`,
    { headers: { Authorization: `Bearer ${secretKey}` } },
  );
  if (searchRes.ok) {
    const result = (await searchRes.json()) as { data: { id: string }[] };
    if (result.data.length > 0) return result.data[0]!.id;
  }

  // No existing customer — create one.
  const createRes = await fetch("https://api.stripe.com/v1/customers", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secretKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ email, "metadata[user_id]": userId }).toString(),
  });
  if (!createRes.ok) throw new Error(`Stripe customer create failed: ${await createRes.text()}`);
  const customer = (await createRes.json()) as { id: string };
  return customer.id;
}

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

/**
 * Authed: start a 7-day free trial directly — no card required, no browser redirect.
 * Creates a Stripe customer + trialing subscription and immediately sets plan = pro.
 */
app.post("/trial", requireAuth, async (c) => {
  const user = c.get("user");

  if (user.plan === "pro") return c.json({ error: "already_subscribed" }, 400);

  let customerId = user.stripe_customer_id;
  if (!customerId) {
    try {
      customerId = await getOrCreateStripeCustomer(c.env.STRIPE_SECRET_KEY, user.email, user.id);
    } catch (e) {
      return c.json({ error: "stripe_error", detail: String(e) }, 502);
    }
    await setStripeCustomerId(c.env.DB, user.id, customerId);
  }

  const res = await fetch("https://api.stripe.com/v1/subscriptions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      customer: customerId,
      "items[0][price]": c.env.STRIPE_PRICE_ID,
      trial_period_days: "7",
      payment_behavior: "default_incomplete",
      "payment_settings[save_default_payment_method]": "on_subscription",
    }).toString(),
  });

  if (!res.ok) return c.json({ error: "stripe_error", detail: await res.text() }, 502);
  const sub = (await res.json()) as { id: string; status: string; trial_end: number | null };
  const trialEnd = sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null;

  // Set plan immediately so the app doesn't have to wait for the webhook.
  await updatePlanByStripeCustomer(c.env.DB, customerId, "pro", sub.id, trialEnd);

  return c.json({ ok: true });
});

/**
 * Authed: create a Stripe Checkout session for subscribing after a trial ends.
 * Returns a URL the client opens in the browser.
 */
app.post("/checkout", requireAuth, async (c) => {
  const user = c.get("user");

  let customerId = user.stripe_customer_id;
  if (!customerId) {
    try {
      customerId = await getOrCreateStripeCustomer(c.env.STRIPE_SECRET_KEY, user.email, user.id);
    } catch (e) {
      return c.json({ error: "stripe_error", detail: String(e) }, 502);
    }
    await setStripeCustomerId(c.env.DB, user.id, customerId);
  }

  const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      customer: customerId,
      mode: "subscription",
      "line_items[0][price]": c.env.STRIPE_PRICE_ID,
      "line_items[0][quantity]": "1",
      success_url: "https://allaboard.patbarlow.com/subscribed",
      cancel_url: "https://allaboard.patbarlow.com",
    }).toString(),
  });

  if (!res.ok) return c.json({ error: "stripe_error", detail: await res.text() }, 502);
  const session = (await res.json()) as { url: string };
  return c.json({ url: session.url });
});

/**
 * Authed: create a Stripe billing portal session and return its URL.
 * The client opens it for the user to manage their subscription.
 */
app.post("/portal", requireAuth, async (c) => {
  const user = c.get("user");
  if (!user.stripe_customer_id) return c.json({ error: "no_customer" }, 400);

  const res = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      customer: user.stripe_customer_id,
      return_url: "https://allaboard.app",
    }).toString(),
  });

  if (!res.ok) return c.json({ error: "stripe_error", detail: await res.text() }, 502);
  const portal = (await res.json()) as { url: string };
  return c.json({ url: portal.url });
});

/**
 * Stripe webhook: update plan on subscription lifecycle events.
 */
app.post("/webhook", async (c) => {
  const rawBody = await c.req.text();
  const signature = c.req.header("Stripe-Signature");
  if (!signature) return c.json({ error: "missing_signature" }, 400);

  const verified = await verifyStripeSignature(rawBody, signature, c.env.STRIPE_WEBHOOK_SECRET);
  if (!verified) return c.json({ error: "invalid_signature" }, 400);

  const event = JSON.parse(rawBody) as { type: string; data: { object: Record<string, unknown> } };

  switch (event.type) {
    case "customer.subscription.created":
    case "customer.subscription.updated": {
      const sub = event.data.object as { id: string; customer: string; status: string; trial_end: number | null; items: { data: { price: { id: string } }[] } };
      if (!sub.items.data.some((item) => item.price.id === c.env.STRIPE_PRICE_ID)) break;
      const plan = sub.status === "active" || sub.status === "trialing" ? "pro" : "free";
      const trialEnd = sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null;
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, plan, sub.id, trialEnd);
      break;
    }
    case "customer.subscription.deleted": {
      const sub = event.data.object as { customer: string; items: { data: { price: { id: string } }[] } };
      if (!sub.items.data.some((item) => item.price.id === c.env.STRIPE_PRICE_ID)) break;
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, "free", null, null);
      break;
    }
  }

  return c.json({ received: true });
});

async function verifyStripeSignature(body: string, header: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => { const [k, ...rest] = kv.split("="); return [k, rest.join("=")]; }),
  ) as Record<string, string | undefined>;
  const timestamp = parts["t"];
  const expected = header.split(",").filter((kv) => kv.startsWith("v1=")).map((kv) => kv.slice(3));
  if (!timestamp || expected.length === 0) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${body}`));
  const computed = Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return expected.some((cand) => cand.length === computed.length && cand === computed);
}

export default app;
