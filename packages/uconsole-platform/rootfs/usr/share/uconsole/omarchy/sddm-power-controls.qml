  // uConsole power controls: native SDDM actions, always confirmed.
  property string uconsolePowerAction: ""

  function requestPower(action) {
    root.uconsolePowerAction = action;
    cancelPower.forceActiveFocus();
  }
  function cancelPowerRequest() {
    root.uconsolePowerAction = "";
    password.forceActiveFocus();
  }

  component PowerButton: Controls.Button {
    id: powerButton
    implicitWidth: 128
    implicitHeight: 36
    activeFocusOnTab: true
    contentItem: Text {
      text: powerButton.text
      color: powerButton.enabled ? "#ffffff" : "#777777"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 14
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
      color: powerButton.down ? "#462511" : (powerButton.hovered ? "#292521" : "#191b1c")
      border.color: powerButton.activeFocus || powerButton.hovered ? "#ff6b1a" : "#62625e"
      border.width: 1
      radius: 2
    }
  }

  Row {
    id: powerControls
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 20
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 12
    enabled: root.uconsolePowerAction === ""
    PowerButton {
      id: restartPower
      text: "Restart"
      enabled: sddm.canReboot
      onClicked: root.requestPower("restart")
      KeyNavigation.tab: shutdownPower
      KeyNavigation.backtab: password
    }
    PowerButton {
      id: shutdownPower
      text: "Shut down"
      enabled: sddm.canPowerOff
      onClicked: root.requestPower("shutdown")
      KeyNavigation.tab: password
      KeyNavigation.backtab: restartPower
    }
  }

  Rectangle {
    id: powerConfirmation
    anchors.fill: parent
    z: 100
    color: root.color
    visible: root.uconsolePowerAction !== ""
    // Consume pointer input outside the dialog rather than passing it to login.
    MouseArea { anchors.fill: parent }
    Keys.onEscapePressed: root.cancelPowerRequest()
    Rectangle {
      width: Math.min(360, parent.width - 32)
      height: 174
      anchors.centerIn: parent
      color: "#191b1c"
      border.color: "#ff6b1a"
      radius: 2
      Text {
        anchors.top: parent.top
        anchors.topMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.uconsolePowerAction === "restart" ? "Restart uConsole?" : "Shut down uConsole?"
        color: "#ffffff"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 18
      }
      Text {
        anchors.centerIn: parent
        text: "Any running sessions will end."
        color: "#aaaaaa"
        font.pixelSize: 13
      }
      Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        PowerButton {
          id: cancelPower
          text: "Cancel"
          onClicked: root.cancelPowerRequest()
          KeyNavigation.tab: confirmPower
          KeyNavigation.backtab: confirmPower
        }
        PowerButton {
          id: confirmPower
          text: root.uconsolePowerAction === "restart" ? "Restart" : "Shut down"
          enabled: root.uconsolePowerAction === "restart" ? sddm.canReboot : sddm.canPowerOff
          onClicked: {
            if (root.uconsolePowerAction === "restart" && sddm.canReboot) sddm.reboot();
            else if (root.uconsolePowerAction === "shutdown" && sddm.canPowerOff) sddm.powerOff();
          }
          KeyNavigation.tab: cancelPower
          KeyNavigation.backtab: cancelPower
        }
      }
    }
  }
