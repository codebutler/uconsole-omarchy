-- CM4's stateful H.264 decoder is not the CM5's stateless HEVC decoder.
-- Inspect both the SoC and exposed driver; never force v4l2m2m on a CM5.
local function read(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local value = file:read("*a")
  file:close()
  return value
end
local cm4 = read("/proc/device-tree/compatible"):find("brcm,bcm2711", 1, true)
local decoder = false
for n = 0, 63 do
  if read("/sys/class/video4linux/video" .. n .. "/name"):match("^bcm2835%-codec%-decode") then
    decoder = true
  end
end
mp.add_hook("on_load", 10, function()
  -- Explicit user/CLI choices win. The platform default is auto-safe.
  if mp.get_property("hwdec") ~= "auto-safe" then return end
  if cm4 and decoder then
    mp.set_property("hwdec", "v4l2m2m-copy")
    mp.set_property("hwdec-codecs", "h264")
    mp.msg.info("uConsole: CM4 H.264 stateful decoder enabled; other codecs use software")
  else
    mp.msg.info("uConsole: using mpv auto-safe; no CM4 decoder override")
  end
end)
