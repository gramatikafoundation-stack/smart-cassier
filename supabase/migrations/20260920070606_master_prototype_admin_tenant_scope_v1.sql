alter policy "Admins delete menu"
on public.menu_items
using ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins insert menu"
on public.menu_items
with check ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins update menu"
on public.menu_items
using ((select private.is_admin()) and tenant_id = private.client_tenant_id())
with check ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins create order events"
on public.order_events
with check ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins read order events"
on public.order_events
using ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins create orders"
on public.orders
with check ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins read orders"
on public.orders
using ((select private.is_admin()) and tenant_id = private.client_tenant_id());

alter policy "Admins update orders"
on public.orders
using ((select private.is_admin()) and tenant_id = private.client_tenant_id())
with check ((select private.is_admin()) and tenant_id = private.client_tenant_id());
