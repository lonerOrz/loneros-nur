#!/usr/bin/env python3
"""
NUR Sync Status SVG Renderer

This script generates an SVG image showing the status of NUR (Nix User Repository) sync operations.
"""

import json
import sys
from datetime import datetime, timedelta, timezone
from collections import defaultdict


def status_to_color(status):
    """Convert status string to color"""
    color_map = {
        "synced": "#4CAF50",    # Green
        "unsynced": "#F44336",  # Red
        "initial": "#9E9E9E",   # Gray
    }
    return color_map.get(status, "#795548")  # Brown for unknown


def parse_iso_datetime(dt_str):
    """Parse ISO 8601 datetime string to datetime object"""
    try:
        # Remove 'Z' and add '+00:00' for proper timezone parsing
        dt_str = dt_str.replace('Z', '+00:00')
        return datetime.fromisoformat(dt_str)
    except ValueError:
        # If parsing fails, return None
        return None


def filter_valid_history(history):
    """Filter and parse history entries, returning only valid ones"""
    valid_history = []
    for entry in history:
        timestamp_str = entry.get('timestamp')

        # Check if timestamp is a string and can be parsed
        if isinstance(timestamp_str, str):
            timestamp_obj = parse_iso_datetime(timestamp_str)
            if timestamp_obj is not None:
                valid_history.append({
                    'timestamp_str': timestamp_str,
                    'timestamp_obj': timestamp_obj,
                    'fork_rev': entry.get('fork_rev'),
                    'official_rev': entry.get('official_rev'),
                    'status': entry.get('status'),
                    'phase': entry.get('phase')
                })
    # Sort by timestamp to ensure order
    valid_history.sort(key=lambda x: x['timestamp_obj'])
    return valid_history


def get_latest_entry(valid_history):
    """Get the latest non-initial entry from history"""
    for entry in reversed(valid_history):  # Go through in reverse to find the most recent
        if entry['phase'] != 'initial':
            return entry
    return None


def get_last_days_data(valid_history, days_to_show=7):
    """Get data for the last specified number of days, including status details"""
    now = datetime.now(timezone.utc)
    last_days = []
    for i in range(days_to_show):
        day = (now - timedelta(days=i)).date()
        # Get entries for this day
        day_entries = [entry for entry in valid_history
                      if entry['phase'] != 'initial' and entry['timestamp_obj'].date() == day]
        last_days.append((day, day_entries))
    return last_days


