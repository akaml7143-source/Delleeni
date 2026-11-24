-- Delleeni Iraq data platform
-- Apply in the Supabase SQL editor. PostGIS stores coordinates as geographic data.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists postgis with schema extensions;

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'member' check (role in ('member','moderator','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.places (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  category text not null check (char_length(category) between 2 and 60),
  address text,
  neighborhood text,
  city text,
  governorate text not null,
  location extensions.geography(Point,4326) not null,
  entrance extensions.geography(Point,4326),
  entrance_note text,
  source text not null default 'community',
  status text not null default 'pending' check (status in ('pending','published','closed','rejected')),
  verified_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists places_location_gix on public.places using gist(location);
create index if not exists places_entrance_gix on public.places using gist(entrance);
create index if not exists places_search_idx on public.places (governorate, city, category, status);

create table if not exists public.road_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  kind text not null check (kind in ('closure','traffic','roadwork','hazard','other')),
  details text check (details is null or char_length(details) <= 240),
  location extensions.geography(Point,4326) not null,
  city text,
  governorate text not null,
  status text not null default 'pending' check (status in ('pending','verified','rejected','resolved')),
  expires_at timestamptz not null default (now() + interval '6 hours'),
  verified_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists road_reports_location_gix on public.road_reports using gist(location);
create index if not exists road_reports_active_idx on public.road_reports(status, expires_at);

create table if not exists public.transit_routes (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  mode text not null check (mode in ('bus','minibus','shared_taxi','other')),
  city text not null,
  governorate text not null,
  fare_min_iqd integer check (fare_min_iqd is null or fare_min_iqd >= 0),
  fare_max_iqd integer check (fare_max_iqd is null or fare_max_iqd >= fare_min_iqd),
  notes text,
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.transit_stops (
  id uuid primary key default extensions.gen_random_uuid(),
  route_id uuid not null references public.transit_routes(id) on delete cascade,
  name text not null,
  sequence_no integer not null check (sequence_no >= 0),
  location extensions.geography(Point,4326) not null,
  created_at timestamptz not null default now(),
  unique(route_id, sequence_no)
);
create index if not exists transit_stops_location_gix on public.transit_stops using gist(location);

create table if not exists public.building_models (
  id uuid primary key default extensions.gen_random_uuid(),
  name text,
  footprint extensions.geometry(Polygon,4326) not null,
  height_m numeric(7,2) check (height_m is null or height_m >= 0),
  levels integer check (levels is null or levels >= 0),
  source text not null default 'community',
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_at timestamptz not null default now()
);
create index if not exists building_models_footprint_gix on public.building_models using gist(footprint);

create table if not exists public.accessibility_features (
  id uuid primary key default extensions.gen_random_uuid(),
  kind text not null check (kind in ('ramp','step_free_entry','sidewalk','crossing','obstacle','accessible_toilet','other')),
  notes text,
  location extensions.geography(Point,4326) not null,
  verified boolean not null default false,
  status text not null default 'pending' check (status in ('pending','published','rejected')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists accessibility_location_gix on public.accessibility_features using gist(location);

create table if not exists public.community_contributions (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type text not null check (entity_type in ('place','road_report','transit_route','transit_stop','building','accessibility')),
  entity_id uuid,
  action text not null check (action in ('add','edit','close','correct','verify')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_delleeni_moderator()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.user_profiles
    where id = auth.uid() and role in ('moderator','admin')
  );
$$;

alter table public.user_profiles enable row level security;
alter table public.places enable row level security;
alter table public.road_reports enable row level security;
alter table public.transit_routes enable row level security;
alter table public.transit_stops enable row level security;
alter table public.building_models enable row level security;
alter table public.accessibility_features enable row level security;
alter table public.community_contributions enable row level security;


-- Create a member profile automatically after a successful signup.
create or replace function public.handle_new_delleeni_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'name'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_delleeni on auth.users;
create trigger on_auth_user_created_delleeni
after insert on auth.users
for each row execute function public.handle_new_delleeni_user();

create policy "profiles read own or moderators" on public.user_profiles
for select to authenticated using (id = auth.uid() or public.is_delleeni_moderator());
create or replace function public.prevent_profile_role_escalation()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is not null and new.role is distinct from old.role and not public.is_delleeni_moderator() then
    raise exception 'Only moderators can change account roles';
  end if;
  return new;
end;
$$;
drop trigger if exists protect_user_profile_role on public.user_profiles;
create trigger protect_user_profile_role
before update on public.user_profiles
for each row execute function public.prevent_profile_role_escalation();

create policy "profiles update own display" on public.user_profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy "published places are public" on public.places
for select to anon, authenticated using (status = 'published' or public.is_delleeni_moderator());
create policy "signed in users suggest places" on public.places
for insert to authenticated with check (created_by = auth.uid() and status = 'pending');
create policy "moderators manage places" on public.places
for update to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());


-- Keep road reports short-lived and limit repeated submissions from one account.
create or replace function public.guard_delleeni_road_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is null or new.created_by <> auth.uid() then
    raise exception 'A signed-in contributor is required';
  end if;
  if (select count(*) from public.road_reports r
      where r.created_by = new.created_by
        and r.created_at > now() - interval '30 minutes') >= 5 then
    raise exception 'Report submission limit reached; try again later';
  end if;
  new.created_at := now();
  new.expires_at := now() + interval '6 hours';
  new.status := 'pending';
  return new;
end;
$$;

drop trigger if exists guard_delleeni_road_report_insert on public.road_reports;
create trigger guard_delleeni_road_report_insert
before insert on public.road_reports
for each row execute function public.guard_delleeni_road_report();

create policy "active verified reports are public" on public.road_reports
for select to anon, authenticated using ((status = 'verified' and expires_at > now()) or public.is_delleeni_moderator() or created_by = auth.uid());
create policy "signed in users submit reports" on public.road_reports
for insert to authenticated with check (created_by = auth.uid() and status = 'pending');
create policy "moderators review reports" on public.road_reports
for update to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());

create policy "published routes are public" on public.transit_routes
for select to anon, authenticated using (status = 'published' or public.is_delleeni_moderator());
create policy "published stops are public" on public.transit_stops
for select to anon, authenticated using (
  exists (select 1 from public.transit_routes r where r.id = route_id and r.status = 'published')
  or public.is_delleeni_moderator()
);
create policy "moderators manage transit routes" on public.transit_routes
for all to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());
create policy "moderators manage transit stops" on public.transit_stops
for all to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());

create policy "published buildings are public" on public.building_models
for select to anon, authenticated using (status = 'published' or public.is_delleeni_moderator());
create policy "moderators manage buildings" on public.building_models
for all to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());

create policy "published accessibility is public" on public.accessibility_features
for select to anon, authenticated using (status = 'published' or public.is_delleeni_moderator());
create policy "signed in users suggest accessibility" on public.accessibility_features
for insert to authenticated with check (created_by = auth.uid() and status = 'pending');
create policy "moderators review accessibility" on public.accessibility_features
for update to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());

