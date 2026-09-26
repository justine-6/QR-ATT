-- ============================================================================
-- QR Attendance — Supabase schema (Phase 3)
-- Safe to re-run: every statement below is idempotent.
-- Run this file in the Supabase SQL Editor (see instructions/03-database-design.md)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- TABLE 1: profiles — who are the users?
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  full_name  text,
  role       text not null default 'student' check (role in ('student', 'teacher')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- TABLE 2: events — what is the event?
-- NOTE: start_time / end_time are used instead of start / end because
--       start and end are reserved words in PostgreSQL.
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  event_code  text not null unique,
  title       text not null,
  start_time  timestamptz,
  end_time    timestamptz,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- TABLE 3: attendance — who scanned what?
-- unique (student_id, event_id) is the anti-double-scan rule.
-- ---------------------------------------------------------------------------
create table if not exists public.attendance (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references auth.users (id) on delete cascade,
  event_id    uuid not null references public.events (id) on delete cascade,
  scanned_at  timestamptz not null default now(),
  unique (student_id, event_id)
);

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY — enabled on every table
-- ---------------------------------------------------------------------------
alter table public.profiles   enable row level security;
alter table public.events     enable row level security;
alter table public.attendance enable row level security;

-- ---------------------------------------------------------------------------
-- profiles policies
-- ---------------------------------------------------------------------------
drop policy if exists "Profiles are viewable by owner" on public.profiles;
create policy "Profiles are viewable by owner"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "Teachers can view profiles of their attendees" on public.profiles;
create policy "Teachers can view profiles of their attendees"
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1
      from public.attendance a
      join public.events e on e.id = a.event_id
      where a.student_id = profiles.id
        and e.created_by = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- events policies
-- ---------------------------------------------------------------------------
drop policy if exists "Events are readable by any authenticated user" on public.events;
create policy "Events are readable by any authenticated user"
  on public.events for select
  to authenticated
  using (true);

drop policy if exists "Users can insert events" on public.events;
create policy "Users can insert events"
  on public.events for insert
  to authenticated
  with check (true);

drop policy if exists "Users can update their own events" on public.events;
create policy "Users can update their own events"
  on public.events for update
  to authenticated
  using (auth.uid() = created_by)
  with check (auth.uid() = created_by);

-- ---------------------------------------------------------------------------
-- attendance policies
-- ---------------------------------------------------------------------------
drop policy if exists "Students can view their own attendance" on public.attendance;
create policy "Students can view their own attendance"
  on public.attendance for select
  to authenticated
  using (auth.uid() = student_id);

drop policy if exists "Students can insert their own attendance" on public.attendance;
create policy "Students can insert their own attendance"
  on public.attendance for insert
  to authenticated
  with check (auth.uid() = student_id);

drop policy if exists "Teachers can view attendance for their events" on public.attendance;
create policy "Teachers can view attendance for their events"
  on public.attendance for select
  to authenticated
  using (
    exists (
      select 1 from public.events e
      where e.id = attendance.event_id
        and e.created_by = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- TRIGGER — automatically create a profile row on signup
-- Reads full_name / role from the signup metadata (options.data) so the role
-- the user picked on the Sign Up screen is written atomically — even when
-- email confirmation is on and the client has no session yet.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    nullif(new.raw_user_meta_data->>'full_name', ''),
    case when new.raw_user_meta_data->>'role' = 'teacher'
         then 'teacher'
         else 'student'
    end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
