#!/usr/bin/env python3
"""End-to-end tests against the bundled worker/encoder, with actual MP4 decode.
Run outside a restricted sandbox: Apple VideoToolbox requires macOS services.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'build/Finder Audio Tools.app/Contents/Resources'
WORKER = RES / 'CompressionWorker'
FFMPEG = RES / 'ffmpeg'
PROBE = RES / 'ffprobe'
GENERATOR = shutil.which('ffmpeg')

def command(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True)

def generate(path, *args):
    command(GENERATOR, '-hide_banner', '-loglevel', 'error', '-y', *args, path)

def probe(path):
    return json.loads(command(PROBE, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', path).stdout)

def run(mb, paths, resolution='auto', audio='keep', expected=0):
    p = subprocess.run([str(WORKER), str(mb), resolution, audio, *map(str, paths)], capture_output=True, text=True)
    assert p.returncode == expected, (p.stdout, p.stderr)
    events = [json.loads(line) for line in p.stdout.splitlines()]
    for event in events:
        if event['type'] == 'success':
            output = Path(event['output'])
            if mb: assert 0 < output.stat().st_size < mb * 1_000_000
            command(FFMPEG, '-hide_banner', '-v', 'error', '-i', output, '-f', 'null', '-')
            video = next(s for s in probe(output)['streams'] if s['codec_type'] == 'video')
            assert video['codec_name'] == 'h264'
            assert video['width'] % 2 == video['height'] % 2 == 0
    return events

def results(events, kind):
    return [e for e in events if e['type'] == kind]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    assert GENERATOR and WORKER.exists(), 'Build the app first; developer ffmpeg is needed to create fixtures.'
    with tempfile.TemporaryDirectory(prefix='convertright-video-') as folder:
        directory = Path(folder)
        large = directory / '大视频 空格.mp4'
        generate(large, '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '35', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '0', '-c:a', 'aac')
        original_hash = digest(large)
        assert large.stat().st_size > 100_000_000
        for limit in (10, 20, 50, 100):
            event = results(run(limit, [large]), 'success')[0]
            print(f'PASS preset {limit} MB: {event["outputBytes"] / 1e6:.2f} MB', flush=True)
        first = results(run(1, [large], '720', 'mute'), 'success')[0]
        streams = probe(first['output'])['streams']
        assert not any(s['codec_type'] == 'audio' for s in streams)
        assert max(streams[0]['width'], streams[0]['height']) <= 1280
        again = results(run(1, [large], '720', 'mute'), 'success')[0]
        assert again['output'] != first['output'] and Path(first['output']).exists()
        assert results(run(0.1, [large], expected=1), 'error')
        print('PASS custom size, mute, resolution, collision and infeasible target', flush=True)
        portrait = directory / '竖屏 无声.mov'
        generate(portrait, '-f', 'lavfi', '-i', 'testsrc2=size=360x640:rate=24', '-t', '4', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '0')
        event = results(run(0.3, [portrait]), 'success')[0]
        video = next(s for s in probe(event['output'])['streams'] if s['codec_type'] == 'video')
        assert video['height'] > video['width']
        assert results(run(20, [Path(event['output'])]), 'skipped')
        assert results(run(0, [large]), 'success')
        corrupt = directory / '坏视频.mp4'
        corrupt.write_bytes(b'not a video')
        batch = run(0.3, [corrupt, portrait], expected=1)
        assert len(results(batch, 'success')) == len(results(batch, 'error')) == 1
        print('PASS portrait, no audio, already-small skip, quick mode and partial batch failure', flush=True)
        rotated = directory / '旋转.mp4'
        generate(rotated, '-display_rotation', '90', '-i', portrait, '-c', 'copy')
        event = results(run(0.3, [rotated]), 'success')[0]
        video = next(s for s in probe(event['output'])['streams'] if s['codec_type'] == 'video')
        assert video['width'] > video['height']
        hdr = directory / 'HDR.mov'
        generate(hdr, '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '3', '-c:v', 'libx265', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p10le', '-x265-params', 'log-level=error:pools=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc', '-color_primaries', 'bt2020', '-color_trc', 'smpte2084', '-colorspace', 'bt2020nc')
        assert probe(hdr)['streams'][0].get('color_transfer') == 'smpte2084', 'HDR fixture must contain an actual PQ transfer tag'
        event = results(run(0.2, [hdr]), 'success')[0]
        video = next(s for s in probe(event['output'])['streams'] if s['codec_type'] == 'video')
        assert video.get('color_transfer') == 'bt709' and video['pix_fmt'] == 'yuv420p'
        print('PASS rotation and HDR-to-SDR', flush=True)
        before = set(directory.iterdir())
        p = subprocess.Popen([str(WORKER), '1', 'auto', 'keep', str(large), str(portrait)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        start = time.monotonic()
        for line in p.stdout:
            event = json.loads(line)
            if event['type'] == 'state' and event['detail'].startswith(('Compressing', 'Analysing')):
                p.terminate()
                break
            assert time.monotonic() - start < 30
        remaining = p.communicate(timeout=20)[0]
        assert p.returncode == 130, remaining
        assert set(directory.iterdir()) == before, 'Cancelled job left a partial file or processed another video'
        assert digest(large) == original_hash
        print('PASS cancellation cleanup, queued-file cancellation and unchanged source', flush=True)
    print('All video compression integration tests passed.', flush=True)

if __name__ == '__main__':
    main()
