-- Hardware dispatch policy tests; real decode performance is a device test.
local script = "packages/uconsole-platform/rootfs/usr/share/uconsole/mpv/hwdec.lua"
local original_open = io.open
local function check(model, has_decoder, initial, expected)
  local properties = { hwdec = initial }
  local callback
  io.open = function(path)
    local data
    if path == "/proc/device-tree/compatible" then
      data = model
    elseif path == "/sys/class/video4linux/video10/name" and has_decoder then
      data = "bcm2835-codec-decode\n"
    else
      return nil
    end
    return { read = function() return data end, close = function() end }
  end
  mp = {
    add_hook = function(_, _, fn) callback = fn end,
    get_property = function(key) return properties[key] end,
    set_property = function(key, value) properties[key] = value end,
    msg = { info = function() end },
  }
  dofile(script)
  callback()
  io.open = original_open
  assert(properties.hwdec == expected, model .. ": " .. properties.hwdec)
  if expected == "v4l2m2m-copy" and initial == "auto-safe" then
    assert(properties["hwdec-codecs"] == "h264")
  end
end
check("raspberrypi,4-compute-module\0brcm,bcm2711\0", true, "auto-safe", "v4l2m2m-copy")
check("raspberrypi,4-compute-module\0brcm,bcm2711\0", false, "auto-safe", "auto-safe")
check("raspberrypi,5-compute-module\0brcm,bcm2712\0", true, "auto-safe", "auto-safe")
check("raspberrypi,5-compute-module\0brcm,bcm2712\0", false, "auto-safe", "auto-safe")
check("brcm,bcm2711\0", true, "no", "no")
check("brcm,bcm2711\0", true, "vaapi", "vaapi")
print("mpv model policy: 6 tests passed")
