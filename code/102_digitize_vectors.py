#!/usr/bin/env python3
"""Э87. Оцифровка, шаг 2: плотный вектор точки «банк на дату» — 968 координат.
  0…965   161 ячейка (лист × срочность) × 6 чисел в порядке: остаток руб., остаток вал., оборот Дт руб., Дт вал., Кт руб., Кт вал.
          Остаток — доля в валюте баланса банка (знак приведён к стороне листа: обычная статья положительна);
          оборот — отношение к валюте баланса (сколько раз статья обернулась за месяц). Ничего не обрезается.
  966     размер: натуральный логарифм валюты баланса (тыс. руб.)
  967     время: лет от 1 января 1998 г.
Точки: все пары «банк — дата» с положительной валютой баланса. Родительские узлы не хранятся (сумма листьев).
Результат: m.dig_state (regn, dat, assets, v vector(968)); файл hsdr_2026/cache/dig_state.npz; описание осей m.dig_coord."""
import io, subprocess, numpy as np, pandas as pd
PSQL = ["psql", "-h", "127.0.0.1", "-p", "5433", "-U", "postgres", "bank"]
def q(s, names): return pd.read_csv(io.StringIO(subprocess.run(PSQL + ["-At", "-F", "\t", "-c", s], capture_output=True, text=True, check=True).stdout), sep="\t", header=None, names=names)
AX = q("select cell, ch_id, srok, replace(name, E'\\t', ' '), side from m.dig_axis order by cell", ["cell", "ch", "srok", "name", "side"]); NC = len(AX); cell = {(c, s): i for i, c, s in zip(AX.cell, AX.ch, AX.srok)}; sgn = np.where(AX.side == "A", 1.0, -1.0)
BD = q("select regn, dat, assets from m.bank_date where assets > 0 order by regn, dat", ["regn", "dat", "assets"]); N = len(BD); row = {(r, d): i for i, (r, d) in enumerate(zip(BD.regn, BD.dat))}
V = np.zeros((N, NC * 6 + 2), np.float32); FAC = ["остаток руб.", "остаток вал.", "оборот Дт руб.", "оборот Дт вал.", "оборот Кт руб.", "оборот Кт вал."]
proc = subprocess.Popen(PSQL + ["-At", "-F", "\t", "-c", "select regn, dat, ch_id, srok, v_rub, v_fx, td_rub, td_fx, tc_rub, tc_fx from m.dig_cell"], stdout=subprocess.PIPE, text=True); n = 0; skipped = 0
for ch in pd.read_csv(proc.stdout, sep="\t", header=None, names=["regn", "dat", "ch", "srok", "a", "b", "c", "d", "e", "f"], chunksize=2_000_000):
    i = np.array([row.get(k, -1) for k in zip(ch.regn, ch.dat)]); j = np.array([cell[k] for k in zip(ch.ch, ch.srok)]); ok = i >= 0; skipped += int((~ok).sum()); i, j = i[ok], j[ok]; a = BD.assets.values[i]; vals = ch[["a", "b", "c", "d", "e", "f"]].values[ok].astype(np.float64)
    vals[:, :2] *= sgn[j][:, None]; vals /= a[:, None]
    for k in range(6): V[i, j * 6 + k] = vals[:, k]
    n += len(ch); print("прочитано", n, flush=True)
V[:, -2] = np.log(BD.assets.values); d = pd.to_datetime(BD.dat); V[:, -1] = ((d.dt.year - 1998) + (d.dt.month - 1) / 12).values
print("точек", N, "| координат", V.shape[1], "| строк вне точек (нет положительной валюты баланса)", skipped, "| ненулевых значений, %", round(100 * float((V[:, :-2] != 0).mean()), 2), flush=True)
np.savez_compressed("hsdr/cache/dig_state.npz", V=V, regn=BD.regn.values, dat=BD.dat.values.astype(str), assets=BD.assets.values, cell_ch=AX.ch.values, cell_srok=AX.srok.values, cell_side=AX.side.values.astype(str), cell_name=AX.name.values.astype(str), facets=np.array(FAC))
coord = [[c * 6 + k, int(AX.ch[c]), int(AX.srok[c]), AX.side[c], AX.name[c], FAC[k]] for c in range(NC) for k in range(6)] + [[NC * 6, None, None, None, "размер: ln валюты баланса", ""], [NC * 6 + 1, None, None, None, "время: лет от 01.01.1998", ""]]
buf = io.StringIO(); pd.DataFrame(coord).to_csv(buf, header=False, index=False, float_format="%.0f")
subprocess.run(PSQL + ["-q", "-c", "create extension if not exists vector; drop table if exists m.dig_coord; create table m.dig_coord (coord int, ch_id int, srok int, side text, name text, facet text); drop table if exists m.dig_state; create table m.dig_state (regn int, dat date, assets numeric, v vector(968))"], check=True); subprocess.run(PSQL + ["-q", "-c", "\\copy m.dig_coord from stdin csv"], input=buf.getvalue(), text=True, check=True)
for a in range(0, N, 10000):
    b = min(N, a + 10000); buf = io.StringIO()
    for r, dd, s, v in zip(BD.regn[a:b], BD.dat[a:b], BD.assets[a:b], V[a:b]): buf.write(f"{r}\t{dd}\t{s}\t[" + ",".join("0" if x == 0 else f"{x:.6g}" for x in v) + "]\n")
    subprocess.run(PSQL + ["-q", "-c", "\\copy m.dig_state from stdin with (format text)"], input=buf.getvalue(), text=True, check=True)
subprocess.run(PSQL + ["-q", "-c", "alter table m.dig_state add primary key (regn, dat); analyze m.dig_state"], check=True); print("m.dig_state записана: ", N, "точек"); print("готово")
