create policy kds_observability_deny_select
on private.kds_observability_samples
for select
to anon, authenticated
using (false);

create policy kds_observability_deny_insert
on private.kds_observability_samples
for insert
to anon, authenticated
with check (false);

create policy kds_observability_deny_update
on private.kds_observability_samples
for update
to anon, authenticated
using (false)
with check (false);

create policy kds_observability_deny_delete
on private.kds_observability_samples
for delete
to anon, authenticated
using (false);
