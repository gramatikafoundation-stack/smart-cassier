-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260912171106  Name: edge_function_retirement_catalog_v1
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

insert into private.release_component_registry(component_key,display_name,component_type,canonical_target,expected_version,expected_sha256,deployment_ref,rollback_ref,lifecycle,critical,change_control_component,source_mode,notes)
values
('retired_html_test','Retired HTML Test','edge-function','rohmat-html-test-v1','v2','f7cab8d230c1026cd70d7033164e186d0212ade3f75b1165e6b94885ec3c10c2',null,'retired-410','retired',false,null,'supabase-edge-version','Retired test endpoint; expected behavior is HTTP 410 Gone.'),
('retired_xhtml_test','Retired XHTML Test','edge-function','rohmat-xhtml-test-v1','v4','ae472c5b83b671ed6c206ef5dd4827577b798b7ae8af72d79c718731f0cfdb57',null,'retired-410','retired',false,null,'supabase-edge-version','Retired test endpoint; expected behavior is HTTP 410 Gone.'),
('retired_svg_test','Retired SVG Test','edge-function','rohmat-svg-test-v1','v2','1a4743793f97e91643430e76dc4464a50d5d45cbbcb8f59650dc38047434b8ec',null,'retired-410','retired',false,null,'supabase-edge-version','Retired test endpoint; expected behavior is HTTP 410 Gone.'),
('retired_static_publisher','Retired Static Publisher','edge-function','rohmat-static-publisher-v1','v2','96ccaee4d0ec77e2e133874aa6ce2d822480f192eb4a3ae4640f737f19d3eff3',null,'retired-410','retired',false,null,'supabase-edge-version','Legacy publisher retired; expected behavior is HTTP 410 legacy_endpoint_retired.')
on conflict(component_key) do update set display_name=excluded.display_name,component_type=excluded.component_type,canonical_target=excluded.canonical_target,expected_version=excluded.expected_version,expected_sha256=excluded.expected_sha256,deployment_ref=excluded.deployment_ref,rollback_ref=excluded.rollback_ref,lifecycle=excluded.lifecycle,critical=excluded.critical,change_control_component=excluded.change_control_component,source_mode=excluded.source_mode,last_verified_at=now(),notes=excluded.notes;
