# Batch 5 Security Review — 2026-09-25

Project: Supabase `xrepmvbccalzhlcznrff`.

## Effective privilege findings

### `private.kds_realtime_channels`

Supabase inventory reports RLS disabled. Effective privilege inspection shows:

- `anon`: no schema usage and no SELECT/INSERT/UPDATE/DELETE;
- `authenticated`: no table SELECT/INSERT/UPDATE/DELETE;
- object is in the private schema.

Therefore no active direct client data exposure was demonstrated. RLS is still desirable defense in depth, but it must not be enabled blindly without validating the realtime access model.

### `private.sheet_writer_lease` and `public.public_rum_samples`

Advisor reports RLS enabled with no policy. Both objects currently grant no direct table CRUD privileges to `anon` or `authenticated`. This is fail-closed rather than publicly readable.

### `public.master_prototype_resolve_origin(text,text)`

Advisor reports anonymous EXECUTE on a SECURITY DEFINER function. Review confirms:

- `search_path` is explicitly empty;
- PUBLIC execute is false;
- authenticated execute is false;
- anonymous execute is intentional for origin bootstrap;
- the function normalizes and matches only enabled registered origins and active tenant/runtime rows;
- foreign origins return `tenant_not_resolved`;
- return data is limited to runtime/public tenant configuration.

This is an intentional narrowly-scoped bootstrap surface, not an unrestricted privileged RPC.

### Leaked password protection

Supabase Auth leaked-password protection is disabled and one Auth password user exists. Active Public/Admin/KDS source does not use Supabase password sign-in; application authentication uses its own tenant-scoped session/RPC boundaries. The warning therefore remains a platform-account hardening item rather than an exposed application login path.

The connected Supabase management toolset available during Batch 5 does not expose an Auth-setting mutation for this toggle. It is retained as a visible non-P0/P1 hardening item rather than bypassed or misreported as fixed.

## Freeze interpretation

Security freeze requires zero demonstrated privilege escape, cross-tenant exposure, secret leakage, or unauthenticated privileged mutation. Informational/advisor findings with proven fail-closed effective privileges may remain documented exceptions, but they must be re-reviewed after any schema/grant/auth change.
