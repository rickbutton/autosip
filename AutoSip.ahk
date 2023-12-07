#SingleInstance force
#NoEnv  
#Warn  
#Persistent

global ConfigFileName = "AutoSip.ini"
global ConfigSection = "AutoSip"
; configuration options
; these get set in configuration mode
global ConfigFlaskDuration := []
ConfigFlaskDuration[1] := 0
ConfigFlaskDuration[2] := 0
ConfigFlaskDuration[3] := 0
ConfigFlaskDuration[4] := 0
ConfigFlaskDuration[5] := 0
global ConfigQuickSilverFlask := 5
global ConfigIsConfigMode := false
global ConfigCurrentFlask := 1
; end config

; constants
global WinTitle = "Path of Exile"
global DurationFuzz := 50
global FlaskRegEx = "Om)Item Class: (?P<class>.*)`r`nRarity: .*`r`n(?P<name>.*)"
global FlaskDurationRegEx = "Om)Lasts ([\d.]+) (?:\(augmented\) )?Seconds"
global QuickSilverFlaskMod = "40% increased Movement Speed"
global ToolTipX := Round(A_ScreenWidth * 0.35)
global ToolTipY := Round(A_ScreenHeight * 0.84375)
global StatusToolTipX := Round(A_ScreenWidth * 0.35)
global StatusToolTipY := Round(A_ScreenHeight * 0.86458)
; end constants

; script state
global ScriptStartModTime := 0
global GameIsActive := false
global AutoSipEnabled := false
global FlaskDuration := []
global FlaskLastUsed := []
global HoldAttack := false
global HoldMove := false
global LastAttack := 0
global LastMove := 0
; end script state

FileGetTime ScriptStartModTime, %A_ScriptFullPath%
LoadSettings()

CoordMode, ToolTip, Screen
SetTimer CheckUpdates, 250
SetTimer TimerTick, 50

ClearMessage() { 
	ToolTip
}

ShowMessage(msg) {
	gameActive := WinActive(WinTitle)

	ClearMessage()
	ToolTip %msg%, ToolTipX, ToolTipY
	SetTimer ClearMessage, -1000

	if (gameActive) {
		WinActivate, %WinTitle%
	}
}

GetFuzz() {
	Random, delay, -DurationFuzz, DurationFuzz
	return delay
}

TrackFlaskSip(flask) {
    FlaskLastUsed[flask] := A_TickCount
	FlaskDuration[flask] := ConfigFlaskDuration[flask]
}

FuzzFlaskDuration(flask) {
	fuzz := GetFuzz()
	FlaskDuration[flask] := FlaskDuration[flask] + fuzz
	Sleep % fuzz
}

ShouldSipFlask(flask) {
	duration := FlaskDuration[flask]
	use := (duration > 0) && (duration < A_TickCount - FlaskLastUsed[flask])
	return use
}

SipFlask(flask) {
	if (!GameIsActive) {
		return
	}
	if (ShouldSipFlask(flask)) {
		Send % flask
		TrackFlaskSip(flask)
		FuzzFlaskDuration(flask)
	}
}

SipAllFlasks() {
	if (!GameIsActive) {
		return
	}
	for flask in FlaskDuration {
		SipFlask(flask)
	}
}

ToggleAutoSip() {
	if (!WinExist(WinTitle)) {
		ShowMessage("AutoSip: PoE not found!")
		return
	}
	if (!GameIsActive) {
		return
	}

    AutoSipEnabled := not AutoSipEnabled
	if (AutoSipEnabled) {
		; initialize start of auto-flask use
		
		; reset usage timers for all flasks
		for i in ConfigFlaskDuration {
			FlaskLastUsed[i] := 0
			FlaskDuration[i] := ConfigFlaskDuration[i]
		}
	}
}

TrackAttack(isup) {
	if (!GameIsActive) {
		return 1
	}
	if (!isup) {
		HoldAttack := true
		LastAttack := A_TickCount
	} else {
		HoldAttack := false
	}
}

TrackMove(isup) {
	if (!GameIsActive) {
		return 1
	}
	if (!isup) {
		HoldMove := true
		LastMove := A_TickCount
	} else {
		HoldMove := false
	}
}

WriteSettings() {
	IniDelete %ConfigFileName%, %ConfigSection%
	for i in ConfigFlaskDuration {
		d := ConfigFlaskDuration[i]
		IniWrite %d%, %ConfigFileName%, %ConfigSection%, Flask%i%
	}
	IniWrite %ConfigQuickSilverFlask%, %ConfigFileName%, %ConfigSection%, QuickSilver
	IniWrite false, %ConfigFileName%, %ConfigSection%, IsConfigMode
}

