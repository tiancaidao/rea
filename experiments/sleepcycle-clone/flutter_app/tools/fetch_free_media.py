#!/usr/bin/env python3
"""Fetch the app's real alarm and ambience recordings from Wikimedia Commons.

Every source is public domain, CC0, CC BY or CC BY-SA (checked on its file
page and written to assets/free/CREDITS-audio.md). Needs curl and ffmpeg.

    python3 tools/fetch_free_media.py [cache-dir]
"""
import subprocess, re, sys, html, urllib.parse, time
UA = "SleepCloneAssets/1.0 (https://github.com/tiancaidao/rea; tiancaidao)"
def get(url):
    for i in range(4):
        r = subprocess.run(["curl", "-sL", "-A", UA, "-m", "60", "-w", "\n%{http_code}", url], capture_output=True)
        body, _, code = r.stdout.rpartition(b"\n")
        if code == b"200": return body.decode("utf-8", "replace")
        time.sleep(2 ** i)
    return ""
def search(q, mime="audio", n=40):
    u = ("https://commons.wikimedia.org/w/index.php?search=" + urllib.parse.quote_plus(q + f" filemime:{mime}")
         + f"&title=Special:Search&profile=advanced&fulltext=1&ns6=1&limit={n}")
    return sorted(set(html.unescape(t) for t in re.findall(r'title="(File:[^"]+)"', get(u))))
def info(title):
    s = get("https://commons.wikimedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_")))
    lic = sorted(set(html.unescape(x).strip() for x in re.findall(r'class="licensetpl(?:_|&#95;)short"[^>]*>(.*?)<', s)))
    a = re.search(r'id="fileinfotpl(?:_|&#95;)aut"[^>]*>.*?</td>\s*<td[^>]*>(.*?)</td>', s, re.S)
    author = " ".join(html.unescape(re.sub("<[^>]+>", " ", a.group(1))).split())[:120] if a else ""
    dur = re.search(r'(\d+(?:\.\d+)?)\s*s(?:econds)?,', s) or re.search(r'length (\d+ min \d+ s|\d+ s|\d+\.\d+ s)', s)
    meta = re.search(r'class="fileInfo">(.*?)<', s)
    return lic, author, html.unescape(meta.group(1)) if meta else ""
