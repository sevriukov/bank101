#!/usr/bin/env python3
"""Наглядная сводка пробелов базы: рисунки по таблицам 01 и 03. Запуск из этой папки после build_gaps.sql."""
import pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt, matplotlib.dates as md
BLUE, ORANGE, INK, MUTED, GRID, SURF = "#2a78d6", "#eb6834", "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11, "figure.dpi": 150, "figure.facecolor": SURF, "axes.facecolor": SURF, "axes.edgecolor": GRID, "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8, "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False, "xtick.color": MUTED, "ytick.color": MUTED, "axes.labelcolor": MUTED, "text.color": INK, "axes.titleweight": "bold", "axes.titlesize": 13, "axes.titlelocation": "left"})
D = pd.read_csv("01_охват_по_датам.csv"); D.columns = ["dat", "have", "ok", "must", "miss", "note"]; D["dat"] = pd.to_datetime(D.dat)
# 1. должно быть и есть (среди действовавших); отдельно — всего в базе, включая отчёты после окончания лицензии
D["have_act"] = D.must - D.miss
fig, ax = plt.subplots(figsize=(11, 4.8)); ax.set_axisbelow(True); ax.plot(D.dat, D.have, color="#9a9992", lw=1.2, ls=(0, (4, 2)), label="всего отчётов в базе (включая банки после окончания лицензии)")
ax.plot(D.dat, D.must, color=ORANGE, lw=2, label="должно быть: банк действовал на дату"); ax.plot(D.dat, D.have_act, color=BLUE, lw=2, label="есть: отчёт действовавшего банка")
ax.fill_between(D.dat, D.have_act, D.must, color=ORANGE, alpha=0.15, lw=0)
ax.annotate("март — май 1998:\nмесяцев нет совсем", (pd.Timestamp("1998-04-01"), 40), xytext=(pd.Timestamp("1999-06-01"), 520), arrowprops=dict(arrowstyle="-", color=MUTED), fontsize=9.5, color=MUTED)
ax.annotate("2006–2009: нет отчётов\nу 29–311 банков на дату", (pd.Timestamp("2007-03-01"), 1060), xytext=(pd.Timestamp("2004-01-01"), 700), arrowprops=dict(arrowstyle="-", color=MUTED), fontsize=9.5, color=MUTED)
ax.annotate("до 2006 г. в базе есть и отчёты\nбанков с уже прекращённой лицензией", (pd.Timestamp("2002-06-01"), 1700), xytext=(pd.Timestamp("2008-01-01"), 1560), arrowprops=dict(arrowstyle="-", color=MUTED), fontsize=9.5, color=MUTED)
ax.set_ylim(0, 1900); ax.set_ylabel("банков"); ax.set_title("Сколько балансов должно быть и сколько есть, по отчётным датам"); ax.legend(frameon=False, loc="lower center", bbox_to_anchor=(0.5, 0.02), fontsize=9.5); ax.xaxis.set_major_locator(md.YearLocator(2)); ax.xaxis.set_major_formatter(md.DateFormatter("%Y")); ax.grid(axis="x", visible=False)
plt.tight_layout(); plt.savefig("рис1_должно_быть_и_есть.png"); plt.close()
# 2. нет отчёта, по датам
fig, ax = plt.subplots(figsize=(11, 3.8)); ax.set_axisbelow(True); ax.bar(D.dat, D.miss, width=25, color=ORANGE, lw=0); ax.set_ylabel("банков без отчёта"); ax.set_title("Банк действовал, а отчёта в базе нет — по отчётным датам"); ax.xaxis.set_major_locator(md.YearLocator(2)); ax.xaxis.set_major_formatter(md.DateFormatter("%Y")); ax.grid(axis="x", visible=False)
plt.tight_layout(); plt.savefig("рис2_нет_отчёта_по_датам.png"); plt.close()
# 3. виды недостатков
S = pd.read_csv("03_сводка_видов.csv"); S.columns = ["kind", "n", "banks", "d0", "d1"]; S = S[~S.kind.str.contains("взято из файлов")].sort_values("n")
S["kind"] = S.kind.str.replace("нет деления остатков на рубли и валюту: в обоих источниках валюта записана в рублёвый столбец", "нет деления на рубли и валюту (валюта в рублёвом столбце)")
fig, ax = plt.subplots(figsize=(12.5, 5.4)); ax.set_axisbelow(True); b = ax.barh(S.kind, S.n, color=BLUE, height=0.62, lw=0)
for r, v in zip(b, S.n): ax.text(v + S.n.max() * 0.01, r.get_y() + r.get_height() / 2, f"{v:,}".replace(",", " "), va="center", fontsize=10, color=INK)
ax.set_xlim(0, S.n.max() * 1.12); fig.suptitle("Известные недостатки базы: число случаев по видам", x=0.02, ha="left", fontweight="bold", fontsize=13); ax.grid(axis="y", visible=False); ax.tick_params(axis="y", colors=INK)
plt.tight_layout(); plt.savefig("рис3_виды_недостатков.png"); plt.close(); print("готово")
