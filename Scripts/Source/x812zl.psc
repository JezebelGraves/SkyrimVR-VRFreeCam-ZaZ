Scriptname x812zl Hidden
{ZaZ VR Lock - PUBLIC RELEASE HOOK. Call these from NPC package / dialogue / scene fragments, the Serana mod or any
other mod. No properties, globals only. Mods that don't want a script dependency can use the mod events instead:
  SendModEvent("x812zl_Release", "<reason>")            (sender form = releaser actor, optional)
  SendModEvent("x812zl_RequestRescue")                  (sender form = preferred rescuer, optional)
Outbound events: x812zl_Locked, x812zl_Released, x812zl_RescueStarted, x812zl_RescueFailed.
Console:  cgf "x812zl.Release" "test"    cgf "x812zl.Panic"}

x812zl_Core Function Core() global
	Return Game.GetFormFromFile(0x00000805, "ZazVRLock.esp") as x812zl_Core
EndFunction

; True while the player is held (set-up or locked)
Bool Function IsLocked() global
	x812zl_Core c = Core()
	Return c && c.Phase >= 1 && c.Phase <= 2
EndFunction

; 0 none, 1 Self (entered by hand), 2 Locked (seated by a mod/NPC, or DommeLock)
Int Function GetMode() global
	x812zl_Core c = Core()
	If c && c.Phase >= 1 && c.Phase <= 2
		Return c.Mode
	EndIf
	Return 0
EndFunction

ObjectReference Function GetFurniture() global
	x812zl_Core c = Core()
	If c && c.Phase >= 1 && c.Phase <= 2
		Return c.Furn
	EndIf
	Return None
EndFunction

; Proper release: camera, VRIK, HIGGS hands and controls restored. Always allowed (also under DommeLock).
; Returns False if the player wasn't locked.
Bool Function Release(String reason = "api", Actor releaser = None) global
	x812zl_Core c = Core()
	If c == None
		Return False
	EndIf
	Return c.Release(reason, releaser)
EndFunction

; Start a rescue: the preferred actor (or the nearest friendly NPC) walks to the furniture and releases the player.
Function RequestRescue(Actor preferred = None) global
	x812zl_Core c = Core()
	If c
		c.RequestRescue(preferred)
	EndIf
EndFunction

; DommeLock: A / self-release gesture refuse; this hook still releases.
Function SetDommeLock(Bool on) global
	If on
		StorageUtil.SetIntValue(None, "x812zl.DommeLock", 1)
	Else
		StorageUtil.UnsetIntValue(None, "x812zl.DommeLock")
	EndIf
EndFunction

; Console escape: full reset even with a broken state.
Function Panic() global
	x812zl_Core c = Core()
	If c
		c.Panic()
	Else
		x812zl_Cam.Restore(Game.GetPlayer())
	EndIf
EndFunction


; Live pin calibration while locked (furniture frame: x right, y forward, z up, yaw degrees). Saved per furniture base.
;   cgf "x812zl.Nudge" 0 0 0 180    turn the body round
;   cgf "x812zl.Nudge" 0 -10 0 0    move the body 10 units towards the back of the piece
Function Nudge(Float dx, Float dy, Float dz, Float dyaw) global
	x812zl_Core c = Core()
	If c
		c.Nudge(dx, dy, dz, dyaw)
	EndIf
EndFunction

Function ClearCalibration() global
	x812zl_Core c = Core()
	If c
		c.ClearCalibration()
	EndIf
EndFunction


; Play the furniture pose again on the pinned body (also VRIK gesture "ZaZ VR Lock: re-pose").
Function Repose() global
	x812zl_Core c = Core()
	If c
		c.RePose("api")
	EndIf
EndFunction

; Camera: 0 (default) = hold the camera on a viewpoint looking at the posed body (pose never breaks);
; 1 = walk (the stick moves the camera; locomotion drops the pose, it replays when you stop).
Function SetWalkCam(Bool on) global
	StorageUtil.SetIntValue(None, "x812zl.CamMode", on as Int)
	x812zl_Core c = Core()
	If c && IsLocked()
		c.PlaceCamera("api")
	EndIf
EndFunction

; Next viewpoint (front -> right -> back -> left). Also VRIK gesture "ZaZ VR Lock: next view".
Function NextView() global
	x812zl_Core c = Core()
	If c
		c.NextView()
	EndIf
EndFunction


; Try another furniture pose on the device you are in, no reload (update9):
;   cgf "x812zl.TryPose" "ZaZRSPP01_Enter"     any ZaZ furniture Enter event
;   cgf "x812zl.TryPose" ""                    back to the table pose (also forgets a saved one)
;   cgf "x812zl.KeepPose"                      keep the tried pose for this furniture type
Function TryPose(String enterEv) global
	x812zl_Core c = Core()
	If c
		c.TryPose(enterEv)
	EndIf
EndFunction

Function KeepPose() global
	x812zl_Core c = Core()
	If c
		c.KeepPose()
	EndIf
EndFunction


; ---------------------------------------------------------------------------------- external holds (update10)
; For framework adapters (e.g. the Devious Devices VR patch). ApiVersion() >= 2 means these exist.
Int Function ApiVersion() global
	Return 2
EndFunction

Bool Function ExtBegin(ObjectReference device, String tag) global
	x812zl_Core c = Core()
	Return c && c.ExtBegin(device, tag)
EndFunction

Bool Function ExtLock(Float x, Float y, Float z, Float angle, String loopEvent, String exitEvent = "", Float keepAliveSeconds = 0.0) global
	x812zl_Core c = Core()
	Return c && c.ExtLock(x, y, z, angle, loopEvent, exitEvent, keepAliveSeconds)
EndFunction

Function ExtPlay(String ev, Float holdSeconds) global
	x812zl_Core c = Core()
	If c
		c.ExtPlay(ev, holdSeconds)
	EndIf
EndFunction

Function ExtSetLoop(String ev) global
	x812zl_Core c = Core()
	If c
		c.ExtSetLoop(ev)
	EndIf
EndFunction

Bool Function ExtRelease(String reason = "framework") global
	x812zl_Core c = Core()
	Return c && c.ExtRelease(reason)
EndFunction

Bool Function IsExtHeld(ObjectReference device = None) global
	x812zl_Core c = Core()
	Return c && c.IsExtHeld(device)
EndFunction

; framework: "my device cleanup after x812zl_ExtRelease is finished" (ExtRelease does the same)
Function ExtCleanupDone() global
	x812zl_Core c = Core()
	If c
		c.ExtCleanupDone()
	EndIf
EndFunction

; 1 (default) = the self-release gesture releases for sure; 0 = it sends x812zl_ExtSelfRelease to the device instead
Function ExtSetSelfRelease(Int mode) global
	x812zl_Core c = Core()
	If c
		c.ExtSetSelfRelease(mode)
	EndIf
EndFunction
