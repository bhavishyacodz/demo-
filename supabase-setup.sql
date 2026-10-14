-- Theme 005 database setup for existing Supabase project.
-- Safe additive migration: preserves existing registrations and the existing payment_status values.
alter table public.registrations
  add column if not exists contact_method text,
  add column if not exists contact_details text,
  add column if not exists privacy_consent_at timestamptz,
  add column if not exists work_status text not null default 'Unpaid',
  add column if not exists admin_notes text;

alter table public.registrations drop constraint if exists registrations_contact_method_check;
alter table public.registrations add constraint registrations_contact_method_check
  check (contact_method is null or contact_method in ('phone','instagram','whatsapp'));
alter table public.registrations drop constraint if exists registrations_work_status_check;
alter table public.registrations add constraint registrations_work_status_check
  check (work_status in ('Unpaid','Paid','Work in Progress','Awaiting User Response','Completed'));

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
drop policy if exists "Admins can see their own allowlist entry" on public.admin_users;
create policy "Admins can see their own allowlist entry" on public.admin_users
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.admin_users to authenticated;
revoke insert, update, delete on public.admin_users from anon, authenticated;

alter table public.registrations enable row level security;
drop policy if exists "Public can submit adult registrations" on public.registrations;
create policy "Public can submit adult registrations" on public.registrations
  for insert to anon with check (
    age_18_confirmed = true and consent_status = true
    and payment_status = 'pending' and match_status = 'unmatched'
    and payment_reference is null and work_status = 'Unpaid'
  );
drop policy if exists "Admins can view registrations" on public.registrations;
create policy "Admins can view registrations" on public.registrations
  for select to authenticated using (
    exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()))
  );
drop policy if exists "Admins can update registrations" on public.registrations;
create policy "Admins can update registrations" on public.registrations
  for update to authenticated using (
    exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()))
  );

-- Limit public inserts to registration fields only. Browser code cannot mark a record paid.
revoke insert, select, update, delete on public.registrations from anon;
grant insert (id, full_name, age_18_confirmed, city_area, interests, match_preferences,
              availability, consent_status, contact_method, contact_details, privacy_consent_at)
  on public.registrations to anon;
grant select on public.registrations to authenticated;
grant update (payment_status, payment_reference, match_status, work_status, admin_notes)
  on public.registrations to authenticated;

-- After creating the admin user in Supabase Auth, allowlist its auth.users UUID:
-- insert into public.admin_users(user_id) values ('REPLACE-WITH-ADMIN-AUTH-UUID');
