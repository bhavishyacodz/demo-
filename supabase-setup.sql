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
revoke insert, select, update, delete on public.registrations from anon, authenticated;
revoke insert (id, full_name, age, age_18_confirmed, city_area, interests, match_preferences,
              availability, consent_status, contact_method, contact_details, privacy_consent_at)
  on public.registrations from anon;
grant select on public.registrations to authenticated;
grant update (payment_status, payment_reference, match_status, work_status, admin_notes)
  on public.registrations to authenticated;

-- After creating the admin user in Supabase Auth, allowlist its auth.users UUID:
-- insert into public.admin_users(user_id) values ('REPLACE-WITH-ADMIN-AUTH-UUID');

-- Keep the public registration RPC available only to unauthenticated visitors;
-- it validates DOB/18+, consent, interests, and required contact details before inserting.
revoke execute on function public.submit_registration(jsonb) from public, authenticated;
grant execute on function public.submit_registration(jsonb) to anon;


-- Private payment screenshot storage for the manual ₹99 UPI flow.
alter table public.registrations
  add column if not exists payment_screenshot_path text;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to anon, authenticated;

create or replace function private.registration_is_pending(p_registration_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.registrations r
    where r.id = p_registration_id and r.payment_status = 'pending'
  );
$$;
revoke all on function private.registration_is_pending(uuid) from public;
grant execute on function private.registration_is_pending(uuid) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Visitors can upload pending registration payment proof" on storage.objects;
create policy "Visitors can upload pending registration payment proof"
on storage.objects for insert to anon
with check (
  bucket_id = 'payment-proofs'
  and case
    when (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then private.registration_is_pending(((storage.foldername(name))[1])::uuid)
    else false
  end
);

drop policy if exists "Admins can view payment proof files" on storage.objects;
create policy "Admins can view payment proof files"
on storage.objects for select to authenticated
using (
  bucket_id = 'payment-proofs'
  and exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()))
);

create or replace function public.attach_payment_proof(p_registration_id uuid, p_object_path text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_object_path is null
     or left(p_object_path, length(p_registration_id::text) + 1) <> (p_registration_id::text || '/')
     or length(p_object_path) > 300
     or not exists (
       select 1 from storage.objects o
       where o.bucket_id = 'payment-proofs' and o.name = p_object_path
     ) then
    raise exception 'Invalid payment proof upload';
  end if;

  update public.registrations
  set payment_screenshot_path = p_object_path
  where id = p_registration_id and payment_status = 'pending';

  if not found then
    raise exception 'Registration not found or payment is no longer pending';
  end if;
  return true;
end;
$$;
revoke all on function public.attach_payment_proof(uuid, text) from public, authenticated;
grant execute on function public.attach_payment_proof(uuid, text) to anon;
