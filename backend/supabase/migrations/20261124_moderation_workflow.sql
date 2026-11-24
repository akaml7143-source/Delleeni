-- Delleeni moderator workflow migration
-- Apply this file to an existing project; do not rerun schema.sql (policies are created there).

-- Atomic moderation actions. Only authenticated moderators may execute these
-- functions; the caller cannot choose reviewer_id or bypass the role table.
alter table public.community_contributions
  add column if not exists reviewer_notes text;

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
      verified_at = case when p_decision = 'verified' then pg_catalog.now() else verified_at end
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
