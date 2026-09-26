#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_time(time_str: str) -> float:
    """Converts [[HH:]MM:]SS[.xxx] or seconds float string to float seconds."""
    parts = str(time_str).strip().split(":")
    if len(parts) == 1:
        return float(parts[0])
    elif len(parts) == 2:
        return float(parts[0]) * 60 + float(parts[1])
    elif len(parts) == 3:
        return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
    raise ValueError(f"Invalid time format: {time_str}")


def run_command(cmd: list[str]) -> str:
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Command failed:\n{' '.join(cmd)}\n\nError:\n{res.stderr}")
    return res.stdout


def get_stream_info(input_file: str) -> dict:
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,pix_fmt,r_frame_rate,profile",
        "-of", "json",
        input_file,
    ]
    info = json.loads(run_command(cmd))
    return info["streams"][0]


def get_keyframes(input_file: str) -> list[float]:
    """Retrieves all packet PTS timestamps for I-frames."""
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-skip_frame", "nokey",
        "-show_entries", "frame=pkt_pts_time,best_effort_timestamp_time",
        "-of", "json",
        input_file,
    ]
    data = json.loads(run_command(cmd))
    keyframes = []
    for frame in data.get("frames", []):
        ts = frame.get("pkt_pts_time") or frame.get("best_effort_timestamp_time")
        if ts is not None:
            keyframes.append(float(ts))
    return sorted(list(set(keyframes)))


def smart_cut(input_file: str, start_time: str, end_time: str, output_file: str):
    t_start = parse_time(start_time)
    t_end = parse_time(end_time)

    if t_start >= t_end:
        raise ValueError("Start time must be strictly less than end time.")

    print(f"[*] Probing keyframes and codecs for: {input_file}")
    stream_info = get_stream_info(input_file)
    keyframes = get_keyframes(input_file)

    codec = stream_info.get("codec_name", "h264")
    pix_fmt = stream_info.get("pix_fmt", "yuv420p")
    fps = stream_info.get("r_frame_rate", "30/1")

    # Select encoder based on source video codec
    v_encoder = "libx264"
    if codec in ("hevc", "h265"):
        v_encoder = "libx265"

    # Find bounding keyframes
    # k_next: First keyframe >= t_start
    k_next = next((k for k in keyframes if k >= t_start), None)
    # k_prev: Last keyframe <= t_end
    k_prev_candidates = [k for k in keyframes if k <= t_end]
    k_prev = k_prev_candidates[-1] if k_prev_candidates else None

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_dir_path = Path(temp_dir)
        concat_list = temp_dir_path / "concat.txt"
        segments = []

        # Scenario 1: Target slice is entirely inside a single GOP (no keyframe in between)
        if k_next is None or k_next >= t_end:
            print("[*] Interval lies within a single GOP. Performing brief re-encode...")
            out_part = temp_dir_path / "single.mp4"
            cmd = [
                "ffmpeg", "-y", "-ss", str(t_start), "-to", str(t_end),
                "-i", input_file,
                "-c:v", v_encoder, "-crf", "18", "-preset", "fast",
                "-pix_fmt", pix_fmt, "-r", fps,
                "-c:a", "aac", str(out_part),
            ]
            run_command(cmd)
            subprocess.run(["mv", str(out_part), output_file], check=True)
            print(f"[+] Output ready: {output_file}")
            return

        # Scenario 2: Smart cut (Head -> Body -> Tail)
        # 1. Head segment (re-encode from t_start to k_next if not directly on a keyframe)
        if abs(t_start - k_next) > 0.04:  # > 1 frame difference
            print(f"[*] Re-encoding head: {t_start:.3f} -> {k_next:.3f}")
            head_part = temp_dir_path / "head.ts"
            cmd_head = [
                "ffmpeg", "-y", "-ss", str(t_start), "-to", str(k_next),
                "-i", input_file,
                "-c:v", v_encoder, "-crf", "18", "-preset", "fast",
                "-pix_fmt", pix_fmt, "-r", fps,
                "-c:a", "aac", str(head_part),
            ]
            run_command(cmd_head)
            segments.append(head_part)
        else:
            k_next = t_start

        # 2. Body segment (stream copy between keyframes)
        if k_prev > k_next:
            print(f"[*] Stream copying body: {k_next:.3f} -> {k_prev:.3f}")
            body_part = temp_dir_path / "body.ts"
            cmd_body = [
                "ffmpeg", "-y", "-ss", str(k_next), "-to", str(k_prev),
                "-i", input_file,
                "-c", "copy", str(body_part),
            ]
            run_command(cmd_body)
            segments.append(body_part)

        # 3. Tail segment (re-encode from k_prev to t_end if not directly on a keyframe)
        if abs(t_end - k_prev) > 0.04:
            print(f"[*] Re-encoding tail: {k_prev:.3f} -> {t_end:.3f}")
            tail_part = temp_dir_path / "tail.ts"
            cmd_tail = [
                "ffmpeg", "-y", "-ss", str(k_prev), "-to", str(t_end),
                "-i", input_file,
                "-c:v", v_encoder, "-crf", "18", "-preset", "fast",
                "-pix_fmt", pix_fmt, "-r", fps,
                "-c:a", "aac", str(tail_part),
            ]
            run_command(cmd_tail)
            segments.append(tail_part)

        # Generate concat manifest
        with open(concat_list, "w") as f:
            for seg in segments:
                f.write(f"file '{seg.resolve()}'\n")

        # Final concatenation step
        print("[*] Merging parts into final container...")
        cmd_concat = [
            "ffmpeg", "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_list),
            "-c", "copy",
            "-movflags", "+faststart",
            output_file,
        ]
        run_command(cmd_concat)
        print(f"[+] Successfully generated: {output_file}")


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: python smart_cut.py <input.mp4> <start> <end> <output.mp4>")
        print("Example: python smart_cut.py video.mp4 00:01:23.500 00:04:12.100 out.mp4")
        sys.exit(1)

    smart_cut(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])