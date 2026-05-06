# Fix: Stripe Webhook Isolation for Yap

## Background

Yap and All Aboard share the same Stripe account. Stripe sends ALL subscription
events to ALL registered webhook endpoints, regardless of which product the
subscription belongs to. Without filtering, an active All Aboard subscription
can grant pro access in Yap (and vice versa).

All Aboard was fixed for this — Yap needs the same fix applied.

## What to change

Find the Stripe webhook handler (the POST route that handles `Stripe-Signature`
requests). Look for the `customer.subscription.created/updated/deleted` cases.

Add a price ID check using `items.data` on the subscription object before
updating the user's plan. The check should compare each item's `price.id`
against your `STRIPE_PRICE_ID` environment variable.

**Before:**
```ts
case "customer.subscription.created":
case "customer.subscription.updated": {
  const sub = event.data.object as { id: string; customer: string; status: string; trial_end: number | null };
  const plan = sub.status === "active" || sub.status === "trialing" ? "pro" : "free";
  await updatePlan(sub.customer, plan, sub.id);
  break;
}
case "customer.subscription.deleted": {
  const sub = event.data.object as { customer: string };
  await updatePlan(sub.customer, "free", null);
  break;
}
```

**After:**
```ts
case "customer.subscription.created":
case "customer.subscription.updated": {
  const sub = event.data.object as { id: string; customer: string; status: string; trial_end: number | null; items: { data: { price: { id: string } }[] } };
  if (!sub.items.data.some((item) => item.price.id === env.STRIPE_PRICE_ID)) break;
  const plan = sub.status === "active" || sub.status === "trialing" ? "pro" : "free";
  await updatePlan(sub.customer, plan, sub.id);
  break;
}
case "customer.subscription.deleted": {
  const sub = event.data.object as { customer: string; items: { data: { price: { id: string } }[] } };
  if (!sub.items.data.some((item) => item.price.id === env.STRIPE_PRICE_ID)) break;
  await updatePlan(sub.customer, "free", null);
  break;
}
```

Adapt the field names (`env`, `updatePlan`, etc.) to match Yap's codebase.

## After applying the fix

Check whether any Yap users were incorrectly granted pro access via an
All Aboard subscription. To find them: query your DB for users with
`plan = 'pro'` whose `stripe_subscription_id` belongs to an All Aboard
subscription (i.e. not a Yap price ID). Reset those users to `plan = 'free'`.
