import csv
import random
import sys
from datetime import datetime, timedelta

rows = int(sys.argv[1]) if len(sys.argv) > 1 else 200_000
out = sys.argv[2] if len(sys.argv) > 2 else "sales.csv"

rnd = random.Random(42)
regions = ["Москва", "Санкт-Петербург", "Казань", "Новосибирск", "Екатеринбург", "Краснодар"]
categories = {"electronics": 9000, "grocery": 900, "clothes": 3500, "books": 700, "home": 2500, "sport": 4000}
payments = ["card", "cash", "sbp"]
start = datetime(2025, 1, 1)
seconds_in_year = 365 * 24 * 3600

with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["tx_id", "tx_time", "region", "category", "amount", "quantity", "payment_type"])
    for i in range(1, rows + 1):
        cat = rnd.choice(list(categories))
        qty = rnd.choices([1, 2, 3, 4, 5], weights=[60, 20, 10, 6, 4])[0]
        amount = round(rnd.lognormvariate(0, 0.5) * categories[cat] * qty, 2)
        ts = start + timedelta(seconds=rnd.randrange(seconds_in_year))
        w.writerow([i, ts.strftime("%Y-%m-%d %H:%M:%S"), rnd.choice(regions), cat, amount, qty, rnd.choice(payments)])