def generate_svg_content(latest_entry, last_days, days_to_show):
    """Generate SVG content from the data"""
    # Constants for layout - redesigned for heat map style
    cell_size = 20
    cell_margin = 2
    cell_total = cell_size + 2 * cell_margin
    header_height = 100
    footer_height = 40

    # Calculate dimensions for heat map grid
    width = max(400, (days_to_show * cell_total) + 60)  # Minimum width for readability
    height = header_height + footer_height + cell_total

    # Start SVG content
    svg_content = [
        f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg" font-family="Arial, sans-serif">'
    ]

    # Add title with styling
    svg_content.append(f'<text x="20" y="25" font-size="18" font-weight="bold" fill="#333">NUR Sync Status</text>')

    # Show latest status info with improved formatting and color
    if latest_entry:
        status_color = "#4CAF50" if latest_entry["status"] == "synced" else "#F44336"
        status_icon = "🟢" if latest_entry["status"] == "synced" else "🔴"
        svg_content.append(f'<text x="20" y="45" font-size="14" font-weight="bold" fill="{status_color}">Latest: {status_icon} {latest_entry["status"].title()}</text>')
        svg_content.append(f'<text x="20" y="65" font-size="12" fill="#666">📅 {latest_entry["timestamp_str"]}</text>')
        svg_content.append(f'<text x="20" y="80" font-size="12" fill="#666">🔄 Fork: {latest_entry["fork_rev"][:8]}... | 📦 Official: {latest_entry["official_rev"][:8]}...</text>')
    else:
        svg_content.append(f'<text x="20" y="45" font-size="12" fill="#999">Latest: No data available</text>')

    # Heat map title
    svg_content.append(f'<text x="20" y="{header_height - 15}" font-size="14" font-weight="bold" fill="#333">Last {days_to_show} Days Activity</text>')

    # Draw heat map grid
    start_x = (width - days_to_show * cell_total) // 2  # Center the grid

    for i, (day, day_entries) in enumerate(last_days):
        x = start_x + i * cell_total + cell_margin

        if day_entries:
            # Determine color based on the day's status
            # If any entry is unsynced, make the cell red; if all synced, make it green
            all_synced = all(entry['status'] == 'synced' for entry in day_entries)
            color = "#4CAF50" if all_synced else "#F44336"  # Green if all synced, red otherwise

            # Draw day cell with color based on status
            svg_content.append(f'<rect x="{x}" y="{header_height}" width="{cell_size}" height="{cell_size}" fill="{color}" stroke="#000" stroke-width="0.5" rx="3" ry="3"/>')

            # Add day text
            svg_content.append(f'<text x="{x + cell_size/2}" y="{header_height + cell_size/2 + 5}" font-size="10" text-anchor="middle" fill="white" font-weight="bold">{day.strftime("%d")}</text>')
        else:
            # Draw a gray cell to indicate no data
            svg_content.append(f'<rect x="{x}" y="{header_height}" width="{cell_size}" height="{cell_size}" fill="#BDBDBD" stroke="#000" stroke-width="0.5" rx="3" ry="3"/>')
            svg_content.append(f'<text x="{x + cell_size/2}" y="{header_height + cell_size/2 + 5}" font-size="10" text-anchor="middle" fill="#666">-</text>')

    # Add day labels (name of the day) below the heat map
    for i, (day, day_entries) in enumerate(last_days):
        x = start_x + i * cell_total + cell_total // 2
        day_name = day.strftime("%a")  # Abbreviated day name (Mon, Tue, etc.)
        svg_content.append(f'<text x="{x}" y="{header_height + cell_total + 15}" font-size="10" text-anchor="middle" fill="#666">{day_name}</text>')

    # Add legend
    legend_x = 20
    legend_y = height - 25
    svg_content.append(f'<rect x="{legend_x}" y="{legend_y}" width="12" height="12" fill="#4CAF50" stroke="#000" stroke-width="0.5" rx="2" ry="2"/>')
    svg_content.append(f'<text x="{legend_x + 20}" y="{legend_y + 10}" font-size="10" fill="#333">Synced</text>')

    svg_content.append(f'<rect x="{legend_x + 80}" y="{legend_y}" width="12" height="12" fill="#F44336" stroke="#000" stroke-width="0.5" rx="2" ry="2"/>')
    svg_content.append(f'<text x="{legend_x + 100}" y="{legend_y + 10}" font-size="10" fill="#333">Unsynced</text>')

    svg_content.append(f'<rect x="{legend_x + 170}" y="{legend_y}" width="12" height="12" fill="#BDBDBD" stroke="#000" stroke-width="0.5" rx="2" ry="2"/>')
    svg_content.append(f'<text x="{legend_x + 190}" y="{legend_y + 10}" font-size="10" fill="#333">No data</text>')

    # Close SVG
    svg_content.append('</svg>')

    return '\n'.join(svg_content)


def main():
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print(f"Usage: {sys.argv[0]} <input_json_file> <output_svg_file> [days_to_show=7]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    # 设置默认值
    days_to_show = 7  # 默认显示7天

    # 解析可选参数
    if len(sys.argv) >= 4:
        try:
            days_to_show = int(sys.argv[3])
        except ValueError:
            print(f"Error: Days to show must be an integer, got: {sys.argv[3]}")
            sys.exit(1)

    # Load and process JSON data
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    history = data.get('history', [])
    valid_history = filter_valid_history(history)
    latest_entry = get_latest_entry(valid_history)
    last_days = get_last_days_data(valid_history, days_to_show)

    # Generate and write SVG content
    svg_content = generate_svg_content(latest_entry, last_days, days_to_show)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(svg_content)

    print(f"Successfully written SVG to {output_file}")


if __name__ == "__main__":
    main()