create policy "contributors read own or moderators" on public.community_contributions
for select to authenticated using (created_by = auth.uid() or public.is_delleeni_moderator());
create policy "users submit contributions" on public.community_contributions
for insert to authenticated with check (created_by = auth.uid() and status = 'pending');
create policy "moderators review contributions" on public.community_contributions
for update to authenticated using (public.is_delleeni_moderator()) with check (public.is_delleeni_moderator());

-- Nearby search helper. Coordinates are parameters supplied only after user action.
create or replace function public.nearby_places(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 5000,
  p_category text default null
)
returns table (
  id uuid, name text, category text, address text, city text, governorate text,
  latitude double precision, longitude double precision, distance_m double precision
)
language sql stable security invoker set search_path = ''
as $$
  select p.id, p.name, p.category, p.address, p.city, p.governorate,
    st_y(p.location::geometry), st_x(p.location::geometry),
    st_distance(p.location, st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography)
  from public.places p
  where p.status = 'published'
    and st_dwithin(p.location, st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography,
      greatest(100, least(coalesce(p_radius_m,5000), 20000)))
    and (p_category is null or p.category = p_category)
  order by p.location <-> st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography
  limit 200;
$$;



create or replace function public.nearby_road_reports(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 5000
)
returns table (
  id uuid, kind text, details text, city text, governorate text,
  latitude double precision, longitude double precision,
  created_at timestamptz, expires_at timestamptz, distance_m double precision
)
language sql stable security invoker set search_path = ''
as $$
  select r.id, r.kind, r.details, r.city, r.governorate,
    st_y(r.location::geometry), st_x(r.location::geometry),
    r.created_at, r.expires_at,
    st_distance(r.location, st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography)
  from public.road_reports r
  where r.status = 'verified'
    and r.expires_at > now()
    and st_dwithin(r.location,
      st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography,
      greatest(100, least(coalesce(p_radius_m,5000), 20000)))
  order by r.location <-> st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography
  limit 100;
