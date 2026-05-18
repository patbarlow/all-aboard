import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { getUserByStripeCustomer, setStripeCustomerId, updatePlanByStripeCustomer } from "../db";

/**
 * Look up an existing Stripe customer by email, or create one if none exists.
 * This ensures customers who buy multiple products share a single
 * Stripe customer record.
 */
async function getOrCreateStripeCustomer(
  secretKey: string,
  email: string,
  userId: string,
): Promise<string> {
  const searchRes = await fetch(
    `https://api.stripe.com/v1/customers/search?query=${encodeURIComponent(`email:'${email}'`)}&limit=1`,
    { headers: { Authorization: `Bearer ${secretKey}` } },
  );
  if (searchRes.ok) {
    const result = (await searchRes.json()) as { data: { id: string }[] };
    if (result.data.length > 0) return result.data[0]!.id;
  }

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
 * Authed: create a Stripe Checkout session for a one-time $5 purchase.
 * Returns a URL the client opens in the browser.
 */
app.post("/checkout", requireAuth, async (c) => {
  const user = c.get("user");

  if (user.plan === "pro") return c.json({ error: "already_purchased" }, 400);

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
      mode: "payment",
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
 * Stripe webhook: grant pro access on successful one-time payment.
 */
app.post("/webhook", async (c) => {
  const rawBody = await c.req.text();
  const signature = c.req.header("Stripe-Signature");
  if (!signature) return c.json({ error: "missing_signature" }, 400);

  const verified = await verifyStripeSignature(rawBody, signature, c.env.STRIPE_WEBHOOK_SECRET);
  if (!verified) return c.json({ error: "invalid_signature" }, 400);

  const event = JSON.parse(rawBody) as { type: string; data: { object: Record<string, unknown> } };

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as {
        customer: string;
        mode: string;
        payment_status: string;
        line_items?: { data: { price: { id: string } }[] };
        metadata?: Record<string, string>;
      };

      if (session.mode !== "payment" || session.payment_status !== "paid") break;

      // Verify this checkout was for the All Aboard price (Yap isolation).
      const lineItemsRes = await fetch(
        `https://api.stripe.com/v1/checkout/sessions/${(event.data.object as { id: string }).id}/line_items?limit=5`,
        { headers: { Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}` } },
      );
      if (!lineItemsRes.ok) break;
      const lineItems = (await lineItemsRes.json()) as { data: { price: { id: string } }[] };
      if (!lineItems.data.some((item) => item.price.id === c.env.STRIPE_PRICE_ID)) break;

      const user = await getUserByStripeCustomer(c.env.DB, session.customer);
      if (!user) break;

      await updatePlanByStripeCustomer(c.env.DB, session.customer, "pro", null, null);
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
