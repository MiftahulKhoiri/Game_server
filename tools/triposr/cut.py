import sys
from PIL import Image
import rembg
src, out = sys.argv[1], sys.argv[2]
crop_bottom = int(sys.argv[3]) if len(sys.argv) > 3 else 0
im = Image.open(src).convert("RGB")
if crop_bottom:
    im = im.crop((0, 0, im.width, crop_bottom))
sess = rembg.new_session("isnet-general-use" if len(sys.argv) > 4 else "u2net")
res = rembg.remove(im, session=sess)
bbox = res.getchannel("A").getbbox()
res = res.crop(bbox)
res.thumbnail((768, 768))
res.save(out)
print("ok", out, res.size)
