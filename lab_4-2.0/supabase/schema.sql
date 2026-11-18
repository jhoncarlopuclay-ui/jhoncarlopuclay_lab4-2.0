-- Commonroom | Laboratory 4, Section B
-- Run in the Supabase SQL editor for the shared, authenticated deployment.
create extension if not exists btree_gist;

create type public.app_role as enum ('administrator','facility_staff','requester');
create type public.facility_status as enum ('active','maintenance','inactive');
create type public.reservation_status as enum ('pending','approved','rejected','scheduled','in_use','completed','cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'requester',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  capacity integer not null check (capacity > 0),
  status public.facility_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete restrict,
  requester_id uuid not null references public.profiles(id) on delete restrict,
  purpose text not null check (length(trim(purpose)) between 1 and 500),
  start_at timestamptz not null,
  end_at timestamptz not null,
  status public.reservation_status not null default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservation_time_order check (start_at < end_at),
  -- Protect active time slots even against simultaneous approval transactions.
  constraint no_overlapping_reserved_slots exclude using gist (
    facility_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  ) where (status in ('approved','scheduled','in_use'))
);
create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete restrict,
  reported_by uuid not null references public.profiles(id) on delete restrict,
  description text not null check (length(trim(description)) > 0),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index reservations_requester_idx on public.reservations(requester_id, created_at desc);
create index reservations_facility_time_idx on public.reservations(facility_id, start_at, end_at);
create index audit_logs_created_idx on public.audit_logs(created_at desc);

create function public.current_role() returns public.app_role
language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and is_active $$;

-- Validate each insert/update. The exclusion constraint above is the final
-- concurrent-safe guard; this trigger provides useful facility and transition checks.
create function public.guard_reservation() returns trigger
language plpgsql security definer set search_path = public
as $$
declare f_status public.facility_status;
begin
  select status into f_status from public.facilities where id = new.facility_id;
  if f_status is distinct from 'active' then raise exception 'Facility is not active'; end if;
  if tg_op = 'INSERT' then
    if public.current_role() not in ('requester','administrator') then raise exception 'Only requesters may submit reservations'; end if;
    new.status := 'pending';
    if public.current_role() = 'requester' then new.requester_id := auth.uid(); end if;
  else
    if old.status = 'completed' then raise exception 'Completed reservations cannot be edited'; end if;
    if new.requester_id <> old.requester_id or new.facility_id <> old.facility_id and new.status <> 'pending' then
      raise exception 'Reservation ownership and approved facility are immutable';
    end if;
    if new.status is distinct from old.status then
      if public.current_role() = 'administrator' then
        if old.status <> 'pending' or new.status not in ('approved','rejected') then raise exception 'Invalid administrator transition'; end if;
        if new.status = 'approved' then new.status := 'scheduled'; end if;
        new.reviewed_by := auth.uid(); new.reviewed_at := now();
      elsif public.current_role() = 'facility_staff' then
        if old.status not in ('scheduled','approved','in_use') or new.status not in ('in_use','completed') then raise exception 'Invalid staff transition'; end if;
      elsif public.current_role() = 'requester' then
        if old.requester_id <> auth.uid() or old.status <> 'pending' or new.status <> 'cancelled' then raise exception 'Requesters may cancel only their own pending requests'; end if;
      else raise exception 'Not authorized to change reservation status'; end if;
    elsif public.current_role() = 'requester' then
      if old.requester_id <> auth.uid() or old.status <> 'pending' then raise exception 'Requesters may edit only their own pending requests'; end if;
    elsif public.current_role() not in ('administrator','facility_staff') then raise exception 'Not authorized';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger reservation_guard before insert or update on public.reservations for each row execute function public.guard_reservation();

create function public.write_audit_log() returns trigger
language plpgsql security definer set search_path = public
as $$
declare act text; ent text; eid text; det jsonb;
begin
  ent := tg_table_name;
  if tg_op = 'DELETE' then act := lower(ent)||'.deleted'; eid := old.id::text; det := to_jsonb(old); else
    eid := new.id::text;
    if tg_op = 'INSERT' then act := lower(ent)||'.created'; det := to_jsonb(new);
    else act := lower(ent)||'.updated'; det := jsonb_build_object('before',to_jsonb(old),'after',to_jsonb(new)); end if;
  end if;
  if ent = 'reservations' and tg_op = 'INSERT' then act := 'reservation.submitted'; end if;
  if ent = 'reservations' and tg_op = 'UPDATE' and old.status is distinct from new.status then act := 'reservation.'||new.status::text; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),act,ent,eid,det);
  return coalesce(new,old);
end $$;
create trigger reservation_audit after insert or update or delete on public.reservations for each row execute function public.write_audit_log();
create trigger facility_audit after insert or update or delete on public.facilities for each row execute function public.write_audit_log();
create trigger service_request_audit after insert or update or delete on public.service_requests for each row execute function public.write_audit_log();

alter table public.profiles enable row level security;
alter table public.facilities enable row level security;
alter table public.reservations enable row level security;
alter table public.service_requests enable row level security;
alter table public.audit_logs enable row level security;

create policy "active users read profiles" on public.profiles for select to authenticated using (is_active and (id=auth.uid() or public.current_role()='administrator'));
create policy "administrators manage profiles" on public.profiles for all to authenticated using (public.current_role()='administrator') with check (public.current_role()='administrator');
create policy "authenticated users read facilities" on public.facilities for select to authenticated using (true);
create policy "administrators manage facilities" on public.facilities for all to authenticated using (public.current_role()='administrator') with check (public.current_role()='administrator');
create policy "read own or operational reservations" on public.reservations for select to authenticated using (requester_id=auth.uid() or public.current_role() in ('administrator','facility_staff'));
create policy "requesters submit own reservations" on public.reservations for insert to authenticated with check (requester_id=auth.uid() and public.current_role()='requester');
create policy "requesters update own pending reservations" on public.reservations for update to authenticated using (requester_id=auth.uid() and status='pending' and public.current_role()='requester') with check (requester_id=auth.uid() and status in ('pending','cancelled'));
create policy "administrators review reservations" on public.reservations for update to authenticated using (public.current_role()='administrator') with check (public.current_role()='administrator');
create policy "staff update usage status" on public.reservations for update to authenticated using (public.current_role()='facility_staff') with check (public.current_role()='facility_staff');
create policy "staff manage service requests" on public.service_requests for all to authenticated using (public.current_role()='facility_staff') with check (public.current_role()='facility_staff');
create policy "administrators read audit logs" on public.audit_logs for select to authenticated using (public.current_role()='administrator');
create policy "no direct audit writes" on public.audit_logs for all to authenticated using (false) with check (false);

insert into public.facilities(name,description,capacity,status) values
('Willow meeting room','A bright room for small team sessions.',8,'active'),
('Juniper conference hall','Flexible presentation and planning space.',24,'active'),
('The Sunroom','A calm creative space with natural light.',12,'active'),
('Studio 03','Workshop space temporarily under maintenance.',10,'maintenance');
