using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;

// Win32 display configuration. Changes are restricted to the named virtual adapter.
public static class FrameDisplayNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2;
        public int dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string device, int index, ref DISPLAY_DEVICE output, int flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettingsEx(string device, int mode, ref DEVMODE output, int flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string device, ref DEVMODE mode, IntPtr hwnd, int flags, IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")] static extern int ApplyAll(string device, IntPtr mode, IntPtr hwnd, int flags, IntPtr param);
    public class Display {
        public string Name, Description, AdapterId, MonitorName, MonitorId;
        public bool Active, Primary;
        public int X, Y, Width, Height, RefreshRate, Orientation;
    }
    static DEVMODE Mode(string name) {
        var mode = new DEVMODE(); mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettingsEx(name, -1, ref mode, 0) && !EnumDisplaySettingsEx(name, -2, ref mode, 0))
            throw new InvalidOperationException("No display mode for " + name);
        return mode;
    }
    public static Display[] List() {
        var list = new List<Display>();
        for (int i=0;;i++) {
            var device = new DISPLAY_DEVICE(); device.cb=Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, i, ref device, 0)) break;
            var monitor = new DISPLAY_DEVICE(); monitor.cb=Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            EnumDisplayDevices(device.DeviceName, 0, ref monitor, 0);
            var item = new Display { Name=device.DeviceName, Description=device.DeviceString, AdapterId=device.DeviceID,
                MonitorName=monitor.DeviceString, MonitorId=monitor.DeviceID, Active=(device.StateFlags&1)!=0, Primary=(device.StateFlags&4)!=0 };
            try { var mode=Mode(device.DeviceName); item.X=mode.dmPositionX; item.Y=mode.dmPositionY;
                item.Width=mode.dmPelsWidth; item.Height=mode.dmPelsHeight; item.RefreshRate=mode.dmDisplayFrequency; item.Orientation=mode.dmDisplayOrientation; } catch {}
            list.Add(item);
        }
        return list.ToArray();
    }
    public static Display Virtual(string name) {
        var matches=List().Where(d => d.Name==name && (d.Description.Equals("Virtual Display Driver", StringComparison.OrdinalIgnoreCase)
            || d.Description.Equals("SudoMaker Virtual Display Adapter", StringComparison.OrdinalIgnoreCase))).ToArray();
        if(matches.Length!=1) throw new InvalidOperationException("Expected exactly one supported virtual display named " + name);
        return matches[0];
    }
    public static Display Extend(string name, int width=1920, int height=1080, int refreshRate=60) {
        var target=Virtual(name);
        var physical=List().Where(d=>d.Active && d.Name!=target.Name).ToArray();
        if(physical.Length==0) throw new InvalidOperationException("No existing desktop display to preserve.");
        if(target.Primary) throw new InvalidOperationException("Virtual display is primary; restore the physical primary display first.");
        if(target.Active && target.Width==width && target.Height==height && target.Orientation==0 && target.RefreshRate==refreshRate
            && physical.All(d=>!Overlaps(target, d))) return target;
        var mode=Mode(target.Name);
        mode.dmPositionX=physical.Max(d=>d.X+d.Width); mode.dmPositionY=physical.Min(d=>d.Y);
        mode.dmPelsWidth=width; mode.dmPelsHeight=height; mode.dmDisplayFrequency=refreshRate; mode.dmBitsPerPel=32; mode.dmDisplayOrientation=0;
        mode.dmFields=0x20|0x80|0x40000|0x80000|0x100000|0x400000;
        int status=ChangeDisplaySettingsEx(target.Name, ref mode, IntPtr.Zero, 2, IntPtr.Zero);
        if(status!=0) throw new InvalidOperationException("Virtual display mode validation failed: " + status);
        status=ChangeDisplaySettingsEx(target.Name, ref mode, IntPtr.Zero, 1|0x10000000, IntPtr.Zero);
        if(status!=0) throw new InvalidOperationException("Virtual display configuration failed: " + status);
        status=ApplyAll(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        if(status!=0) throw new InvalidOperationException("Applying virtual display layout failed: " + status);
        foreach(var old in physical) {
            var current=List().Single(d=>d.Name==old.Name);
            if(!current.Active || current.X!=old.X || current.Y!=old.Y || current.Width!=old.Width || current.Height!=old.Height || current.Primary!=old.Primary)
                throw new InvalidOperationException("Existing display layout changed unexpectedly: " + old.Name);
        }
        target=Virtual(name);
        if(!target.Active || target.Width!=width || target.Height!=height || target.Primary || physical.Any(d=>Overlaps(target,d)))
            throw new InvalidOperationException("Virtual display is not an independent extended desktop.");
        return target;
    }
    public static void Detach(string name) {
        var target=Virtual(name); if(!target.Active) return;
        if(target.Primary) throw new InvalidOperationException("Refusing to detach the primary display.");
        var mode=Mode(target.Name); mode.dmPelsWidth=0; mode.dmPelsHeight=0; mode.dmFields=0x20|0x80000|0x100000;
        int status=ChangeDisplaySettingsEx(target.Name, ref mode, IntPtr.Zero, 1|0x10000000, IntPtr.Zero);
        if(status==0) status=ApplyAll(null,IntPtr.Zero,IntPtr.Zero,0,IntPtr.Zero);
        if(status!=0) throw new InvalidOperationException("Detaching virtual display failed: " + status);
    }
    static bool Overlaps(Display a, Display b) { return a.X < b.X+b.Width && a.X+a.Width > b.X && a.Y < b.Y+b.Height && a.Y+a.Height > b.Y; }
}
