#!/usr/bin/env python3
"""
NUR Sync Status SVG Renderer - 横向时间轴 + 圆点（状态图标右侧）
"""

import json
import sys
from datetime import datetime, timedelta, timezone

# -------------------------------
# 数据处理函数
# -------------------------------


def parse_iso_datetime(dt_str):
    try:
        dt_str = dt_str.replace("Z", "+00:00")
        return datetime.fromisoformat(dt_str)
    except ValueError:
        return None


def filter_valid_history(history):
    valid_history = []
    for entry in history:
        ts_str = entry.get("timestamp")
        if isinstance(ts_str, str):
            ts_obj = parse_iso_datetime(ts_str)
            if ts_obj:
                valid_history.append(
                    {
                        "timestamp_str": ts_str,
                        "timestamp_obj": ts_obj,
                        "fork_rev": entry.get("fork_rev"),
                        "official_rev": entry.get("official_rev"),
                        "status": entry.get("status"),
                        "phase": entry.get("phase"),
                    }
                )
    valid_history.sort(key=lambda x: x["timestamp_obj"])
    return valid_history


def get_latest_entry(valid_history):
    for entry in reversed(valid_history):
        if entry["phase"] != "initial":
            return entry
    return None


def get_last_days_data(valid_history, days_to_show=7):
    now = datetime.now(timezone.utc)
    last_days = []
    for i in range(days_to_show):
        day = (now - timedelta(days=i)).date()
        day_entries = [
            e
            for e in valid_history
            if e["phase"] != "initial" and e["timestamp_obj"].date() == day
        ]
        last_days.append((day, day_entries))
    return last_days[::-1]


# -------------------------------
# SVG 生成函数
# -------------------------------


