# Theme 005 — Crimson Romance setup

## Files
- `theme-005.html`: public landing page, adults-only registration, ₹99 manual UPI payment instructions, and payment screenshot upload.
- `admin.html`: authenticated admin tracker with private signed links for payment screenshots.
- `supabase-setup.sql`: database fields, admin access, private screenshot bucket policies, and RPC permissions.
- `supabase/functions/create-order/index.ts` and `verify-payment/index.ts`: older Razorpay functions still deployed but no longer used by the Theme 005 page.

## Manual ₹99 UPI flow
1. Visitor submits the registration form. Registration is saved as pending/unpaid.
2. The page displays a clearly marked **non-scannable placeholder image** where the QR will go.
3. After the owner replaces the placeholder with their actual UPI QR, visitors can pay ₹99 through their UPI app.
4. Visitor uploads a JPG, PNG, or WebP screenshot (maximum 5 MB). The image is stored in a private Supabase Storage bucket and linked to the registration.
5. In the admin dashboard, an allowlisted admin signs in and uses **View screenshot** to inspect the proof. The admin must check the transaction in the UPI/bank app before marking payment as paid.

**Do not accept payments while the placeholder QR is still displayed.** It is decorative and cannot receive money. Replace the inline SVG inside the `qr-placeholder` element in `theme-005.html` with the owner's actual QR image when provided. Do not put a QR for someone else's account on the site.

## Supabase setup
The current project has the `payment_screenshot_path` column and private `payment-proofs` bucket. If setting this up in a different project, run `supabase-setup.sql` in the Supabase SQL editor after reviewing it.

1. Create an admin account in Supabase Authentication (email/password). Copy that user's Auth UUID.
2. In the Supabase SQL editor, allowlist that UUID:
   ```sql
   insert into public.admin_users(user_id)
   values ('REPLACE-WITH-ADMIN-AUTH-UUID');
   ```
3. Visit the website at https://bhavishyacodz.github.io/demo-/theme-005.html and the admin dashboard at https://bhavishyacodz.github.io/demo-/admin.html.
4. Test with a registration and a sample screenshot before launch. Confirm the screenshot is private and only an allowlisted admin can view it.
5. Before launch, publish a real privacy notice with operator contact details, a data retention/deletion process, and final service/refund terms.

## Important security notes
- Public registration is submitted through `submit_registration(jsonb)`, which validates date of birth and consent and stores the calculated age—not the birth date.
- Public users cannot read registration rows or set payment/work status directly.
- Screenshot upload is limited to image/jpeg, image/png, or image/webp files up to 5 MB; files are in a private bucket.
- A screenshot is not proof that a payment cleared. Verify the transaction in the UPI/bank app before changing payment status.
- Admin access is protected by Supabase Auth plus the database allowlist and RLS.
- The registration and screenshot-attachment RPCs are callable by the anonymous role by design; review Supabase Security Advisor warnings and rate-limit/monitor before public launch.
- The site's 18+ restriction must be retained. Since the owner is a minor, a trusted adult should help with payment account ownership, applicable terms, and privacy obligations.
