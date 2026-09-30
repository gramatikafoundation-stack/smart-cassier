-- SDB AI Core controlled seed data.
insert into sdb_ai.products(product_key,display_name,risk_profile) values
 ('sdb-core','SDB AI Core','high'),
 ('smart-cashier','SMART CASHIER','high'),
 ('smart-insight','SMART INSIGHT','medium'),
 ('smart-asisten','SMART ASISTEN','high'),
 ('media-ai','Media AI','medium')
on conflict(product_key) do update set display_name=excluded.display_name,risk_profile=excluded.risk_profile,updated_at=now();

insert into sdb_ai.model_routes(task_class,primary_model,fallback_model,reasoning_effort,max_output_tokens,max_input_bytes) values
 ('simple','gpt-6-luna','gpt-5.6-luna','low',1200,32768),
 ('standard','gpt-6-luna','gpt-5.6-luna','medium',2400,65536),
 ('complex','gpt-6-sol','gpt-5.6-sol','high',5000,131072),
 ('vision','gpt-6-luna','gpt-5.6-luna','medium',2400,1048576)
on conflict(task_class) do update set primary_model=excluded.primary_model,fallback_model=excluded.fallback_model,reasoning_effort=excluded.reasoning_effort,max_output_tokens=excluded.max_output_tokens,max_input_bytes=excluded.max_input_bytes,enabled=true,updated_at=now();

insert into sdb_ai.model_rates(model,input_usd_per_million,output_usd_per_million,source_note) values
 ('gpt-6-luna',0.10,0.50,'OpenAI model catalog checked 2026-10-01; account availability verified live'),
 ('gpt-6-sol',2.00,10.00,'OpenAI model catalog checked 2026-10-01; account availability verified live'),
 ('gpt-5.6-luna',0.20,1.20,'Fallback model rate'),
 ('gpt-5.6-sol',4.00,20.00,'Fallback model rate')
on conflict(model) do update set input_usd_per_million=excluded.input_usd_per_million,output_usd_per_million=excluded.output_usd_per_million,source_note=excluded.source_note,updated_at=now();

insert into sdb_ai.spend_controls(product_key,requests_per_minute,daily_request_limit,monthly_input_token_limit,monthly_output_token_limit) values
 ('smart-cashier',30,1000,10000000,2000000),
 ('smart-insight',20,300,10000000,2000000),
 ('smart-asisten',20,500,8000000,2000000),
 ('media-ai',30,800,10000000,2500000),
 ('sdb-core',10,200,5000000,1500000)
on conflict(product_key) do update set requests_per_minute=excluded.requests_per_minute,daily_request_limit=excluded.daily_request_limit,monthly_input_token_limit=excluded.monthly_input_token_limit,monthly_output_token_limit=excluded.monthly_output_token_limit,enabled=true,updated_at=now();

-- Prompt registry and tool-policy seeds are deliberately versioned and should
-- be promoted from the validated environment, not silently overwritten.
