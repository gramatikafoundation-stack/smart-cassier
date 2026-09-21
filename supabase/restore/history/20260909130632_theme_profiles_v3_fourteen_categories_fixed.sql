-- Sanitized DR-only replay snapshot from production migration history.
-- Version: 20260909130632  Name: theme_profiles_v3_fourteen_categories_fixed
-- Production-specific credentials, operator identities, and project endpoint were neutralized.

create table if not exists private.theme_profiles (
  id text primary key,
  name text not null,
  tag text not null default '',
  profile jsonb not null,
  updated_at timestamptz not null default now()
);

with x(id,name,tag,bg,panel,pri,accent,textc,muted,body_font,heading_font,base_size,heading_scale,width,macro,hero,menu_cols,checkout_mode,section_gap,card_gap,card_pad,control_pad,card_style,button_style,card_radius,button_radius,input_radius,image_radius,shadow_style,border_style,border_width,nav_style,nav_position,nav_sticky,img_aspect,img_treatment,saturation,contrastv,brightness,density_mode,density_scale,form_style,form_height,form_border,label_style,visual_character,surface,decoration,contrast_mode,motion_mode,duration,hover_lift,hover_scale) as (values
('heritage-nusantara','Heritage Nusantara','Tradisional • Autentik • Premium','#F5EFE3','#FFFDF8','#315343','#B87444','#24362F','#7C776E','Georgia','Georgia',15,1.38,'balanced','asymmetric','split-left',3,'split',72,18,20,12,'outlined','solid',18,12,12,14,'soft','subtle',1,'pill','top',true,'4/3','warm',1.02,1.03,1.00,'balanced',1.00,'outlined',48,1,'above','heritage','paper','heritage-line','medium','subtle',180,2,1.01),
('modern-emerald','Modern Emerald','Natural • Profesional • Modern','#EEF4F0','#FFFFFF','#235345','#4F8A72','#203B32','#6E8179','Inter','Inter',15,1.32,'balanced','balanced','split-left',3,'split',64,18,18,12,'soft','solid',20,12,12,16,'soft','subtle',1,'pill','top',true,'4/3','natural',1.00,1.00,1.00,'balanced',1.00,'outlined',48,1,'above','natural-professional','soft','none','medium','subtle',160,2,1.01),
('terracotta-bistro','Terracotta Bistro','Warm • Artisan • Culinary','#F8F0EA','#FFFCF9','#6A493A','#C96D4B','#3D302A','#88766C','Inter','Georgia',15,1.40,'balanced','asymmetric','split-right',3,'split',72,20,20,13,'elevated','solid',18,14,12,18,'soft','subtle',1,'pill','top',true,'4/3','warm',1.06,1.04,1.02,'spacious',1.08,'filled',50,1,'above','artisan-warm','textured','warm-edge','medium','soft',200,3,1.015),
('midnight-gold','Midnight Gold','Luxury • Dramatic • Exclusive','#15171A','#202329','#252B32','#C6A15B','#F6F1E7','#AFA79B','Georgia','Georgia',15,1.46,'wide','immersive','fullbleed',2,'split',88,24,24,14,'elevated','outline',10,4,4,8,'strong','strong',1,'underline','top',true,'16/10','cinematic',0.92,1.14,0.88,'spacious',1.12,'underlined',52,1,'floating','luxury','deep','gold-line','high','subtle',220,3,1.01),
('ivory-minimal','Ivory Minimal','Clean • Calm • Timeless','#F7F5F0','#FFFFFF','#343D3A','#A78B6A','#292E2C','#7A7F7B','Inter','Inter',15,1.26,'balanced','centered','stacked',4,'stacked',80,16,18,10,'flat','outline',8,8,8,8,'none','subtle',1,'underline','top',true,'1/1','bright',0.96,0.98,1.06,'spacious',1.10,'underlined',48,1,'floating','minimal','clean','none','medium','minimal',140,0,1.00),
('urban-slate','Urban Slate','Metropolitan • Structured • Strong','#E9EDF0','#F9FAFB','#3F4C55','#6E8391','#222B31','#707C84','Segoe UI','Segoe UI',14,1.24,'wide','modular','split-left',4,'split',52,12,14,10,'outlined','solid',10,8,8,8,'none','strong',1,'tabs','side',true,'4/3','crisp',0.94,1.08,1.00,'compact',0.90,'outlined',44,1,'above','urban-structured','crisp','grid','high','fast',120,1,1.005),
('royal-indigo','Royal Indigo','Elegant • Formal • Distinctive','#F2EFF8','#FFFFFF','#4B3769','#8460A8','#30283B','#786E82','Inter','Georgia',15,1.42,'balanced','formal','split-right',3,'split',74,18,20,12,'elevated','solid',18,14,12,16,'soft','subtle',1,'pill','top',true,'4/3','soft',0.98,1.02,1.02,'balanced',1.02,'outlined',50,1,'above','refined-formal','soft','accent-line','medium','subtle',180,2,1.01),
('ocean-professional','Ocean Professional','Trust • Clear • Professional','#EDF5F9','#FFFFFF','#24566F','#3E88A7','#1F3743','#6C7E87','Inter','Inter',15,1.30,'balanced','structured','split-left',4,'split',58,14,16,11,'outlined','solid',14,10,10,12,'soft','subtle',1,'tabs','top',true,'4/3','cool-clean',0.96,1.04,1.04,'balanced',0.98,'outlined',46,1,'above','professional','clean','none','high','fast',140,1,1.005),
('fresh-teal','Fresh Teal','Fresh • Friendly • Contemporary','#E9F6F4','#FFFFFF','#17665E','#32A092','#223F3B','#6E8581','Inter','Inter',15,1.30,'balanced','friendly','stacked',3,'stacked',66,16,18,12,'soft','pill',22,22,16,20,'soft','none',0,'pill','top',true,'1/1','fresh',1.08,1.02,1.05,'balanced',1.00,'filled',50,0,'floating','fresh-friendly','soft','bubble','medium','soft',180,2,1.015),
('olive-organic','Olive Organic','Earthy • Healthy • Natural','#F2F3E8','#FFFDF7','#55633C','#929E52','#303628','#74786C','Georgia','Georgia',15,1.36,'balanced','organic','split-left',3,'split',76,20,20,12,'soft','solid',20,16,14,20,'soft','subtle',1,'pill','top',true,'4/3','earthy',0.98,0.98,1.02,'spacious',1.06,'filled',50,1,'above','organic','paper','leaf-line','medium','soft',200,3,1.01),
('sakura-soft','Sakura Soft','Soft • Friendly • Delightful','#FFF1F4','#FFFFFF','#875365','#E087A4','#49353C','#8D7880','Inter','Georgia',15,1.34,'balanced','soft-centered','stacked',2,'stacked',82,20,22,13,'soft','pill',24,24,18,22,'soft','none',0,'pill','top',true,'1/1','soft',0.94,0.96,1.08,'spacious',1.12,'filled',52,0,'floating','soft-delightful','airy','petal','low','soft',220,3,1.02),
('sunset-orange','Sunset Orange','Energetic • Warm • Conversion','#FFF1E8','#FFFDFC','#8A4528','#ED7A3E','#4A3025','#8D7164','Inter','Inter',14,1.28,'compact','conversion','split-left',4,'stacked',48,10,14,9,'outlined','solid',12,10,8,10,'strong','subtle',1,'tabs','top',true,'4/3','vivid',1.12,1.10,1.02,'compact',0.86,'filled',44,1,'above','energetic','punchy','stripe','high','fast',110,2,1.02),
('monochrome-studio','Monochrome Studio','Editorial • Bold • Minimal','#F2F2F2','#FFFFFF','#202020','#5B5B5B','#171717','#747474','Arial','Arial',14,1.34,'wide','editorial','stacked',4,'split',68,14,16,10,'flat','outline',2,2,2,2,'none','strong',1,'underline','top',true,'3/2','monochrome',0.20,1.16,1.02,'balanced',0.96,'underlined',46,1,'floating','editorial-bold','clean','rule','high','minimal',100,0,1.00),
('glass-future','Glass Future','Glass • Airy • Futuristic','#E8F0F3','#F8FCFD','#315A67','#7BA7B5','#20333A','#687D84','Inter','Inter',15,1.32,'wide','floating','fullbleed',3,'floating',84,22,22,13,'glass','pill',26,22,18,24,'soft','subtle',1,'floating','top',true,'16/9','cool-clean',0.92,1.02,1.08,'spacious',1.08,'glass',52,1,'floating','futuristic','glass','glow-line','medium','fluid',260,4,1.02),
('neo-digital','Neo Digital','Tech • Dark • Dynamic','#10161B','#182028','#273746','#58B6A9','#F2F7F6','#93A4A5','Segoe UI','Segoe UI',14,1.28,'wide','modular','split-left',4,'split',48,10,12,9,'glass','solid',10,8,8,8,'glow','strong',1,'tabs','side',true,'16/10','tech',0.90,1.16,0.94,'compact',0.84,'filled',44,1,'floating','tech-dynamic','deep','grid-glow','high','dynamic',240,4,1.025),
('classic-editorial','Classic Editorial','Editorial • Refined • Story-led','#F6F1E7','#FFFCF6','#3C3A33','#9A6D48','#282720','#7A756B','Times New Roman','Times New Roman',16,1.52,'wide','editorial','split-right',2,'stacked',92,24,22,12,'flat','outline',2,0,0,0,'none','strong',1,'underline','top',false,'3/2','editorial',0.88,1.06,1.01,'spacious',1.14,'underlined',50,1,'floating','classic-editorial','paper','rule','medium','minimal',120,0,1.00),
('luxury-restaurant','Luxury Restaurant','Sophisticated • Premium • Hospitality','#EEEAE3','#FAF8F3','#2B2B29','#A98955','#1D1D1B','#756E64','Georgia','Georgia',15,1.48,'wide','hospitality','fullbleed',2,'split',96,24,26,14,'elevated','outline',12,6,6,8,'strong','subtle',1,'underline','top',true,'16/10','cinematic',0.90,1.10,0.92,'spacious',1.16,'outlined',54,1,'floating','luxury-hospitality','refined','champagne-line','high','subtle',240,3,1.01)
)
insert into private.theme_profiles(id,name,tag,profile,updated_at)
select id,name,tag,
jsonb_build_object(
 'schemaVersion',3,'id',id,'name',name,'tag',tag,
 'layout',jsonb_build_object('width',width,'macro',macro,'hero',hero,'menuColumns',menu_cols,'checkout',checkout_mode),
 'composition',jsonb_build_object('sectionGap',section_gap,'cardGap',card_gap,'contentAlign',case when macro in ('centered','soft-centered') then 'center' else 'left' end,'cardOrientation',case when macro in ('editorial','conversion') then 'horizontal' else 'vertical' end),
 'colors',jsonb_build_object('background',bg,'panel',panel,'primary',pri,'accent',accent,'text',textc,'muted',muted),
 'typography',jsonb_build_object('family',body_font,'headingFamily',heading_font,'size',base_size,'headingScale',heading_scale,'bodyWeight',400,'headingWeight',case when macro in ('editorial','hospitality','immersive') then 600 else 700 end,'lineHeight',case when density_mode='compact' then 1.38 else 1.5 end,'letterSpacing',0),
 'spacing',jsonb_build_object('section',section_gap,'gap',card_gap,'card',card_pad,'control',control_pad),
 'components',jsonb_build_object('card',card_style,'button',button_style,'cardPadding',card_pad,'buttonHeight',form_height),
 'radius',jsonb_build_object('card',card_radius,'button',button_radius,'input',input_radius,'image',image_radius),
 'effects',jsonb_build_object('shadow',shadow_style,'border',border_style,'borderWidth',border_width,'blur',case when card_style='glass' then 16 else 0 end),
 'navigation',jsonb_build_object('style',nav_style,'position',nav_position,'sticky',nav_sticky,'height',case when density_mode='compact' then 56 else 68 end),
 'images',jsonb_build_object('aspect',img_aspect,'treatment',img_treatment,'saturation',saturation,'contrast',contrastv,'brightness',brightness,'fit','cover'),
 'density',jsonb_build_object('mode',density_mode,'scale',density_scale),
 'forms',jsonb_build_object('style',form_style,'height',form_height,'borderWidth',form_border,'label',label_style,'focus',case when form_style='underlined' then 'underline' else 'ring' end),
 'visual',jsonb_build_object('character',visual_character,'surface',surface,'decoration',decoration,'contrast',contrast_mode),
 'motion',jsonb_build_object('mode',motion_mode,'duration',duration,'easing',case when motion_mode='dynamic' then 'cubic-bezier(.2,.8,.2,1)' else 'ease' end,'hoverLift',hover_lift,'hoverScale',hover_scale)
),now()
from x
on conflict(id) do update set name=excluded.name,tag=excluded.tag,profile=excluded.profile,updated_at=now();

