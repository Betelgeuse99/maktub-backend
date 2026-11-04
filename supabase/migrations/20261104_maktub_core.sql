-- Maktub multi-network dashboard: core schema
-- One tenant, N networks. Only the edge function (service role) touches these tables.

create extension if not exists pgcrypto;

create table if not exists public.tenant (
  id integer primary key,
  name text not null,
  status text not null default 'active' check (status in ('active','expired','locked')),
  paid_until timestamptz not null,
  per_network_amount integer not null default 500000, -- kobo: N5,000 per network
  email text,
  squad_token_id text,
  last_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.networks (
  id uuid primary key default gen_random_uuid(),
  tenant_id integer not null references public.tenant(id) on delete cascade default 1,
  name text not null,
  slug text not null unique,
  api_key_hash text not null unique,
  plan_prices jsonb not null default '{"24hr":200,"7d":800,"30d":3000}'::jsonb,
  timezone text not null default 'Africa/Lagos',
  status text not null default 'active' check (status in ('active','disabled')),
  last_sync timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.mikrotik_users (
  id bigserial primary key,
  network_id uuid not null references public.networks(id) on delete cascade,
  username text not null,
  password text,
  profile text,
  plan text,
  mac_address text,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','expired')),
  first_login_at timestamptz,
  last_seen timestamptz,
  disabled boolean not null default false,
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (network_id, username)
);

create table if not exists public.activity_log (
  id bigserial primary key,
  network_id uuid references public.networks(id) on delete cascade,
  level text,
  message text not null,
  ref text,
  username text,
  mac text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  id bigserial primary key,
  tenant_id integer not null default 1 references public.tenant(id) on delete cascade,
  username text not null unique,
  password_hash text not null,
  role text not null default 'owner' check (role in ('owner','viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_sessions (
  id bigserial primary key,
  session_id text not null unique,
  username text not null,
  role text not null,
  ip text,
  user_agent text,
  created_at timestamptz not null default now(),
  last_activity timestamptz not null default now(),
  revoked boolean not null default false
);

create table if not exists public.subscription_payments (
  id bigserial primary key,
  reference text not null unique,
  amount integer not null,
  status text not null default 'pending',
  kind text,
  network_count integer,
  paid_until timestamptz,
  email text,
  token_id text,
  raw jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_maktub_users_network_status on public.mikrotik_users(network_id, status);
create index if not exists idx_maktub_users_network_seen on public.mikrotik_users(network_id, last_seen desc);
create index if not exists idx_maktub_users_expiry on public.mikrotik_users(network_id, expires_at);
create index if not exists idx_maktub_activity on public.activity_log(network_id, created_at desc);
create index if not exists idx_maktub_sessions on public.admin_sessions(session_id);

alter table public.tenant enable row level security;
alter table public.networks enable row level security;
alter table public.mikrotik_users enable row level security;
alter table public.activity_log enable row level security;
alter table public.admin_users enable row level security;
alter table public.admin_sessions enable row level security;
alter table public.subscription_payments enable row level security;

-- Seed tenant: active until 10 Nov 2026 00:00 WAT (09 Nov 23:00 UTC). No grace.
insert into public.tenant (id, name, status, paid_until, per_network_amount, email)
values (1, 'Maktub', 'active', '2026-11-09T23:00:00Z', 500000, 'dreamhatchertech@gmail.com')
on conflict (id) do nothing;

-- Seed the two networks. Hashes are injected at apply time; placeholders are safe in git.
insert into public.networks (name, slug, api_key_hash, plan_prices)
values
  ('Maktub 1', 'maktub-1', '__KEY1_HASH__', '{"24hr":200,"7d":800,"30d":3000}'::jsonb),
  ('Maktub 2', 'maktub-2', '__KEY2_HASH__', '{"24hr":200,"7d":800,"30d":3000}'::jsonb)
on conflict (slug) do nothing;

-- Seed the single owner login. Hash injected at apply time.
insert into public.admin_users (tenant_id, username, password_hash, role)
values (1, 'admin', '__ADMIN_HASH__', 'owner')
on conflict (username) do nothing;

insert into public.activity_log (level, message)
values ('system', 'Maktub tenant created')

on conflict do nothing;

-- Per-network aggregates used by the cards and the per-network dashboard.
create or replace function public.maktub_network_stats()
returns table (
  network_id uuid,
  online bigint,
  expired bigint,
  active bigint,
  total bigint,
  revenue_today bigint,
  revenue_week bigint,
  revenue_month bigint
)
language sql stable as $$
  with base as (
    select n.id as network_id,
           n.plan_prices,
           u.id as user_id,
           u.plan,
           u.status,
           u.expires_at,
           u.last_seen,
           u.first_login_at
    from public.networks n
    left join public.mikrotik_users u on u.network_id = n.id
    where n.status = 'active'
  ),
  d as (
    select (now() at time zone 'Africa/Lagos')::date as today
  )
  select
    b.network_id,
    count(b.user_id) filter (
      where b.last_seen > now() - interval '3 minutes'
        and b.status = 'active'
        and (b.expires_at is null or b.expires_at > now())
    ) as online,
    count(b.user_id) filter (
      where b.status = 'expired'
         or (b.expires_at is not null and b.expires_at <= now())
    ) as expired,
    count(b.user_id) filter (
      where b.status = 'active'
        and (b.expires_at is null or b.expires_at > now())
    ) as active,
    count(b.user_id) as total,
    coalesce(sum((b.plan_prices->>b.plan)::int) filter (
      where (b.first_login_at at time zone 'Africa/Lagos')::date = (select today from d)
    ), 0)::bigint as revenue_today,
    coalesce(sum((b.plan_prices->>b.plan)::int) filter (
      where (b.first_login_at at time zone 'Africa/Lagos')::date >= (select today - 6 from d)
    ), 0)::bigint as revenue_week,
    coalesce(sum((b.plan_prices->>b.plan)::int) filter (
      where (b.first_login_at at time zone 'Africa/Lagos')::date >= date_trunc('month', (select today from d))::date
    ), 0)::bigint as revenue_month
  from base b
  group by b.network_id, b.plan_prices;
$$;

-- Paged user list with filters + total count.
create or replace function public.maktub_users(
  p_network uuid,
  p_search text default '',
  p_status text default 'all',
  p_limit int default 50,
  p_offset int default 0
)
returns table (
  username text,
  plan text,
  profile text,
  mac_address text,
  status text,
  expires_at timestamptz,
  first_login_at timestamptz,
  last_seen timestamptz,
  online boolean,
  total_count bigint
)
language sql stable as $$
  with filtered as (
    select u.*,
           (u.last_seen > now() - interval '3 minutes') as is_online
    from public.mikrotik_users u
    where u.network_id = p_network
      and (
        p_search = ''
        or u.username ilike '%' || p_search || '%'
        or coalesce(u.mac_address, '') ilike '%' || p_search || '%'
      )
      and (
        p_status = 'all'
        or (p_status = 'online' and u.status = 'active'
            and (u.expires_at is null or u.expires_at > now())
            and u.last_seen > now() - interval '3 minutes')
        or (p_status = 'active' and u.status = 'active'
            and (u.expires_at is null or u.expires_at > now()))
        or (p_status = 'expired' and (u.status = 'expired'
            or (u.expires_at is not null and u.expires_at <= now())))
      )
  )
  select f.username, f.plan, f.profile, f.mac_address, f.status,
         f.expires_at, f.first_login_at, f.last_seen, f.is_online,
         count(*) over() as total_count
  from filtered f
  order by (f.last_seen is null), f.last_seen desc, f.username asc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
$$;

-- Expire due users. Called by cron and by the sync endpoint.
create or replace function public.maktub_expire_users()
returns integer
language plpgsql as $$
declare
  n integer;
begin
  update public.mikrotik_users
     set status = 'expired', updated_at = now()
   where status = 'active'
     and expires_at is not null
     and expires_at <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.maktub_network_stats() to service_role;
grant execute on function public.maktub_users(uuid, text, text, int, int) to service_role;
grant execute on function public.maktub_expire_users() to service_role;
