-- Project Genesis: church groups and the community (Phase 4).
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing and never drops or deletes
-- anything.
--
-- Design
--   * Everything needs a signed-in account. People choose a display name
--     (profiles); it's copied onto what they post by the database, so nobody
--     can post under someone else's name.
--   * Groups are private: only members see a group and what's in it. People
--     join with an invite code through join_group(); leaders manage members.
--   * The community (prayer wall and reflections) is public to signed-in
--     people. Posting needs the community guidelines accepted. Text is checked
--     against blocked_terms, posting is rate limited, three reports hide a post
--     until you review it, and community_bans stops someone posting.
--   * App Store guideline 1.2 asks for exactly this: a filter, reporting,
--     blocking (user_blocks) and a way to act on reports (moderation_queue).
--   * Two switches in feature_flags: 'groups' (on) and 'community' (off until
--     you're ready to moderate). The database enforces them too.
--   * Verse references are VerseIDs (book*1000000 + chapter*1000 + verse);
--     Scripture text is never stored here.

-- Switches ------------------------------------------------------------------

insert into public.feature_flags (key, enabled, description)
values ('groups', true, 'Church groups: shared reading plans, prayer requests, discussion and announcements.')
on conflict (key) do nothing;

insert into public.feature_flags (key, enabled, description)
values ('community', false, 'Public community: prayer wall and reflections. Turn on once you are ready to review reports.')
on conflict (key) do nothing;

create or replace function public.genesis_feature_on(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select enabled from public.feature_flags where key = p_key), false);
$$;

-- Profiles ------------------------------------------------------------------

create table if not exists public.profiles (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
  community_terms_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Moderation tables (written by you in the dashboard, or by the database) ----

create table if not exists public.blocked_terms (
  term text primary key check (term ~ '^[a-z0-9]+$')
);

create table if not exists public.community_bans (
  user_id uuid primary key references auth.users (id) on delete cascade,
  reason text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.user_blocks (
  blocker uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blocked uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content_type text not null check (content_type in ('community_post', 'community_comment', 'group_prayer', 'group_post', 'group_announcement')),
  content_id uuid not null,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (reporter, content_type, content_id)
);

-- Groups --------------------------------------------------------------------

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  description text not null default '' check (char_length(description) <= 500),
  invite_code text not null unique,
  -- The shared reading plan: a built-in plan id, or a custom plan's books and days.
  plan_id text,
  plan_title text,
  plan_books integer[],
  plan_days integer check (plan_days is null or plan_days between 1 and 730),
  plan_start date,
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('leader', 'member')),
  display_name text not null,
  -- Push notifications for this group's announcements.
  notifications boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- For databases created before the column existed.
alter table public.group_members add column if not exists notifications boolean not null default true;

create index if not exists group_members_user_idx on public.group_members (user_id);

create table if not exists public.group_progress (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day integer not null check (day between 1 and 730),
  completed_at timestamptz not null default now(),
  primary key (group_id, user_id, day)
);

create table if not exists public.group_prayers (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null default '',
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  prayed_count integer not null default 0,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  deleted_at timestamptz
);

create index if not exists group_prayers_group_idx on public.group_prayers (group_id, created_at desc);

create table if not exists public.group_prayer_marks (
  prayer_id uuid not null references public.group_prayers (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (prayer_id, user_id)
);

-- Discussion: one thread per plan day (day is null for general discussion).
create table if not exists public.group_posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null default '',
  day integer check (day is null or day between 1 and 730),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists group_posts_group_idx on public.group_posts (group_id, day, created_at);

create table if not exists public.group_announcements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null default '',
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null default '' check (char_length(body) <= 2000),
  event_at timestamptz,
  created_at timestamptz not null default now(),
  notified_at timestamptz,
  deleted_at timestamptz
);

create index if not exists group_announcements_group_idx on public.group_announcements (group_id, created_at desc);

-- Community -----------------------------------------------------------------

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('prayer', 'reflection')),
  body text not null check (char_length(btrim(body)) between 1 and 1500),
  start_verse integer,
  end_verse integer,
  display_name text not null default '',
  is_anonymous boolean not null default false,
  reaction_count integer not null default 0,
  comment_count integer not null default 0,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  hidden_at timestamptz
);

