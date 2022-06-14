import shutil
import sys
import pathlib


dst = pathlib.Path(sys.argv[1])

dst_map = {}

def chunk(lst, count):
    if len(lst) % count != 0:
        raise ValueError("Wrong number of arguments")
    for i in range(0, len(lst), count):
        yield lst[i:i+count]

def walkdir(path):
    yield path
    if path.is_dir():
        for subfile in path.iterdir():
            yield from walkdir(subfile)

for src_name, src, subpath in chunk(sys.argv[2:], 3):
    src = pathlib.Path(src)
    print("Mounting", src_name, "at", subpath)
    for subfile in walkdir(src):
        subfile = subfile.relative_to(src)
        src_subfile = src / subfile
        dst_subfile = dst / subpath / subfile
        if not src_subfile.exists():
            print(f"{src_subfile} does not exist or is not accessible inside the Nix sandbox")
        if src_subfile.is_dir():
            if dst_subfile.exists():
                if dst_subfile.is_file():
                    print(f"{subfile} is a directory in {src_name} but a file in {dst_map.get(dst_subfile, '<unknown package>')}")
                    sys.exit(1)
            else:
                dst_subfile.mkdir(parents=True)
                dst_map[dst_subfile] = src_name
        elif src_subfile.is_file():
            if dst_subfile.exists():
                print(f"{subfile} in {src_name} conflicts with {subfile} in {dst_map.get(dst_subfile, '<unknown package>')}")
                sys.exit(1)
            else:
                print(f"{src_name}/{subfile} -> $out/{subpath}/{subfile}")
                shutil.copy(src_subfile, dst_subfile)
                dst_map[dst_subfile] = src_name
        else:
            print(f"{src_subfile} is an illegal file type")
