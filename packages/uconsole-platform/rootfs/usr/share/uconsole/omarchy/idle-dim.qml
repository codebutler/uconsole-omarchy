
  // uConsole: part of the native idle service, not a competing idle daemon.
  // Serialise transitions: activity during a dim command must still restore.
  property string uconsoleDimDesired: "restore"
  function uconsoleSyncDim() {
    if (uconsoleDimProcess.running) return
    uconsoleDimProcess.command = ["uconsole-idle-backlight", uconsoleDimDesired]
    uconsoleDimProcess.running = true
  }
  IdleMonitor {
    id: uconsoleDimMonitor
    timeout: 120
    enabled: root.idleEnabled
    respectInhibitors: true
    onIsIdleChanged: {
      root.uconsoleDimDesired = isIdle && enabled ? "dim" : "restore"
      root.uconsoleSyncDim()
    }
    onEnabledChanged: {
      if (!enabled) {
        root.uconsoleDimDesired = "restore"
        root.uconsoleSyncDim()
      }
    }
  }
  Process {
    id: uconsoleDimProcess
    onExited: {
      if (command[1] !== root.uconsoleDimDesired) root.uconsoleSyncDim()
    }
  }
