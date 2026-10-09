#!/usr/bin/env python3
"""Э88. Витрина для поиска соседей поверх оцифровки (m.dig_state): масштабы координат выровнены, расстояние — косинусное.
Правила (согласованы с автором 6 октября 2026 г.):
  - время и размер в вектор расстояния не входят, хранятся отдельными столбцами;
  - остатки (322 координаты): стандартизация (вычесть среднее, разделить на стандартное отклонение);
  - обороты (644 координаты): логарифм ln(1 + x), затем та же стандартизация. Способ «медиана и межквартильный размах»
    неприменим: у большинства координат больше трёх четвертей значений — нули, размах равен нулю;
  - ликвидируемые банки (отчётность после отзыва лицензии) и точки без деления остатков на рубли и валюту в витрину
    не входят и в расчёте масштабов не участвуют; в m.dig_state они остаются;
  - после стандартизации значения обрезаются на ±5; блок остатков умножается на множитель, уравнивающий средний квадрат
    длины блока остатков и блока оборотов (около корня из двух);
  - точки без оборотов (остатки восстановлены): координаты оборотов ставятся в ноль, то есть в среднее; признак turn_known.
  - масштабы считаются по всей базе сразу, без деления на периоды.
Результат: m.dig_live (regn, dat, lna, t, turn_known, v vector(966), v_bal vector(322), v_turn vector(644)),
  m.dig_scale (параметры масштаба каждой координаты), индексы HNSW по косинусу; файл cache/dig_live.npz."""
import io, subprocess, numpy as np, pandas as pd
PSQL = ["psql", "-h", "127.0.0.1", "-p", "5433", "-U", "postgres", "bank"]; C = "hsdr/cache/"
z = np.load(C + "dig_state.npz", allow_pickle=True); V = z["V"]; regn = z["regn"]; dat = z["dat"]; N = len(V)
fl = pd.read_csv(io.StringIO(subprocess.run(PSQL + ["-At", "-F", "\t", "-c", "select regn, dat, after_revoke, split_known, turn_known from m.dig_state order by regn, dat"], capture_output=True, text=True, check=True).stdout), sep="\t", header=None, names=["regn", "dat", "a", "s", "t"])
assert (fl.regn.values == regn).all() and (fl.dat.values == dat).all(); live = ((fl.a == "f") & (fl.s == "t")).values; tk = (fl.t == "t").values[live]
W = V[live, :966].astype(np.float64).reshape(-1, 161, 6); lna = V[live, 966]; tt = V[live, 967]; R = regn[live]; Dt = dat[live]; n = len(W)
isb = np.zeros(966, bool); isb.reshape(161, 6)[:, :2] = True; X = W.reshape(n, 966); X[:, ~isb] = np.log1p(np.maximum(X[:, ~isb], 0))          # обороты: ln(1 + x); лакуны остаются NaN
mu = np.nanmean(X, 0); sd = np.nanstd(X, 0); used = sd > 1e-9; Z = np.where(used, (X - mu) / np.where(used, sd, 1), 0.0); Z[np.isnan(Z)] = 0.0; zmax = float(np.abs(Z).max())
CLIP = 5.0; clipped = float((np.abs(Z) > CLIP).mean()); Z = np.clip(Z, -CLIP, CLIP)                                   # обрезка: редкая статья не должна определять всё сходство
wb = float(np.sqrt((Z[:, ~isb] ** 2).sum(1).mean() / (Z[:, isb] ** 2).sum(1).mean())); Z[:, isb] *= wb             # равный вклад остатков и оборотов в длину вектора
Z = Z.astype(np.float32); print("обрезка на ±5: затронуто значений, %", round(100 * clipped, 3), "| до обрезки наибольшее", round(zmax, 1), "| множитель блока остатков", round(wb, 4), "(при равном разбросе осей был бы 1,4142)", flush=True)
print("точек в витрине", n, "из", N, "| координат с ненулевым разбросом", int(used.sum()), "из 966 | точек без оборотов", int((~tk).sum()), "| наибольшее значение после масштабирования", round(float(np.abs(Z).max()), 1), "| 99,9 %:", round(float(np.quantile(np.abs(Z[::20]), 0.999)), 1), flush=True)
np.savez_compressed(C + "dig_live.npz", Z=Z, regn=R, dat=Dt, lna=lna, t=tt, turn_known=tk, is_balance=isb, mean=mu, std=sd, clip=CLIP, weight_balance=wb)
co = pd.read_csv(io.StringIO(subprocess.run(PSQL + ["-At", "-F", "\t", "-c", "select coord from m.dig_coord where coord < 966 order by coord"], capture_output=True, text=True, check=True).stdout), header=None)[0].values
buf = io.StringIO(); pd.DataFrame({"c": co, "k": np.where(isb, "остаток: стандартизация, обрезка ±5, множитель блока", "оборот: ln(1+x), стандартизация, обрезка ±5"), "m": mu, "s": sd, "u": used, "cl": CLIP, "w": np.where(isb, wb, 1.0)}).to_csv(buf, header=False, index=False)
subprocess.run(PSQL + ["-q", "-c", "create table if not exists m.dig_scale (coord int, rule text, mean double precision, std double precision, used boolean, clip double precision, weight double precision); truncate m.dig_scale"], check=True); subprocess.run(PSQL + ["-q", "-c", "\\copy m.dig_scale from stdin csv"], input=buf.getvalue(), text=True, check=True)
WRITE_TABLE = False          # витрина строится материализованным представлением (105_matview.sql); таблица m.dig_live больше не пишется

unit = lambda A: A / np.maximum(np.linalg.norm(A, axis=1, keepdims=True), 1e-12); dates = sorted(set(Dt)); rows = []
def recog(M, lag):
    r = []
    for k in range(6, len(dates) - lag, 12):
        a = np.flatnonzero(Dt == dates[k]); b = np.flatnonzero(Dt == dates[k + lag]); pa = pd.Series(a, index=R[a]); pb = pd.Series(np.arange(len(b)), index=R[b]); c = pa.index.intersection(pb.index)
        if len(c) < 50: continue
        S = unit(M[pa[c].values]) @ unit(M[b]).T; so = S[np.arange(len(c)), pb[c].values]; r.append(((S > so[:, None]).sum(1) == 0).mean())
    return round(float(np.mean(r)), 3)
for nm, M in (("все 966 координат", Z), ("только остатки (322)", Z[:, isb]), ("только обороты (644)", Z[:, ~isb])): rows.append([nm, recog(M, 1), recog(M, 12), recog(M, 60)]); print("узнавание себя:", rows[-1], flush=True)
n2 = Z ** 2; print("доля длины вектора: остатки", round(float(n2[:, isb].sum() / n2.sum()), 3), "| на 10 наибольших координат у медианной точки", round(float(np.median(np.sort(n2[::50], 1)[:, -10:].sum(1) / np.maximum(n2[::50].sum(1), 1e-12))), 3))
buf = io.StringIO(); pd.DataFrame(rows).to_csv(buf, header=False, index=False); subprocess.run(PSQL + ["-q", "-c", "drop table if exists m.dig_check; create table m.dig_check (vec text, self_1m numeric, self_1y numeric, self_5y numeric)"], check=True); subprocess.run(PSQL + ["-q", "-c", "\\copy m.dig_check from stdin csv"], input=buf.getvalue(), text=True, check=True); print("проверка записана")
