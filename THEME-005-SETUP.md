# Theme 005 — Crimson Romance setup

## Files
- `theme-005.html`: public landing page, 18+ registration, ₹99 checkout UI.
- `admin.html`: authenticated admin tracker.
- `supabase-setup.sql`: additive schema, RLS, grants, and RPC execution permissions.
- `supabase/functions/create-order/index.ts`: creates a fixed ₹99 Razorpay order server-side.
- `supabase/functions/verify-payment/index.ts`: validates checkout signature and confirms the Razorpay payment is captured for ₹99 INR before marking the registration paid.

## Current state
The SQL setup has been applied to Supabase project `vpuvcgtmwwherjbzenzq`, and the two Edge Functions are deployed. Razorpay checkout will remain unavailable until provider credentials are configured as Edge Function secrets. No payment secrets belong in GitHub or browser code.

## Finish setup before accepting real payments
1. In the Razorpay dashboard, complete the required account verification and use test credentials first. The account owner must meet Razorpay's eligibility and KYC requirements.
2. In Supabase Dashboard → Edge Functions → Secrets, add:
   - `RAZORPAY_KEY_ID`
   - `RAZORPAY_KEY_SECRET`
   Use test credentials first; switch to live credentials only after end-to-end tests. Never put the secret in HTML, GitHub, or chat.
3. Create an admin account in Supabase Authentication (email/password). Copy that user's Auth UUID.
4. In the Supabase SQL editor, allowlist that UUID:
   ```sql
   insert into public.admin_users(user_id)
   values ('REPLACE-WITH-ADMIN-AUTH-UUID');
   ```
   Only UUIDs in `public.admin_users` can read or update customer records. Do not add public signup to `admin.html`.
5. Visit `https://bhavishyacodz.github.io/demo-/theme-005.html` and test registration. Admin is at `https://bhavishyacodz.github.io/demo-/admin.html`.
6. Test a successful test payment, a cancelled checkout, a failed payment, and an invalid signature. Confirm only a captured ₹99 INR payment changes `payment_status` to `paid` and `work_status` to `Paid`.
7. Before launch, publish a real privacy notice with operator contact details, a data retention/deletion process, and the final service/refund terms.

## Important security notes
- Public registration is submitted through the existing `submit_registration(jsonb)` RPC, which validates the date of birth and consent and stores the calculated age—not the birth date.
- Public users cannot read registration rows or set payment/work status directly.
- Payment status is updated by the server-side verification function, not by browser claims.
- Admin access is protected by Supabase Auth plus the database allowlist and RLS.
- The public registration RPC is intentionally callable by the anonymous role; its input validation is essential. Review Supabase Security Advisor warnings before launch.
- The site currently aims to contact a paying user within 24 hours using their selected method; this is a manual team commitment, not an automated guarantee.
