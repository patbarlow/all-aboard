export interface User {
  id: string;
  email: string;
  plan: "free" | "pro";
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface PublicUser {
  id: string;
  email: string;
  plan: "free" | "pro";
}

export function publicUser(u: User): PublicUser {
  return { id: u.id, email: u.email, plan: u.plan };
}

export async function upsertUserByEmail(db: D1Database, email: string): Promise<User> {
  const existing = await db
    .prepare("SELECT * FROM users WHERE email = ?")
    .bind(email)
    .first<User>();

  if (existing) return existing;

  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO users (id, email, plan, created_at, updated_at)
       VALUES (?, ?, 'free', ?, ?)`,
    )
    .bind(id, email, now, now)
    .run();

  return { id, email, plan: "free", stripe_customer_id: null, stripe_subscription_id: null, created_at: now, updated_at: now };
}

export async function getUser(db: D1Database, id: string): Promise<User | null> {
  return db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<User>();
}

export async function setStripeCustomerId(db: D1Database, userId: string, customerId: string): Promise<void> {
  await db
    .prepare("UPDATE users SET stripe_customer_id = ?, updated_at = ? WHERE id = ?")
    .bind(customerId, new Date().toISOString(), userId)
    .run();
}

export async function updatePlanByStripeCustomer(
  db: D1Database,
  customerId: string,
  plan: "free" | "pro",
  subscriptionId: string | null,
): Promise<void> {
  await db
    .prepare(
      `UPDATE users SET plan = ?, stripe_subscription_id = ?, updated_at = ?
       WHERE stripe_customer_id = ?`,
    )
    .bind(plan, subscriptionId, new Date().toISOString(), customerId)
    .run();
}