import subprocess, sys, os, json, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
DL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, ".media-cache")
OUT = os.path.join(HERE, "..", "assets", "free", "audio")
os.makedirs(DL, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
# (output, Commons title, start s, length s, kind)
ITEMS = [
 ("alarm_soft_breeze", "File:Gymnopedie No. 1 (ISRC USUAN1100787).mp3", 0, 50, "alarm"),
 ("alarm_forest_clearing", "File:Dobroide - 20060824.forest03 (cc-by) (freesound).wav", 0, 50, "alarm"),
 ("alarm_morning_haze", "File:Chopin - Nocturne No. 16 in E-flat major, Op. 55 No. 2 (Xuan He).flac", 0, 50, "alarm"),
 ("alarm_first_light", "File:Grieg - Peer Gynt Suite No. 1, Op. 46 - I. Morning Mood (Musopen Symphony).flac", 0, 60, "alarm"),
 ("alarm_dewdrops", "File:988-aria.lehman1.wav", 0, 50, "alarm"),
 ("alarm_classical_morning", "File:Borodin - String Quartet No. 1 in A major - II. Andante con moto (Musopen String Quartet).flac", 0, 50, "alarm"),
 ("alarm_rain_and_wind", "File:Bourne woods Birdsong and rain 2020-06-17 0748.mp3", 2, 50, "alarm"),
 ("alarm_far_memories", "File:Gymnopedie No. 2 (ISRC USUAN1100786).mp3", 0, 50, "alarm"),
 ("alarm_slow_waltz", "File:Chopin - Waltz No. 10 in B minor, Op. 69 No. 2 (Olga Gurevich).flac", 0, 50, "alarm"),
 ("alarm_songbird", "File:Bourne woods 2020-05-18 0730.mp3", 2, 50, "alarm"),
 ("alarm_city_dawn", "File:Scott Joplin - 04 - The Entertainer 1902 piano roll.mp3", 0, 50, "alarm"),
 ("alarm_meadow", "File:Brylie Christopher Oxley - Springtime Morning Birdsong.flac", 5, 50, "alarm"),
 ("alarm_sea_dreams", "File:Manhã fria no mar - Felipe RuizBRX11.wav", 10, 50, "alarm"),
 ("alarm_riddle", "File:988-v02.lehman1.wav", 0, 50, "alarm"),
 ("alarm_stillness", "File:Gymnopedie No. 3 (ISRC USUAN1100785).mp3", 0, 50, "alarm"),
 ("alarm_winter_moon", "File:Chopin - Nocturne No. 1 in B-flat minor, Op. 9 No. 1 (Olga Gurevich).flac", 0, 50, "alarm"),
 ("alarm_park_bench", "File:Bourne woods 2020-08-31 0735.mp3", 2, 50, "alarm"),
 ("alarm_metro", "File:Chopin - Waltz No. 11 in G-flat major, Op. 70 No. 1 (Olga Gurevich).flac", 0, 50, "alarm"),
 ("alarm_good_morning", "File:Borodin - In the Steppes of Central Asia (Musopen Symphony).flac", 0, 60, "alarm"),
 ("amb_rain", "File:Bourne woods rain 2020-05-10 0800.mp3", 5, 60, "amb"),
 ("amb_wind", "File:Wind in forest (Gravity Sound).wav", 0, 50, "amb"),
 ("amb_ocean", "File:Manhã fria no mar - Felipe RuizBRX11.wav", 70, 60, "amb"),
 ("amb_fire", "File:Semillas crepitando.wav", 0, 26, "amb"),
 ("amb_night_forest", "File:Audio Hörbild Grillenzirpen - nachts um 3 im Föhrenwald Mödling.wav", 0, 40, "amb"),
 ("amb_stream", "File:433589 jackthemurray stream-river-water-up-close.wav", 0, 60, "amb"),
 ("amb_droplets", "File:Listening to Raindrops (1035382 - heavy loop).mp3", 0, 30, "amb"),
]
credits = []
for out, title, start, length, kind in ITEMS:
    src = os.path.join(DL, title[5:].replace("/", "_"))
    if not os.path.exists(src):
        url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(title[5:].replace(" ", "_"))
        subprocess.run(["curl", "-fsL", "-A", UA, "-m", "300", "--retry", "3", "-o", src, url], check=True)
    lic, author, meta = info(title)
    dst = os.path.join(OUT, out + ".mp3")
    fade_out = 4 if kind == "alarm" else 0
    xf = 2.0
    if kind == "alarm":
        af = f"atrim={start}:{start+length},asetpts=PTS-STARTPTS,afade=t=in:d=1.5,afade=t=out:st={length-fade_out}:d={fade_out},loudnorm=I=-16:TP=-1.5:LRA=11"
        args = ["-ac", "2", "-b:a", "96k"]
    else:
        # seamless loop: crossfade the tail into the head
        af = (f"atrim={start}:{start+length+xf},asetpts=PTS-STARTPTS,asplit[a][b];"
              f"[a]atrim=0:{xf},asetpts=PTS-STARTPTS[head];"
              f"[b]atrim={xf},asetpts=PTS-STARTPTS[body];"
              f"[body][head]acrossfade=d={xf}:c1=tri:c2=tri,loudnorm=I=-20:TP=-2:LRA=11")
        args = ["-ac", "2", "-b:a", "80k"]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-filter_complex" if kind != "alarm" else "-af", af,
                    "-ar", "44100", *args, dst], check=True)
    credits.append({"file": out + ".mp3", "source": "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_")),
                    "title": title[5:], "author": author.split(".mw-parser-output")[0].strip(" :;") or "see source page",
                    "license": ", ".join(lic), "excerpt": f"{start}-{start+length} s"})
    print(out, "|", ", ".join(lic), "|", os.path.getsize(dst)//1024, "KB", flush=True)
with open(os.path.join(OUT, "..", "CREDITS-audio.md"), "w") as fh:
    fh.write("# Audio credits\n\nExcerpts trimmed, faded and loudness-normalised by tools/fetch_free_media.py.\n\n")
    fh.write("| File | Source | Author | Licence | Excerpt |\n|---|---|---|---|---|\n")
    for c in credits:
        fh.write(f"| {c['file']} | [{c['title']}]({c['source']}) | {c['author']} | {c['license']} | {c['excerpt']} |\n")
