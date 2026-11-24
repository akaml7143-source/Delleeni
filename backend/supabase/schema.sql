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
returns boolean language sql stable security definer set search_path = public
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
set search_path = public
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
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_delleeni_moderator() then
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
set search_path = public
as $
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
$;

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
language sql stable security invoker set search_path = public, extensions
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
language sql stable security invoker set search_path = public, extensions
as $
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
$;

create or replace function public.nearby_accessibility_features(
  p_lat double precision,
  p_lon double precision,
  p_radius_m integer default 3000
)
returns table (
  id uuid, kind text, notes text, latitude double precision,
  longitude double precision, verified boolean, distance_m double precision
)
language sql stable security invoker set search_path = public, extensions
as $
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
$;

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