$$;

create or replace function public.nearby_accessibility_features(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 3000
)
returns table (
  id uuid, kind text, notes text, latitude double precision,
  longitude double precision, verified boolean, distance_m double precision
)
language sql stable security invoker set search_path = ''
as $$
  select a.id, a.kind, a.notes,
    st_y(a.location::geometry), st_x(a.location::geometry),
    a.verified,
    st_distance(a.location, st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography)
  from public.accessibility_features a
  where a.status = 'published' and a.verified
    and st_dwithin(a.location,
      st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography,
      greatest(100, least(coalesce(p_radius_m,3000), 10000)))
  order by a.location <-> st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography
  limit 100;
$$;

-- Explicit PostgREST grants: RLS still controls which rows and writes are allowed.
grant usage on schema public, extensions to anon, authenticated;
grant select on public.places to anon, authenticated;
grant insert, select, update on public.places to authenticated;
grant select on public.road_reports to anon, authenticated;
grant insert, update on public.road_reports to authenticated;
grant select on public.transit_routes, public.transit_stops to anon, authenticated;
grant select on public.building_models to anon, authenticated;
grant select on public.accessibility_features to anon, authenticated;
grant insert, update on public.accessibility_features to authenticated;
grant select, insert, update on public.community_contributions to authenticated;
grant select, update on public.user_profiles to authenticated;
grant execute on function public.nearby_places(double precision, double precision, integer, text),
  public.nearby_road_reports(double precision, double precision, integer),
  public.nearby_accessibility_features(double precision, double precision, integer)
  to anon, authenticated;

-- Do not store continuous user-location histories. Keep reports coarse and time-limited.


-- Atomic moderation actions. Only authenticated moderators may execute these
-- functions; the caller cannot choose reviewer_id or bypass the role table.
alter table public.community_contributions
  add column if not exists reviewer_notes text;
alter table public.places
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;
alter table public.road_reports
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;

create index if not exists community_contributions_pending_idx
  on public.community_contributions(status, created_at);

create index if not exists road_reports_pending_idx
  on public.road_reports(status, created_at);

create or replace function public.review_delleeni_place(
  p_place_id uuid,
  p_decision text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_delleeni_moderator(), false) then
    raise exception 'Moderator permission required';
  end if;
  if p_decision is null or p_decision not in ('published', 'rejected', 'closed') then
    raise exception 'Unsupported place decision';
  end if;
  update public.places
  set status = p_decision,
      verified_at = case when p_decision = 'published' then pg_catalog.now() else verified_at end,
      reviewed_by = auth.uid(),
      reviewed_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = p_place_id and status = 'pending';
  if found then
    update public.community_contributions
    set status = case when p_decision = 'published' then 'approved' else 'rejected' end,
        reviewer_id = auth.uid(),
        reviewed_at = pg_catalog.now()
    where entity_type = 'place'
      and entity_id = p_place_id
      and action = 'add'
      and status = 'pending';
    return true;
  end if;
  return false;
end;
$$;

create or replace function public.review_delleeni_road_report(
  p_report_id uuid,
  p_decision text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.is_delleeni_moderator(), false) then
    raise exception 'Moderator permission required';
  end if;
  if p_decision is null or p_decision not in ('verified', 'rejected') then
    raise exception 'Unsupported road report decision';
  end if;
  update public.road_reports
  set status = p_decision,
      verified_at = case when p_decision = 'verified' then pg_catalog.now() else verified_at end,
      reviewed_by = auth.uid(),
      reviewed_at = pg_catalog.now()
  where id = p_report_id and status = 'pending' and expires_at > pg_catalog.now();
  return found;
end;
$$;