create index if not exists community_posts_feed_idx on public.community_posts (kind, created_at desc);

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null default '',
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  hidden_at timestamptz
);

create index if not exists community_comments_post_idx on public.community_comments (post_id, created_at);

-- "I prayed" on a prayer, "Amen" on a reflection.
create table if not exists public.community_reactions (
  post_id uuid not null references public.community_posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- Push notifications for group announcements.
create table if not exists public.push_tokens (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  token text not null check (token ~ '^[0-9a-f]{32,200}$'),
  environment text not null default 'production' check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- Row-level security --------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.blocked_terms enable row level security;
alter table public.community_bans enable row level security;
alter table public.user_blocks enable row level security;
alter table public.content_reports enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_progress enable row level security;
alter table public.group_prayers enable row level security;
alter table public.group_prayer_marks enable row level security;
alter table public.group_posts enable row level security;
alter table public.group_announcements enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_reactions enable row level security;
alter table public.push_tokens enable row level security;

-- Helpers (security definer so policies can use them without recursion) -----

create or replace function public.genesis_is_member(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    join public.groups g on g.id = m.group_id
    where m.group_id = p_group and m.user_id = auth.uid() and g.deleted_at is null
  ) and public.genesis_feature_on('groups');
$$;

create or replace function public.genesis_is_leader(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = auth.uid() and m.role = 'leader'
  ) and public.genesis_is_member(p_group);
$$;

create or replace function public.genesis_prayer_group(p_prayer uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select group_id from public.group_prayers where id = p_prayer;
$$;

-- True when the text contains a blocked word (whole words, any case).
create or replace function public.genesis_is_objectionable(p_text text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocked_terms t
    where lower(coalesce(p_text, '')) ~ ('(^|[^a-z0-9])' || t.term || '($|[^a-z0-9])')
  );
$$;

create or replace function public.genesis_can_post_community()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.genesis_feature_on('community')
    and exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.community_terms_accepted_at is not null)
    and not exists (select 1 from public.community_bans b where b.user_id = auth.uid());
$$;

-- Fills in the author's name and checks the text before anything is saved.
create or replace function public.genesis_prepare_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent integer;
begin
  if tg_table_name in ('group_prayers', 'group_posts', 'group_announcements') then
    select m.display_name into new.display_name
    from public.group_members m
    where m.group_id = new.group_id and m.user_id = new.user_id;
  else
    select p.display_name into new.display_name from public.profiles p where p.user_id = new.user_id;
  end if;
  new.display_name := coalesce(new.display_name, 'Member');

  -- Fields only some tables have are read through jsonb, since PL/pgSQL
  -- checks every field it sees against the row.
  if coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false) then
    new.display_name := 'Someone';
  end if;

  if public.genesis_is_objectionable(new.body)
     or public.genesis_is_objectionable(to_jsonb(new) ->> 'title') then
    raise exception 'objectionable_content' using errcode = 'P0001', hint = 'Please rephrase. Some words aren''t allowed in Genesis.';
  end if;

  -- Fair use: at most 20 posts and comments an hour per person.
  if tg_table_name in ('community_posts', 'community_comments') then
    select (select count(*) from public.community_posts where user_id = new.user_id and created_at > now() - interval '1 hour')
         + (select count(*) from public.community_comments where user_id = new.user_id and created_at > now() - interval '1 hour')
    into recent;
    if recent >= 20 then
      raise exception 'rate_limited' using errcode = 'P0001', hint = 'You''ve posted a lot in the last hour. Please try again later.';
    end if;
  end if;

  new.created_at := now();
  return new;
end;
$$;

create or replace trigger group_prayers_prepare before insert on public.group_prayers
  for each row execute function public.genesis_prepare_content();
create or replace trigger group_posts_prepare before insert on public.group_posts
  for each row execute function public.genesis_prepare_content();
create or replace trigger group_announcements_prepare before insert on public.group_announcements
  for each row execute function public.genesis_prepare_content();
create or replace trigger community_posts_prepare before insert on public.community_posts
  for each row execute function public.genesis_prepare_content();
create or replace trigger community_comments_prepare before insert on public.community_comments
  for each row execute function public.genesis_prepare_content();

-- Keeps counts on posts and prayers in step.
create or replace function public.genesis_count_reactions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'community_reactions' then
    update public.community_posts
    set reaction_count = (select count(*) from public.community_reactions r where r.post_id = coalesce(new.post_id, old.post_id))
    where id = coalesce(new.post_id, old.post_id);
  elsif tg_table_name = 'community_comments' then
    update public.community_posts
    set comment_count = (select count(*) from public.community_comments c where c.post_id = coalesce(new.post_id, old.post_id) and c.deleted_at is null and c.hidden_at is null)
    where id = coalesce(new.post_id, old.post_id);
  elsif tg_table_name = 'group_prayer_marks' then
    update public.group_prayers
    set prayed_count = (select count(*) from public.group_prayer_marks k where k.prayer_id = coalesce(new.prayer_id, old.prayer_id))
    where id = coalesce(new.prayer_id, old.prayer_id);
  end if;
  return null;
end;
$$;

create or replace trigger community_reactions_count after insert or delete on public.community_reactions
  for each row execute function public.genesis_count_reactions();
create or replace trigger community_comments_count after insert or update on public.community_comments
  for each row execute function public.genesis_count_reactions();
create or replace trigger group_prayer_marks_count after insert or delete on public.group_prayer_marks
  for each row execute function public.genesis_count_reactions();

-- Three reports from different people hide community content until reviewed.
create or replace function public.genesis_after_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reports integer;
begin
  select count(*) into reports from public.content_reports
  where content_type = new.content_type and content_id = new.content_id and resolved_at is null;
  if reports >= 3 then
    if new.content_type = 'community_post' then
      update public.community_posts set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    elsif new.content_type = 'community_comment' then
      update public.community_comments set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    end if;
  end if;
  return null;
end;
$$;

create or replace trigger content_reports_after after insert on public.content_reports
  for each row execute function public.genesis_after_report();

-- Times come from the server, and new reports start open.
create or replace function public.genesis_stamp_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'content_reports' then
    new.created_at := now();
    new.resolved_at := null;
  elsif tg_table_name = 'group_progress' then
    new.completed_at := now();
  end if;
  return new;
end;
$$;

create or replace trigger content_reports_stamp before insert on public.content_reports
  for each row execute function public.genesis_stamp_row();
create or replace trigger group_progress_stamp before insert on public.group_progress
  for each row execute function public.genesis_stamp_row();

-- Policies ------------------------------------------------------------------

do $$
begin
  -- Profiles: your own only.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'Own profile') then
    create policy "Own profile" on public.profiles for select to authenticated using (user_id = (select auth.uid()));
  end if;

  -- Blocks: your own list.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_blocks' and policyname = 'Own blocks read') then
    create policy "Own blocks read" on public.user_blocks for select to authenticated using (blocker = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_blocks' and policyname = 'Own blocks add') then
    create policy "Own blocks add" on public.user_blocks for insert to authenticated with check (blocker = (select auth.uid()) and blocked <> (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_blocks' and policyname = 'Own blocks remove') then
    create policy "Own blocks remove" on public.user_blocks for delete to authenticated using (blocker = (select auth.uid()));
  end if;

  -- Reports: anyone signed in can report; only you (dashboard) read them.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'content_reports' and policyname = 'Report content') then
    create policy "Report content" on public.content_reports for insert to authenticated with check (reporter = (select auth.uid()));
  end if;

  -- Groups: members see their groups; leaders edit them.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'groups' and policyname = 'Members read') then
    create policy "Members read" on public.groups for select to authenticated using (public.genesis_is_member(id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_members' and policyname = 'Members read') then
    create policy "Members read" on public.group_members for select to authenticated using (public.genesis_is_member(group_id));
  end if;

  -- Plan progress: members see everyone's; you mark your own.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_progress' and policyname = 'Members read') then
    create policy "Members read" on public.group_progress for select to authenticated using (public.genesis_is_member(group_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_progress' and policyname = 'Own progress add') then
    create policy "Own progress add" on public.group_progress for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_is_member(group_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_progress' and policyname = 'Own progress remove') then
    create policy "Own progress remove" on public.group_progress for delete to authenticated using (user_id = (select auth.uid()));
  end if;

  -- Group prayer requests.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_prayers' and policyname = 'Members read') then
    create policy "Members read" on public.group_prayers for select to authenticated using (public.genesis_is_member(group_id) and deleted_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_prayers' and policyname = 'Members add') then
    create policy "Members add" on public.group_prayers for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_is_member(group_id) and prayed_count = 0 and answered_at is null and deleted_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_prayer_marks' and policyname = 'Own marks read') then
    create policy "Own marks read" on public.group_prayer_marks for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_prayer_marks' and policyname = 'Own marks add') then
    create policy "Own marks add" on public.group_prayer_marks for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_is_member(public.genesis_prayer_group(prayer_id)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_prayer_marks' and policyname = 'Own marks remove') then
    create policy "Own marks remove" on public.group_prayer_marks for delete to authenticated using (user_id = (select auth.uid()));
  end if;

  -- Group discussion.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_posts' and policyname = 'Members read') then
    create policy "Members read" on public.group_posts for select to authenticated using (public.genesis_is_member(group_id) and deleted_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_posts' and policyname = 'Members add') then
    create policy "Members add" on public.group_posts for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_is_member(group_id) and deleted_at is null);
  end if;

  -- Announcements: members read, leaders post.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_announcements' and policyname = 'Members read') then
    create policy "Members read" on public.group_announcements for select to authenticated using (public.genesis_is_member(group_id) and deleted_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_announcements' and policyname = 'Leaders add') then
    create policy "Leaders add" on public.group_announcements for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_is_leader(group_id) and deleted_at is null and notified_at is null);
  end if;

  -- Community: signed-in people read what isn't hidden or deleted (and their own).
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_posts' and policyname = 'Read visible') then
    create policy "Read visible" on public.community_posts for select to authenticated
      using (public.genesis_feature_on('community') and deleted_at is null and (hidden_at is null or user_id = (select auth.uid()))
        and not exists (select 1 from public.user_blocks b where b.blocker = (select auth.uid()) and b.blocked = user_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_posts' and policyname = 'Post') then
    create policy "Post" on public.community_posts for insert to authenticated
      with check (user_id = (select auth.uid()) and public.genesis_can_post_community() and reaction_count = 0 and comment_count = 0 and deleted_at is null and hidden_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_comments' and policyname = 'Read visible') then
    create policy "Read visible" on public.community_comments for select to authenticated
      using (public.genesis_feature_on('community') and deleted_at is null and (hidden_at is null or user_id = (select auth.uid()))
        and not exists (select 1 from public.user_blocks b where b.blocker = (select auth.uid()) and b.blocked = user_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_comments' and policyname = 'Comment') then
    create policy "Comment" on public.community_comments for insert to authenticated
      with check (user_id = (select auth.uid()) and public.genesis_can_post_community() and deleted_at is null and hidden_at is null
        and exists (select 1 from public.community_posts p where p.id = post_id and p.deleted_at is null and p.hidden_at is null));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_reactions' and policyname = 'Own reactions read') then
    create policy "Own reactions read" on public.community_reactions for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_reactions' and policyname = 'React') then
    create policy "React" on public.community_reactions for insert to authenticated with check (user_id = (select auth.uid()) and public.genesis_can_post_community()
      and exists (select 1 from public.community_posts p where p.id = post_id and p.deleted_at is null and p.hidden_at is null));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_reactions' and policyname = 'Unreact') then
    create policy "Unreact" on public.community_reactions for delete to authenticated using (user_id = (select auth.uid()));
  end if;

  -- Push tokens: your own.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'push_tokens' and policyname = 'Own tokens read') then
    create policy "Own tokens read" on public.push_tokens for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'push_tokens' and policyname = 'Own tokens add') then
    create policy "Own tokens add" on public.push_tokens for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'push_tokens' and policyname = 'Own tokens update') then
    create policy "Own tokens update" on public.push_tokens for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'push_tokens' and policyname = 'Own tokens remove') then
    create policy "Own tokens remove" on public.push_tokens for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

-- Actions (called by the app; each checks who is asking) ---------------------

-- Sets your display name everywhere it's shown from now on.
create or replace function public.set_display_name(p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleaned text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if char_length(cleaned) not between 1 and 40 then raise exception 'invalid_name' using errcode = 'P0001'; end if;
  if public.genesis_is_objectionable(cleaned) then
    raise exception 'objectionable_content' using errcode = 'P0001', hint = 'Please choose another name.';
  end if;
  insert into public.profiles (user_id, display_name) values (auth.uid(), cleaned)
  on conflict (user_id) do update set display_name = excluded.display_name, updated_at = now();
  update public.group_members set display_name = cleaned where user_id = auth.uid();
end;
$$;

create or replace function public.accept_community_terms()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set community_terms_accepted_at = now(), updated_at = now() where user_id = auth.uid();
  if not found then raise exception 'name_required' using errcode = 'P0001', hint = 'Choose a display name first.'; end if;
end;
$$;

-- Checks a group's name, description and reading plan.
create or replace function public.genesis_check_group(p_name text, p_description text, p_plan_id text, p_plan_title text, p_plan_books integer[], p_plan_days integer)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 60 or char_length(coalesce(p_description, '')) > 500 then
    raise exception 'invalid_group' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_plan_id, '')) > 80 or char_length(coalesce(p_plan_title, '')) > 120 then
    raise exception 'invalid_plan' using errcode = 'P0001';
  end if;
  if p_plan_books is not null and (
       cardinality(p_plan_books) not between 1 and 66
       or exists (select 1 from unnest(p_plan_books) b where b is null or b not between 1 and 66)
       or p_plan_days is null or p_plan_days not between 1 and 730) then
    raise exception 'invalid_plan' using errcode = 'P0001';
  end if;
  if public.genesis_is_objectionable(p_name) or public.genesis_is_objectionable(p_description) or public.genesis_is_objectionable(p_plan_title) then
    raise exception 'objectionable_content' using errcode = 'P0001', hint = 'Please rephrase. Some words aren''t allowed in Genesis.';
  end if;
end;
$$;

create or replace function public.genesis_new_invite_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw text;
begin
  loop
    -- 10 characters from a random UUID (about a trillion possibilities).
    raw := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from public.groups where invite_code = raw);
  end loop;
  return raw;
end;
$$;

create or replace function public.create_group(
  p_name text,
  p_description text,
  p_plan_id text,
  p_plan_title text,
  p_plan_books integer[],
  p_plan_days integer,
  p_plan_start date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  member_name text;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_feature_on('groups') then raise exception 'groups_off' using errcode = 'P0001'; end if;
  select display_name into member_name from public.profiles where user_id = auth.uid();
  if member_name is null then raise exception 'name_required' using errcode = 'P0001', hint = 'Choose a display name first.'; end if;
  perform public.genesis_check_group(p_name, p_description, p_plan_id, p_plan_title, p_plan_books, p_plan_days);
  if (select count(*) from public.groups where created_by = auth.uid() and deleted_at is null) >= 20 then
    raise exception 'too_many_groups' using errcode = 'P0001';
  end if;

  insert into public.groups (name, description, invite_code, plan_id, plan_title, plan_books, plan_days, plan_start, created_by)
  values (btrim(p_name), coalesce(p_description, ''), public.genesis_new_invite_code(), p_plan_id, p_plan_title, p_plan_books, p_plan_days, p_plan_start, auth.uid())
  returning id into new_id;

  insert into public.group_members (group_id, user_id, role, display_name)
  values (new_id, auth.uid(), 'leader', member_name);
  return new_id;
end;
$$;

create or replace function public.join_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  found_id uuid;
  member_name text;
  cleaned text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_feature_on('groups') then raise exception 'groups_off' using errcode = 'P0001'; end if;
  select display_name into member_name from public.profiles where user_id = auth.uid();
  if member_name is null then raise exception 'name_required' using errcode = 'P0001', hint = 'Choose a display name first.'; end if;
  select id into found_id from public.groups where invite_code = cleaned and deleted_at is null;
  if found_id is null then raise exception 'invalid_code' using errcode = 'P0001', hint = 'That invite code wasn''t found. Check it with your group leader.'; end if;
  if (select count(*) from public.group_members where group_id = found_id) >= 500 then
    raise exception 'group_full' using errcode = 'P0001';
  end if;
  insert into public.group_members (group_id, user_id, role, display_name)
  values (found_id, auth.uid(), 'member', member_name)
  on conflict (group_id, user_id) do nothing;
  return found_id;
end;
$$;

create or replace function public.update_group(p_group uuid, p_name text, p_description text, p_plan_id text, p_plan_title text, p_plan_books integer[], p_plan_days integer, p_plan_start date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'leaders_only' using errcode = 'P0001'; end if;
  perform public.genesis_check_group(p_name, p_description, p_plan_id, p_plan_title, p_plan_books, p_plan_days);
  update public.groups
  set name = btrim(p_name), description = coalesce(p_description, ''), plan_id = p_plan_id, plan_title = p_plan_title,
      plan_books = p_plan_books, plan_days = p_plan_days, plan_start = p_plan_start, updated_at = now()
  where id = p_group;
end;
$$;

create or replace function public.new_invite_code(p_group uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  code text;
begin
  if not public.genesis_is_leader(p_group) then raise exception 'leaders_only' using errcode = 'P0001'; end if;
  code := public.genesis_new_invite_code();
  update public.groups set invite_code = code, updated_at = now() where id = p_group;
  return code;
end;
$$;

create or replace function public.set_member_role(p_group uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'leaders_only' using errcode = 'P0001'; end if;
  if p_role not in ('leader', 'member') then raise exception 'invalid_role' using errcode = 'P0001'; end if;
  if p_role = 'member' and p_user = auth.uid()
     and (select count(*) from public.group_members where group_id = p_group and role = 'leader') <= 1 then
    raise exception 'last_leader' using errcode = 'P0001', hint = 'Make someone else a leader first.';
  end if;
  update public.group_members set role = p_role where group_id = p_group and user_id = p_user;
end;
$$;

create or replace function public.remove_member(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user = auth.uid() then raise exception 'use_leave' using errcode = 'P0001'; end if;
  if not public.genesis_is_leader(p_group) then raise exception 'leaders_only' using errcode = 'P0001'; end if;
  delete from public.group_members where group_id = p_group and user_id = p_user;
  -- A new code, so the person can't simply rejoin with the old one.
  update public.groups set invite_code = public.genesis_new_invite_code(), updated_at = now() where id = p_group;
end;
$$;

-- Leave a group. The last leader hands over to the longest-standing member;
-- the last person out closes the group.
create or replace function public.leave_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_leader uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  delete from public.group_members where group_id = p_group and user_id = auth.uid();
  if not exists (select 1 from public.group_members where group_id = p_group) then
    update public.groups set deleted_at = now(), updated_at = now() where id = p_group;
  elsif not exists (select 1 from public.group_members where group_id = p_group and role = 'leader') then
    select user_id into next_leader from public.group_members where group_id = p_group order by joined_at limit 1;
    update public.group_members set role = 'leader' where group_id = p_group and user_id = next_leader;
  end if;
end;
$$;

create or replace function public.delete_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'leaders_only' using errcode = 'P0001'; end if;
  update public.groups set deleted_at = now(), updated_at = now() where id = p_group;
end;
$$;

-- Remove a post: authors remove their own; group leaders remove anything in
-- their group.
create or replace function public.remove_content(p_type text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  author uuid;
  owner_group uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if p_type = 'group_prayer' then
    select user_id, group_id into author, owner_group from public.group_prayers where id = p_id;
  elsif p_type = 'group_post' then
    select user_id, group_id into author, owner_group from public.group_posts where id = p_id;
  elsif p_type = 'group_announcement' then
    select user_id, group_id into author, owner_group from public.group_announcements where id = p_id;
  elsif p_type = 'community_post' then
    select user_id into author from public.community_posts where id = p_id;
  elsif p_type = 'community_comment' then
    select user_id into author from public.community_comments where id = p_id;
  else
    raise exception 'invalid_type' using errcode = 'P0001';
  end if;
  if author is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if author <> auth.uid() and (owner_group is null or not public.genesis_is_leader(owner_group)) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;

  if p_type = 'group_prayer' then
    update public.group_prayers set deleted_at = now() where id = p_id;
  elsif p_type = 'group_post' then
    update public.group_posts set deleted_at = now() where id = p_id;
  elsif p_type = 'group_announcement' then
    update public.group_announcements set deleted_at = now() where id = p_id;
  elsif p_type = 'community_post' then
    update public.community_posts set deleted_at = now() where id = p_id;
  else
    update public.community_comments set deleted_at = now() where id = p_id;
  end if;
end;
$$;

-- Turn announcement notifications for one group on or off.
create or replace function public.set_group_notifications(p_group uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.group_members set notifications = p_on where group_id = p_group and user_id = auth.uid();
  if not found then raise exception 'not_a_member' using errcode = 'P0001'; end if;
end;
$$;

-- The author marks their prayer request answered (or not).
create or replace function public.set_prayer_answered(p_prayer uuid, p_answered boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.group_prayers
  set answered_at = case when p_answered then coalesce(answered_at, now()) else null end
  where id = p_prayer and user_id = auth.uid();
  if not found then raise exception 'not_allowed' using errcode = 'P0001'; end if;
end;
$$;

-- Anonymous prayer requests: nobody can read who wrote a post directly. The
-- feed comes from community_feed(), which gives the author only when the post
-- isn't anonymous (or is your own).
revoke select on public.community_posts from anon, authenticated;
grant select (id, kind, body, start_verse, end_verse, display_name, is_anonymous, reaction_count, comment_count, created_at, deleted_at, hidden_at)
  on public.community_posts to authenticated;

create or replace function public.community_feed(p_kind text, p_before timestamptz, p_limit integer)
returns table (
  id uuid, author_id uuid, is_mine boolean, kind text, body text, start_verse integer, end_verse integer,
  display_name text, reaction_count integer, comment_count integer, created_at timestamptz, hidden_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id,
         case when p.is_anonymous and p.user_id <> auth.uid() then null else p.user_id end,
         p.user_id = auth.uid(),
         p.kind, p.body, p.start_verse, p.end_verse, p.display_name, p.reaction_count, p.comment_count, p.created_at, p.hidden_at
  from public.community_posts p
  where auth.uid() is not null
    and public.genesis_feature_on('community')
    and p.kind = p_kind
    and p.deleted_at is null
    and (p.hidden_at is null or p.user_id = auth.uid())
    and (p_before is null or p.created_at < p_before)
    and not exists (select 1 from public.user_blocks b where b.blocker = auth.uid() and b.blocked = p.user_id)
  order by p.created_at desc
  limit least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

-- Block whoever wrote a post, even an anonymous one, without revealing who.
create or replace function public.block_post_author(p_post uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  author uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  select user_id into author from public.community_posts where id = p_post;
  if author is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if author = auth.uid() then return; end if;
  insert into public.user_blocks (blocker, blocked) values (auth.uid(), author) on conflict do nothing;
end;
$$;

-- Only signed-in people can call the actions.
revoke all on function public.set_display_name(text) from public, anon;
revoke all on function public.accept_community_terms() from public, anon;
revoke all on function public.create_group(text, text, text, text, integer[], integer, date) from public, anon;
revoke all on function public.join_group(text) from public, anon;
revoke all on function public.update_group(uuid, text, text, text, text, integer[], integer, date) from public, anon;
revoke all on function public.new_invite_code(uuid) from public, anon;
revoke all on function public.set_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.remove_member(uuid, uuid) from public, anon;
revoke all on function public.leave_group(uuid) from public, anon;
revoke all on function public.delete_group(uuid) from public, anon;
revoke all on function public.remove_content(text, uuid) from public, anon;
revoke all on function public.set_prayer_answered(uuid, boolean) from public, anon;
revoke all on function public.set_group_notifications(uuid, boolean) from public, anon;
revoke all on function public.community_feed(text, timestamptz, integer) from public, anon;
revoke all on function public.block_post_author(uuid) from public, anon;
revoke all on function public.genesis_new_invite_code() from public, anon, authenticated;
grant execute on function public.set_display_name(text) to authenticated;
grant execute on function public.accept_community_terms() to authenticated;
grant execute on function public.create_group(text, text, text, text, integer[], integer, date) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.update_group(uuid, text, text, text, text, integer[], integer, date) to authenticated;
grant execute on function public.new_invite_code(uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;
grant execute on function public.delete_group(uuid) to authenticated;
grant execute on function public.remove_content(text, uuid) to authenticated;
grant execute on function public.set_prayer_answered(uuid, boolean) to authenticated;
grant execute on function public.set_group_notifications(uuid, boolean) to authenticated;
grant execute on function public.community_feed(text, timestamptz, integer) to authenticated;
grant execute on function public.block_post_author(uuid) to authenticated;

-- Helpers: used by policies and actions, never called by people directly.
-- Signed-in people need them for the policies; anonymous visitors don't.
revoke all on function public.genesis_feature_on(text) from public, anon;
revoke all on function public.genesis_is_member(uuid) from public, anon;
revoke all on function public.genesis_is_leader(uuid) from public, anon;
revoke all on function public.genesis_prayer_group(uuid) from public, anon;
revoke all on function public.genesis_is_objectionable(text) from public, anon;
revoke all on function public.genesis_can_post_community() from public, anon;
revoke all on function public.genesis_check_group(text, text, text, text, integer[], integer) from public, anon, authenticated;
revoke all on function public.genesis_prepare_content() from public, anon, authenticated;
revoke all on function public.genesis_count_reactions() from public, anon, authenticated;
revoke all on function public.genesis_after_report() from public, anon, authenticated;
revoke all on function public.genesis_stamp_row() from public, anon, authenticated;
grant execute on function public.genesis_feature_on(text) to authenticated;
grant execute on function public.genesis_is_member(uuid) to authenticated;
grant execute on function public.genesis_is_leader(uuid) to authenticated;
grant execute on function public.genesis_prayer_group(uuid) to authenticated;
grant execute on function public.genesis_is_objectionable(text) to authenticated;
grant execute on function public.genesis_can_post_community() to authenticated;

-- Your review list: open reports with what was reported. Visible only in the
-- dashboard (it runs with the reader's permissions, and nobody else can read
-- reports). Resolve one with:
--   update public.content_reports set resolved_at = now() where content_id = '...';
-- Unhide a post you've checked:
--   update public.community_posts set hidden_at = null where id = '...';
-- Stop someone posting:
--   insert into public.community_bans (user_id, reason) values ('...', '...');
create or replace view public.moderation_queue
with (security_invoker = true)
as
select
  r.content_type,
  r.content_id,
  count(*) as reports,
  min(r.created_at) as first_reported,
  string_agg(nullif(r.reason, ''), ' | ') as reasons,
  coalesce(cp.body, cc.body, gp.body, gpo.body, ga.title || ': ' || ga.body) as content,
  coalesce(cp.user_id, cc.user_id, gp.user_id, gpo.user_id, ga.user_id) as author,
  coalesce(cp.display_name, cc.display_name, gp.display_name, gpo.display_name, ga.display_name) as author_name,
  coalesce(cp.hidden_at, cc.hidden_at) as hidden_at
from public.content_reports r
left join public.community_posts cp on r.content_type = 'community_post' and cp.id = r.content_id
left join public.community_comments cc on r.content_type = 'community_comment' and cc.id = r.content_id
left join public.group_prayers gp on r.content_type = 'group_prayer' and gp.id = r.content_id
left join public.group_posts gpo on r.content_type = 'group_post' and gpo.id = r.content_id
left join public.group_announcements ga on r.content_type = 'group_announcement' and ga.id = r.content_id
where r.resolved_at is null
group by r.content_type, r.content_id, cp.body, cc.body, gp.body, gpo.body, ga.title, ga.body,
  cp.user_id, cc.user_id, gp.user_id, gpo.user_id, ga.user_id,
  cp.display_name, cc.display_name, gp.display_name, gpo.display_name, ga.display_name, cp.hidden_at, cc.hidden_at;

revoke all on public.moderation_queue from anon, authenticated;

-- A starter list of blocked words. Add your own in Table Editor -> blocked_terms
-- (lowercase letters and digits only, one word per row).
insert into public.blocked_terms (term) values
  ('fuck'), ('fucking'), ('fucker'), ('motherfucker'), ('shit'), ('shitty'), ('bullshit'),
  ('bitch'), ('bitches'), ('bastard'), ('asshole'), ('cunt'), ('dick'), ('dickhead'),
  ('cock'), ('pussy'), ('slut'), ('whore'), ('wanker'), ('twat'), ('prick'),
  ('porn'), ('porno'), ('nude'), ('nudes'), ('sexting'), ('onlyfans'),
  ('retard'), ('retarded'), ('faggot'), ('fag'), ('nigger'), ('nigga'), ('kike'), ('spic'), ('chink'), ('tranny'),
  ('killyourself'), ('kys')
on conflict (term) do nothing;
