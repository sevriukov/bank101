-- Э88. Витрина «матрёшки» как материализованное представление: оригинал оцифровки (m.dig_cell, m.dig_state) не меняется,
-- все преобразования записаны здесь формулой и в m.dig_scale числами. После смены параметров в m.dig_scale:
--   выполнить этот файл заново (пересоздаёт m.dig_base и представление).
-- Правила: точки — без ликвидируемых банков и без точек с неизвестным делением на рубли и валюту;
--   остаток: (x − среднее) / отклонение; оборот: (ln(1 + x) − среднее) / отклонение; обрезка на ±clip; умножение на weight;
--   неиспользуемая координата = 0; у точек без оборотов координаты оборотов = 0 (среднее).
-- Время и размер — отдельные столбцы, в векторы не входят.
-- Счёт: вектор точки = вектор «нулевого банка» (все значения равны нулю, после масштабирования) + отклонения по имеющимся значениям.
\set ON_ERROR_STOP on
\timing on
set work_mem = '8GB';
set max_parallel_workers_per_gather = 8;
drop materialized view if exists m.dig_view cascade; drop table if exists m.dig_base; drop view if exists m.dig_long;   -- cascade: зависимые m.dig_month_mean, m.dig_view_rel, m.dig_move* пересоздаются в 108_moves.sql
create view m.dig_long as   -- оригинал в длинной форме по координатам, в долях валюты баланса; только ненулевые значения
select c.regn, c.dat, (a.cell * 6 + u.k)::int coord, (u.val / bd.assets * case when u.k < 2 and a.side = 'P' then -1 else 1 end)::double precision raw
  from m.dig_cell c join m.dig_axis a using (ch_id, srok) join m.bank_date bd using (regn, dat)
       cross join lateral (values (0, c.v_rub), (1, c.v_fx), (2, c.td_rub), (3, c.td_fx), (4, c.tc_rub), (5, c.tc_fx)) u(k, val)
 where bd.assets > 0 and u.val <> 0;
create table m.dig_base as
with z as (select coord, coord % 6 < 2 is_bal, (case when used then weight * greatest(-clip, least(clip, -mean / std)) else 0 end)::real z0 from m.dig_scale)
select (array_agg(z0 order by coord))::vector(966) z0,
       (array_agg(case when is_bal then z0 else 0 end order by coord))::vector(966) z0_noturn,
       (array_agg(z0 order by coord) filter (where is_bal))::vector(322) b0,
       (array_agg(z0 order by coord) filter (where not is_bal))::vector(644) t0,
       (array_agg(0::real order by coord) filter (where not is_bal))::vector(644) t0_noturn
  from z;
create materialized view m.dig_view as
with d as (
  select regn, dat,
         ('{' || coalesce(string_agg((coord + 1) || ':' || dz::real, ','), '') || '}/966')::sparsevec dv,
         ('{' || coalesce(string_agg(((coord / 6) * 2 + coord % 6 + 1) || ':' || dz::real, ',') filter (where coord % 6 < 2), '') || '}/322')::sparsevec db,
         ('{' || coalesce(string_agg(((coord / 6) * 4 + coord % 6 - 1) || ':' || dz::real, ',') filter (where coord % 6 >= 2), '') || '}/644')::sparsevec dt
    from (select l.regn, l.dat, l.coord,
                 sc.weight * (greatest(-sc.clip, least(sc.clip, ((case when l.coord % 6 < 2 then l.raw else ln(1 + greatest(l.raw, 0)) end) - sc.mean) / sc.std))
                            - greatest(-sc.clip, least(sc.clip, -sc.mean / sc.std))) dz
            from m.dig_long l join m.dig_scale sc using (coord) where sc.used) q
   where dz::real <> 0 group by 1, 2)
select s.regn, s.dat, ln(s.assets)::real lna, (extract(year from s.dat) - 1998 + (extract(month from s.dat) - 1) / 12.0)::real t, s.turn_known,
       ((case when s.turn_known then b.z0 else b.z0_noturn end) + coalesce(d.dv, '{}/966'::sparsevec)::vector(966))::vector(966) as v,
       (b.b0 + coalesce(d.db, '{}/322'::sparsevec)::vector(322))::vector(322) as v_bal,
       ((case when s.turn_known then b.t0 else b.t0_noturn end) + coalesce(d.dt, '{}/644'::sparsevec)::vector(644))::vector(644) as v_turn
  from m.dig_state s cross join m.dig_base b left join d using (regn, dat)
 where not s.after_revoke and s.split_known;
create unique index on m.dig_view (regn, dat);
create index on m.dig_view (dat);
set maintenance_work_mem = '8GB'; set max_parallel_maintenance_workers = 0;   -- параллельная сборка требует общей памяти, которой в контейнере базы нет
create index dig_view_v_hnsw on m.dig_view using hnsw (v vector_cosine_ops);
create index dig_view_bal_hnsw on m.dig_view using hnsw (v_bal vector_cosine_ops);
create index dig_view_turn_hnsw on m.dig_view using hnsw (v_turn vector_cosine_ops);
analyze m.dig_view;
select count(*) points from m.dig_view;