create or replace function public.review_delleeni_contribution(
  p_contribution_id uuid,
  p_decision text,
  p_reviewer_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.community_contributions%rowtype;
begin
  if not coalesce(public.is_delleeni_moderator(), false) then
    raise exception 'Moderator permission required';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'Unsupported contribution decision';
  end if;
  if p_reviewer_notes is not null and pg_catalog.char_length(p_reviewer_notes) > 500 then
    raise exception 'Reviewer notes are too long';
  end if;

  select * into v
  from public.community_contributions
  where id = p_contribution_id
  for update;

  if not found or v.status <> 'pending' then
    return false;
  end if;

  if p_decision = 'approved' then
    if v.entity_type = 'place' and v.entity_id is not null then
      if v.action = 'add' then
        update public.places
        set status = 'published', verified_at = pg_catalog.now(), updated_at = pg_catalog.now()
        where id = v.entity_id and status = 'pending';
      elsif v.action = 'close' then
        update public.places
        set status = 'closed', updated_at = pg_catalog.now()
        where id = v.entity_id and status = 'published';
      elsif v.action in ('edit', 'correct') then
        update public.places
        set name = coalesce(nullif(v.payload ->> 'name', ''), name),
            category = coalesce(nullif(v.payload ->> 'category', ''), category),
            address = case when v.payload ? 'address' then nullif(v.payload ->> 'address', '') else address end,
            neighborhood = case when v.payload ? 'neighborhood' then nullif(v.payload ->> 'neighborhood', '') else neighborhood end,
            city = case when v.payload ? 'city' then nullif(v.payload ->> 'city', '') else city end,
            governorate = coalesce(nullif(v.payload ->> 'governorate', ''), governorate),
            updated_at = pg_catalog.now()
        where id = v.entity_id and status = 'published';
      else
        raise exception 'Unsupported place contribution action';
      end if;
      if not found then
        raise exception 'Place not found or no longer eligible for this action';
      end if;
    elsif v.entity_type = 'accessibility' and v.entity_id is not null and v.action = 'add' then
      update public.accessibility_features
      set status = 'published', verified = true
      where id = v.entity_id and status = 'pending';
      if not found then raise exception 'Accessibility feature not found or already reviewed'; end if;
    elsif v.entity_type = 'transit_route' and v.entity_id is not null and v.action = 'add' then
      update public.transit_routes
      set status = 'published'
      where id = v.entity_id and status = 'pending';
      if not found then raise exception 'Transit route not found or already reviewed'; end if;
    elsif v.entity_type = 'building' and v.entity_id is not null and v.action = 'add' then
      update public.building_models
      set status = 'published'
      where id = v.entity_id and status = 'pending';
      if not found then raise exception 'Building model not found or already reviewed'; end if;
    else
      raise exception 'Unsupported contribution target or action';
    end if;
  elsif v.entity_type = 'place' and v.action = 'add' and v.entity_id is not null then
    update public.places
    set status = 'rejected', updated_at = pg_catalog.now()
    where id = v.entity_id and status = 'pending';
  elsif v.entity_type = 'accessibility' and v.action = 'add' and v.entity_id is not null then
    update public.accessibility_features
    set status = 'rejected'
    where id = v.entity_id and status = 'pending';
  elsif v.entity_type = 'transit_route' and v.action = 'add' and v.entity_id is not null then
    update public.transit_routes
    set status = 'rejected'
    where id = v.entity_id and status = 'pending';
  elsif v.entity_type = 'building' and v.action = 'add' and v.entity_id is not null then
    update public.building_models
    set status = 'rejected'
    where id = v.entity_id and status = 'pending';
  end if;

  update public.community_contributions
  set status = p_decision,
      reviewer_id = auth.uid(),
      reviewed_at = pg_catalog.now(),
      reviewer_notes = p_reviewer_notes
  where id = v.id and status = 'pending';
  return found;
end;
$$;

-- Remove default PUBLIC execution from privileged moderation functions.
revoke all on function public.review_delleeni_place(uuid, text) from public, anon;
revoke all on function public.review_delleeni_road_report(uuid, text) from public, anon;
revoke all on function public.review_delleeni_contribution(uuid, text, text) from public, anon;
grant execute on function public.review_delleeni_place(uuid, text) to authenticated;
grant execute on function public.review_delleeni_road_report(uuid, text) to authenticated;
grant execute on function public.review_delleeni_contribution(uuid, text, text) to authenticated;

-- Members may edit only their display name, never their role or account id.
revoke update on public.user_profiles from authenticated;
grant update (display_name) on public.user_profiles to authenticated;
