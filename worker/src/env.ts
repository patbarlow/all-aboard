export interface Env {
  DB: D1Database;
  TRANSPORT_NSW_API_KEY: string;
  SESSION_SECRET: string;
  RESEND_API_KEY: string;
  RESEND_FROM?: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  STRIPE_PRICE_ID: string;
}