create or replace function private.site_settings_expand_theme_profile()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id text;
  v_profile jsonb;
  v_draft_id text;
begin
  v_id := new.design_system#>>'{published,theme,id}';
  if v_id is not null then
    select profile into v_profile from private.theme_profiles where id=v_id;
    if v_profile is not null then
      new.design_system := jsonb_set(coalesce(new.design_system,'{}'::jsonb),'{published,theme}',v_profile,true);
      new.admin_design := jsonb_set(coalesce(new.admin_design,'{}'::jsonb),'{_system,designV2,theme}',v_profile,true);
      new.kds_design := jsonb_set(coalesce(new.kds_design,'{}'::jsonb),'{_system,designV2,theme}',v_profile,true);
    end if;
  end if;
  v_draft_id := new.design_system#>>'{draft,theme,id}';
  if v_draft_id is not null then
    select profile into v_profile from private.theme_profiles where id=v_draft_id;
    if v_profile is not null then
      new.design_system := jsonb_set(new.design_system,'{draft,theme}',v_profile,true);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists site_settings_theme_profile_expand on public.site_settings;
create trigger site_settings_theme_profile_expand
before update on public.site_settings
for each row execute function private.site_settings_expand_theme_profile();

update public.site_settings set updated_at=now() where id=1;