LoadSettings() {
	for i in ConfigFlaskDuration {
		d := 0
		IniRead d, %ConfigFileName%, %ConfigSection%, Flask%i%, 0
		ConfigFlaskDuration[i] := d
	}
	IniRead ConfigQuickSilverFlask, %ConfigFileName%, %ConfigSection%, QuickSilver, 5
	IniRead ConfigIsConfigMode, %ConfigFileName%, %ConfigSection%, IsConfigMode, true
	ConfigIsConfigMode := ConfigIsConfigMode == "true"
}

NextConfigureStep() {
	ConfigCurrentFlask := ConfigCurrentFlask + 1
	if (ConfigCurrentFlask == 6) {
		ConfigIsConfigMode := false
		ConfigCurrentFlask := 1
		WriteSettings()
	}
}

ConfigureBack() {
	if (ConfigCurrentFlask > 1) {
		ConfigCurrentFlask := 1
	}
}

ConfigureCopy() {
	if (!ConfigIsConfigMode) {
		return
	}

	MouseGetPos, xpos, ypos
	cb := A_Clipboard

	if (RegExMatch(cb, FlaskRegEx, pat) == 0) {
		ShowMessage("not an item? wtf are you doing?")
		return
	}
	type := pat["class"]
	name := pat["name"]
	if (type == "Utility Flasks") {
		if (RegExMatch(cb, FlaskDurationRegEx, timePat) == 0) {
			ShowMessage("error: unexpected format for utility flask duration")
			return
		}

		time := timePat[1] * 1000
		ConfigFlaskDuration[ConfigCurrentFlask] := time

		suffix := "I'll press it!"
		if (InStr(cb, QuickSilverFlaskMod)) {
			ConfigQuickSilverFlask := ConfigCurrentFlask
			suffix := "Speed!"
		}

		ShowMessage("Flask " . ConfigCurrentFlask . " (" . name . ") lasts " . Floor(time) . "ms. " . suffix)
		NextConfigureStep()
	} else if (type == "Life Flasks" || type == "Mana Flasks" || type == "Hybrid Flasks") {
		ShowMessage("Flask " . ConfigCurrentFlask . " (" . name . ") will be ignored, it isn't a utility flask.")
		ConfigFlaskDuration[ConfigCurrentFlask] = 0
		NextConfigureStep()
	} else {
		ShowMessage("not a flask? " . name)
	}
}

AutoSip() {
	; have we attacked in the last 0.5 seconds?
	if (((A_TickCount - LastAttack) < 500) || HoldAttack) {
		SipAllFlasks()
	}
	if (((A_TickCount - LastMove) < 500) || HoldMove) {
		SipFlask(ConfigQuickSilverFlask)
	}
}

Configure() {
	if (!GameIsActive) {
		return
	}
	ConfigIsConfigMode := true
}

CheckUpdates() {
    global ScriptStartModTime
    FileGetTime curModTime, %A_ScriptFullPath%
    If (curModTime != ScriptStartModTime) {
		Reload
		ScriptStartModTime := curModTime
		ShowMessage("restart failed!")
	}
}

UpdateStatus(msg) {
	gameActive := WinActive(WinTitle)

	ToolTip %msg%, StatusToolTipX, StatusToolTipY, 2

	if (gameActive) {
		WinActivate, %WinTitle%
	}
}

TimerTick() {
	if (WinExist(WinTitle)) {
		if (ConfigIsConfigMode) {
			UpdateStatus("Ctrl-C each flask: Flask " . ConfigCurrentFlask . "`nCtrl-Shift-C to restart")
		} else if (WinActive(WinTitle)) {
			GameIsActive := true
			if (AutoSipEnabled) {
				UpdateStatus("AutoSip: ENABLED")
				AutoSip()
			} else {
				UpdateStatus("AutoSip: DISABLED")
			}
		} else {
			GameIsActive := false
			UpdateStatus("AutoSip: PoE is not the active window!")
		}
	}
}

!Ins::ToggleAutoSip()
^Ins::Configure()

~e::TrackAttack(false)
~e up::TrackAttack(true)

~^c up::ConfigureCopy()
~^+c up::ConfigureBack()

~LButton::TrackMove(false)
~LButton up::TrackMove(true)

~1::TrackFlaskSip(1)
~2::TrackFlaskSip(2)
~3::TrackFlaskSip(3)
~4::TrackFlaskSip(4)
~5::TrackFlaskSip(5)