def generate_svg_content(latest_entry, last_days, days_to_show):
    # 布局参数
    header_height = 160
    footer_height = 80
    line_height = 30
    circle_radius = 8
    circle_margin = 16
    label_width = 140
    left_padding = 30

    # SVG 尺寸计算
    max_commits = max((len(entries) for _, entries in last_days), default=1)
    grid_width = max_commits * (circle_radius * 2 + circle_margin)
    width = max(750, left_padding + label_width + grid_width + 50)
    height = header_height + len(last_days) * line_height + footer_height + 20

    svg_content = [
        f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg" font-family="Segoe UI, sans-serif">',
        # 定义渐变和阴影
        "<defs>",
        '<linearGradient id="syncedGrad" x1="0" y1="0" x2="0" y2="1">',
        '<stop offset="0%" stop-color="#2ecc71"/>',
        '<stop offset="100%" stop-color="#27ae60"/>',
        "</linearGradient>",
        '<linearGradient id="unsyncedGrad" x1="0" y1="0" x2="0" y2="1">',
        '<stop offset="0%" stop-color="#e74c3c"/>',
        '<stop offset="100%" stop-color="#c0392b"/>',
        "</linearGradient>",
        '<filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">',
        '<feDropShadow dx="1" dy="1" stdDeviation="1" flood-color="#888"/>',
        "</filter>",
        "</defs>",
        # 背景
        f'<rect width="100%" height="100%" fill="#f5f7fa"/>',
        # 标题
        '<text x="30" y="35" font-size="24" font-weight="bold" fill="#2c3e50">NUR Sync Status</text>',
    ]

    # 最新状态
    if latest_entry:
        status_color = "#27ae60" if latest_entry["status"] == "synced" else "#e74c3c"
        grad_id = "syncedGrad" if latest_entry["status"] == "synced" else "unsyncedGrad"
        svg_content.append(
            '<text x="30" y="70" font-size="16" font-weight="bold" fill="#2c3e50">Latest:</text>'
        )
        svg_content.append(
            f'<circle cx="100" cy="62" r="10" fill="url(#{grad_id})" stroke="#2c3e50" stroke-width="1" filter="url(#shadow)"/>'
        )
        svg_content.append(
            f'<circle cx="100" cy="62" r="4" fill="white" opacity="0.4"/>'
        )
        svg_content.append(
            f'<text x="120" y="70" font-size="16" font-weight="bold" fill="{status_color}">{latest_entry["status"].title()}</text>'
        )
        svg_content.append(
            f'<text x="30" y="95" font-size="14" fill="#7f8c8d">📅 {latest_entry["timestamp_str"]}</text>'
        )
        svg_content.append(
            f'<text x="30" y="120" font-size="14" fill="#7f8c8d">🔄 Fork: {latest_entry["fork_rev"][:10]}... | 📦 Official: {latest_entry["official_rev"][:10]}...</text>'
        )

    # 分割线
    svg_content.append(
        f'<line x1="{left_padding}" y1="140" x2="{width-left_padding}" y2="140" stroke="#bdc3c7" stroke-width="1"/>'
    )

    # 横向时间轴 + 圆点
    y_start = 160
    for idx, (day, entries) in enumerate(last_days):
        y = y_start + idx * line_height
        # 左侧日期美化
        day_label = day.strftime("%Y-%m-%d")
        svg_content.append(
            f'<text x="{left_padding}" y="{y+5}" font-size="14" fill="#2c3e50">{day_label}:</text>'
        )

        x_start = left_padding + label_width
        if entries:
            for j, entry in enumerate(entries):
                cx = x_start + j * (circle_radius * 2 + circle_margin) + circle_radius
                grad = "syncedGrad" if entry["status"] == "synced" else "unsyncedGrad"
                # 圆点
                svg_content.append(
                    f'<circle cx="{cx}" cy="{y}" r="{circle_radius}" fill="url(#{grad})" stroke="#2c3e50" stroke-width="1" filter="url(#shadow)"/>'
                )
                # 高光
                svg_content.append(
                    f'<circle cx="{cx}" cy="{y-2}" r="3" fill="white" opacity="0.4"/>'
                )
                # 连接线
                if j > 0:
                    prev_cx = (
                        x_start
                        + (j - 1) * (circle_radius * 2 + circle_margin)
                        + circle_radius
                    )
                    svg_content.append(
                        f'<line x1="{prev_cx}" y1="{y}" x2="{cx}" y2="{y}" stroke="#bdc3c7" stroke-width="2"/>'
                    )
            # 最后一个圆点图标放在右侧
            last_entry = entries[-1]
            cx_last = (
                x_start
                + (len(entries) - 1) * (circle_radius * 2 + circle_margin)
                + circle_radius
            )
            icon = "✅" if last_entry["status"] == "synced" else "❌"
            svg_content.append(
                f'<text x="{cx_last + circle_radius + 6}" y="{y + 4}" font-size="12" text-anchor="start" fill="#2c3e50">{icon}</text>'
            )
        else:
            cx = x_start + circle_radius
            svg_content.append(
                f'<circle cx="{cx}" cy="{y}" r="{circle_radius}" fill="#ecf0f1" stroke="#bdc3c7" stroke-width="1"/>'
            )

    # Legend
    legend_y = height - 40
    legend_x = left_padding
    svg_content.append(
        f'<circle cx="{legend_x+8}" cy="{legend_y+8}" r="8" fill="url(#syncedGrad)" stroke="#2c3e50" stroke-width="1"/>'
    )
    svg_content.append(
        f'<text x="{legend_x+22}" y="{legend_y+12}" font-size="14" fill="#2c3e50">Synced</text>'
    )
    svg_content.append(
        f'<circle cx="{legend_x+120}" cy="{legend_y+8}" r="8" fill="url(#unsyncedGrad)" stroke="#2c3e50" stroke-width="1"/>'
    )
    svg_content.append(
        f'<text x="{legend_x+136}" y="{legend_y+12}" font-size="14" fill="#2c3e50">Unsynced</text>'
    )
    svg_content.append(
        f'<circle cx="{legend_x+240}" cy="{legend_y+8}" r="8" fill="#ecf0f1" stroke="#bdc3c7" stroke-width="1"/>'
    )
    svg_content.append(
        f'<text x="{legend_x+256}" y="{legend_y+12}" font-size="14" fill="#2c3e50">No Data</text>'
    )

    svg_content.append("</svg>")
    return "\n".join(svg_content)


# -------------------------------
# 主函数
# -------------------------------


def main():
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print(
            f"Usage: {sys.argv[0]} <input_json_file> <output_svg_file> [days_to_show=7]"
        )
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    days_to_show = int(sys.argv[3]) if len(sys.argv) >= 4 else 7

    with open(input_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    history = data.get("history", [])
    valid_history = filter_valid_history(history)
    latest_entry = get_latest_entry(valid_history)
    last_days = get_last_days_data(valid_history, days_to_show)

    svg_content = generate_svg_content(latest_entry, last_days, days_to_show)

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(svg_content)

    print(f"Successfully written SVG to {output_file}")


if __name__ == "__main__":
    main()
