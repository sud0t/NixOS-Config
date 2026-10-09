-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- Hyprland variables 
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Nord")
-- XDG stuff
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
-- Qt variables 
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
-- Toolkit backend
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
-- Nvidia and general graphics stuff
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

hl.env("AQ_DRM_DEVICES", "/dev/dri/card0:/dev/dri/card1")

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("WINIT_UNIX_BACKEND", "x11")
hl.env("WGPU_BACKEND", "gl")
