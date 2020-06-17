import json
import os
import os.path as ospath
import sys

os.chdir(ospath.abspath(sys.argv[1]))

BASE_PATH = "./"
OUTPUT_PATH = BASE_PATH
try:
    OUTPUT_PATH = ospath.abspath(sys.argv[2])
except:
    pass
FF_CMD_OUTPUT = ospath.join(BASE_PATH, "cmd.bat")
CMD = []


def read_json(file):
    with open(file, "r", encoding="utf-8") as f:
        return json.load(f)


def export_cmd():
    if os.path.exists(FF_CMD_OUTPUT):
        os.remove(FF_CMD_OUTPUT)
    with open(
        FF_CMD_OUTPUT, "x", encoding="utf-8"
    ) as f:  # x: open for exclusive creation, failing if the file already exists
        f.write("@chcp 65001\n")
        f.write("\n".join(CMD))


def get_or_blank(d, k, p):
    v = d[k]
    return (" " + v if p else v) if v else ""


def run(path):
    try:
        e: dict = read_json(ospath.join(path, "entry.json"))
    except FileNotFoundError as err:
        print(err)
        return
    m = {}
    eKeys = e.keys()

    m["title"] = e["title"]
    if "video_quality" in eKeys:
        m["quality"] = e["video_quality"]
    elif "prefered_video_quality" in eKeys:
        m["quality"] = e["prefered_video_quality"]
    try:
        m["quality_label"] = e["quality_pithy_description"] + get_or_blank(
            e, "quality_superscript", True
        )
    except:
        pass

    vid = ""
    cid = ""
    if "ep" in eKeys:
        m["avid"] = e["ep"]["av_id"]
        m["bvid"] = e["ep"]["bvid"]
        m["cid"] = e["source"]["cid"]
        cid = m["cid"]
        vid = "ss" + m["season_id"]
        m["season_id"] = e["season_id"]
        m["page"] = e["ep"]["index"]
        m["page_title"] = get_or_blank(e, "index_title", False)
        output = ospath.join(OUTPUT_PATH, f"{m["page"]}.{m["page_title"]}.mp4")
    else:
        title = m["title"]
        m["avid"] = e["avid"]
        vid = m["avid"]
        if "bvid" in eKeys:
            if e["bvid"] != "":
                vid = e["bvid"]
                m["bvid"] = e["bvid"]
        m["cid"] = e["page_data"]["cid"]
        cid = m["cid"]
        if "owner_id" in eKeys:
            m["owner_id"] = e["owner_id"]
        else:
            m["owner_id"] = -1
        m["page"] = e["page_data"]["page"]
        try:
            _t = e["page_data"]["part"]
            if not _t == m["title"]:
                m["page_title"] = _t
                title += " - " + _t
        except:
            pass
        outputFilename = (
            f"{vid}.{cid} - {title}.mp4".replace("\\", " ")
            .replace("/", " ")
            .replace('"', " ")
            .replace("'", " ")
            .replace("|", " ")
            .replace("^", " ")
            .replace(":", " ")
            .replace("?", " ")
            .replace("*", " ")
            .replace("<", " ")
            .replace(">", " ")
        )
        output = ospath.join(OUTPUT_PATH, outputFilename)

    input = ""
    if "." in e["type_tag"]:
        blv = ospath.join(path, e["type_tag"], "0.blv")
        if "quality_label" in m.keys():
            m["quality_label"] += " BLV"
        else:
            m["quality_label"] = e["type_tag"] + " BLV"
        input = f'-i "{blv}"'
    else:
        video = ospath.join(path, str(m["quality"]), "video.m4s")
        audio = ospath.join(path, str(m["quality"]), "audio.m4s")
        input = f'-i "{ospath.abspath(video)}" -i "{ospath.abspath(audio)}"'
    metadata = f'-metadata title="{m["title"].replace("\"","\"\"\"")}" '
    metadata += " ".join(
        [
            f'-metadata bilibili_{k}="{str(v).replace("\"","\"\"\"")}"'
            for k, v in m.items()
        ]
    )
    print(json.dumps(m, ensure_ascii=False, indent=4))

    danmaku = ospath.join(path, "danmaku.xml")
    if ospath.exists(danmaku):
        CMD.append(
            f"MOVE {ospath.abspath(danmaku)} {ospath.join(OUTPUT_PATH, f"{vid}.{cid}.xml")}"
        )

    ffmpeg = f"""
ffmpeg {input}
-c:v copy -c:a copy {metadata} -movflags +use_metadata_tags
-hide_banner -loglevel warning -y
"{ospath.abspath(output)}"
"""
    CMD.append(ffmpeg.replace("\n", " ").strip())
    CMD.append(f"IF errorlevel 0 RMDIR /S /Q {path}")


if __name__ == "__main__":
    for fileA in os.listdir(BASE_PATH):
        if ospath.isdir(fileA):
            pathA = ospath.abspath(ospath.join(BASE_PATH, fileA))
            for fileB in os.listdir(pathA):
                pathB = ospath.abspath(ospath.join(pathA, fileB))
                if ospath.isdir(pathB):
                    print(pathB)
                    run(pathB)
                    print("")
    export_cmd()
