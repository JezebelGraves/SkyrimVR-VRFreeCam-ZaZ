Scriptname VRFreeCam Hidden
{Skyrim VR free-camera lock for the player on a device / animation spot.
A straight port of SexLab VR patch's 3rd-person mode (sslActorAlias.LockVRIK / MoveMyself /
UnlockVRIK + sslActorLibrary.SetVrSettings thirdPerson=1), which is also what OStim VR's
OStim.dll does natively (OStimVR::VRIKLockPositionAndRotation).

How it works: the player ACTOR is the camera and keeps thumbstick movement. VRIK draws the
body pinned at an exact world coordinate (lockPosition=2) and angle, so walking away leaves the
posed body on the device. Player collision is off so you can walk through the furniture.
Never SetVehicle / SetDontMove / TranslateTo the player while this is active.

SetFirstPerson/SetThirdPerson/ToggleView exist but are NOT bound to any button; the view is chosen
automatically per device. Real furniture (ZaZ) calls Freeze() after the lock so the sit pose holds.
1st person = SexLab VR's Switch3rdPerson() "lockHmdToBody" branch with SL's default config values.

This one script is shared, byte for byte, by every VRFreeCam patch (ZaZ 8 / Display Model DM3 /
Devious Devices NG), so any combination of them can be installed in any order. It has no dependency
on ZaZ, Devious Devices, Display Model or PO3 Papyrus Extender; it needs only VRIK and PapyrusUtil.
Devious Devices' pose replay (which needs PO3) lives in VRFreeCamDD, shipped by the DD patch only.
Console escape: cgf "VRFreeCam.PanicReset"}

String Function KeyActive() global
	Return "VRFreeCam.Active"
EndFunction

String Function KeySneak() global
	Return "VRFreeCam.SetComfortSneak"
EndFunction

; 0 = 3rd person free cam, 1 = 1st person (camera in the body's head)
String Function KeyView() global
	Return "VRFreeCam.View"
EndFunction

String Function KeyX() global
	Return "VRFreeCam.X"
EndFunction

String Function KeyY() global
	Return "VRFreeCam.Y"
EndFunction

String Function KeyZ() global
	Return "VRFreeCam.Z"
EndFunction

; mod event fired by the VRIK gesture profile while locked.
String Function EventToggle() global
	Return "VRFreeCam_ToggleView"
EndFunction

; Lock the player's VRIK body onto spot (plus optional angle offset) and free the camera.
; aiDelay: seconds to keep the player AI-driven first so a package-driven idle (DM3) can start.
Function Lock(Actor who, ObjectReference spot, Float angleOffset = 0.0, Float aiDelay = 2.0) global
	If(who == None || spot == None || who != Game.GetPlayer())
		Return
	EndIf

	; SexLab never translates the player -- a live TranslateTo would drag the camera back.
	who.StopTranslation()

	Debug.Trace("VRFreeCam: Lock on " + spot + " aiDelay " + aiDelay)
	If(aiDelay > 0.0)
		Utility.Wait(aiDelay)
	EndIf

	LockAt(who, spot.GetPositionX(), spot.GetPositionY(), spot.GetPositionZ(), spot.GetAngleZ() + angleOffset)
EndFunction

; Same as Lock, but pins the body wherever the player is standing/sitting right now. For real
; Furniture (ZaZ) the engine has already put the actor on the furniture marker, which is the
; exact spot -- the furniture ref's own origin is not (markers carry offsets).
Function LockHere(Actor who, Float aiDelay = 1.5) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf

	If(aiDelay > 0.0)
		Utility.Wait(aiDelay)
	EndIf

	LockAt(who, who.GetPositionX(), who.GetPositionY(), who.GetPositionZ(), who.GetAngleZ())
EndFunction

Function LockAt(Actor who, Float x, Float y, Float z, Float ang) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf

	; walk through the device instead of being shoved off it (OStim g_bDisablePlayerCollision).
	Utility.SetINIBool("bDisablePlayerCollision:Havok",TRUE)

	; SexLab forces comfort sneak on so physically crouching doesn't toggle sneak.
	If(!Utility.GetINIBool("bComfortSneak:VR"))
		Utility.SetINIBool("bComfortSneak:VR",TRUE)
		StorageUtil.SetIntValue(None,KeySneak(),1)
	EndIf

	; SetVrSettings(thirdPerson=1) -- the parts both views share.
	VRIK.VrikSetSetting("enablePosture", 0)
	VRIK.VrikSetSetting("enableBody", 0)
	VRIK.VrikSetSetting("enableJumping", 0)
	VRIK.VrikSetSetting("displayHolsters", 0)
	VRIK.VrikSetSetting("lockHeightToBody", 1)
	VRIK.VrikSetSetting("enableLeftArm", 0)
	VRIK.VrikSetSetting("enableRightArm", 0)

	; MoveMyself(): pin the body to the exact spot + facing instead of "wherever I stand now".
	While(ang < 0.0)
		ang += 360.0
	EndWhile
	While(ang >= 360.0)
		ang -= 360.0
	EndWhile
	VRIK.VrikSetSetting("lockRotation", 1)
	VRIK.VrikSetSetting("lockRotationAngle", ang)
	VRIK.VrikSetSetting("lockPositionX", x)
	VRIK.VrikSetSetting("lockPositionY", y)
	VRIK.VrikSetSetting("lockPositionZ", z)
	VRIK.VrikSetSetting("lockPosition", 2)

	StorageUtil.SetFloatValue(None,KeyX(),x)
	StorageUtil.SetFloatValue(None,KeyY(),y)
	StorageUtil.SetFloatValue(None,KeyZ(),z)
	StorageUtil.SetIntValue(None,KeyActive(),1)

	SetThirdPerson(who)

	; No VRIK gesture profile and no hotkey: the view is chosen automatically per device
	; (Freeze for real furniture). ToggleView() stays callable but nothing binds it.

	Debug.Trace("VRFreeCam: locked body to " + x + "," + y + "," + z + " angle " + ang)
EndFunction

; 3rd person free cam: SexLab VR Switch3rdPerson() is3rdPerson branch.
Function SetThirdPerson(Actor who) global
	StorageUtil.SetIntValue(None,KeyView(),0)

	VRIK.VrikSetSetting("enableHead", 0)
	VRIK.VrikSetSetting("hidePlayerHeadDistance", 2.0)
	VRIK.VrikSetSetting("lockHmdMinThreshold", 500.0)
	VRIK.VrikSetSetting("lockHmdMaxThreshold", 500.0)
	VRIK.VrikSetSetting("lockHmdSpeed", 60.0)
	VRIK.VrikSetSetting("lockHmdToBody", 0)

	; controls: exactly SexLab's 3rd-person set. movement/looking/menu/journal ON,
	; fighting/camswitch/sneak/activate OFF, player not AI-driven.
	who.SetDontMove(FALSE)
	Game.SetPlayerAIDriven(FALSE)
	Game.EnablePlayerControls(TRUE,FALSE,FALSE,TRUE,FALSE,TRUE,FALSE,TRUE,0)
	Game.DisablePlayerControls(FALSE,TRUE,TRUE,FALSE,TRUE,FALSE,TRUE,FALSE,0)
	Utility.SetINIBool("bDisablePlayerCollision:Havok",TRUE)
EndFunction

; 1st person: camera snapped into the body's head. SexLab VR Switch3rdPerson() else-branch with
; Config.lockHmdToBody=true and SL's defaults (HideHeadDist 16, HmdDis 2, HmdTol 20, HmdSpd 20,
; VRIKtrackHead on). The camera actor is brought back onto the spot first, since in 3rd person
; it may have walked anywhere.
Function SetFirstPerson(Actor who) global
	StorageUtil.SetIntValue(None,KeyView(),1)

	Game.SetPlayerAIDriven(TRUE)
	; VR thumbstick movement ignores DisablePlayerControls -- SetDontMove is what stops it.
	who.SetDontMove(TRUE)
	who.SetPosition(StorageUtil.GetFloatValue(None,KeyX()), StorageUtil.GetFloatValue(None,KeyY()), StorageUtil.GetFloatValue(None,KeyZ()))

	VRIK.VrikSetSetting("hidePlayerHeadDistance", 16.0)
	VRIK.VrikSetSetting("lockHeightToBody", 1)
	VRIK.VrikSetSetting("enableHead", 1)
	VRIK.VrikSetSetting("lockHmdToBody", 1)
	VRIK.VrikSetSetting("lockHmdMinThreshold", 2.0)
	VRIK.VrikSetSetting("lockHmdMaxThreshold", 20.0)
	VRIK.VrikSetSetting("lockHmdSpeed", 20.0)
EndFunction

; v6 "eyes view" for furniture: like SetFirstPerson (HMD snapped into the pinned body's head, camera actor back on the
; body spot, no walking) but WITHOUT SetPlayerAIDriven, so Activate / key events keep working exactly as in the
; third-person phase. SetThirdPerson (or UnlockInPlace/FullReset) undoes everything this sets.
Function SetEyes(Actor who) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf
	StorageUtil.SetIntValue(None,KeyView(),1)
	who.SetDontMove(TRUE)
	who.SetPosition(StorageUtil.GetFloatValue(None,KeyX()), StorageUtil.GetFloatValue(None,KeyY()), StorageUtil.GetFloatValue(None,KeyZ()))

	VRIK.VrikSetSetting("hidePlayerHeadDistance", 16.0)
	VRIK.VrikSetSetting("lockHeightToBody", 1)
	VRIK.VrikSetSetting("enableHead", 1)
	VRIK.VrikSetSetting("lockHmdToBody", 1)
	VRIK.VrikSetSetting("lockHmdMinThreshold", 2.0)
	VRIK.VrikSetSetting("lockHmdMaxThreshold", 20.0)
	VRIK.VrikSetSetting("lockHmdSpeed", 20.0)
	Debug.Trace("VRFreeCam: view -> eyes")
EndFunction

; Real Furniture (ZaZ): the player actor must NOT walk -- thumbstick movement breaks the sit pose
; even though the engine still reports sitting (confirmed live 2026-09-30). Keep the body pin
; from LockAt, just stop the camera actor moving. Verified live in-headset on a ZaZ horse.
Function Freeze(Actor who) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf
	Game.SetPlayerAIDriven(TRUE)
	who.SetDontMove(TRUE)
EndFunction

Function ToggleView() global
	If(StorageUtil.GetIntValue(None,KeyActive(),0) != 1)
		Return
	EndIf

	Actor player = Game.GetPlayer()
	If(StorageUtil.GetIntValue(None,KeyView(),0) == 0)
		SetFirstPerson(player)
	Else
		SetThirdPerson(player)
	EndIf
	Debug.Trace("VRFreeCam: view -> " + StorageUtil.GetIntValue(None,KeyView(),0))
EndFunction

; Put the player back (the camera may be anywhere), restore collision/sneak/VRIK.
; Safe to call when not locked.
Function Unlock(Actor who, Float x, Float y, Float z) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf

	If(StorageUtil.GetIntValue(None,KeyActive(),0) == 1)
		who.SetPosition(x, y, z + 10.0)
		Utility.Wait(0.1)
	EndIf

	UnlockInPlace(who)
EndFunction

; Unlock without moving the player (ZaZ: the engine already stood them up off the furniture).
Function UnlockInPlace(Actor who) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf
	; diagnostics 2026-09-30: who released the player? (needs Papyrus logging on)
	Debug.TraceStack("VRFreeCam: UnlockInPlace called")

	; v3: unconditional -- a second/duplicate unlock (KeyActive already 0) must still free the player
	who.SetDontMove(FALSE)
	Game.SetPlayerAIDriven(FALSE)

	Utility.SetINIBool("bDisablePlayerCollision:Havok",FALSE)
	If(StorageUtil.GetIntValue(None,KeySneak(),0) == 1)
		Utility.SetINIBool("bComfortSneak:VR",FALSE)
		StorageUtil.UnsetIntValue(None,KeySneak())
	EndIf

	VRIK.VrikRestoreSettings()
	StorageUtil.UnsetIntValue(None,KeyActive())
	StorageUtil.UnsetIntValue(None,KeyView())
	Debug.Trace("VRFreeCam: unlocked")
EndFunction

; ===========================================================================================
; v3 (2026-10-30 proposal): alignment helpers, re-pin, diagnostics and a complete reset.
; All angles are Skyrim degrees (clockwise from north). Local frame of a reference with heading a:
;   +Y = forward (sin a, cos a), +X = right (cos a, -sin a).
; ===========================================================================================
Float Function LocalToWorldX(Float ax, Float ay, Float ang, Float ox, Float oy) global
	Return ax + ox * Math.Cos(ang) + oy * Math.Sin(ang)
EndFunction

Float Function LocalToWorldY(Float ax, Float ay, Float ang, Float ox, Float oy) global
	Return ay - ox * Math.Sin(ang) + oy * Math.Cos(ang)
EndFunction

Float Function WorldToLocalX(Float ax, Float ay, Float ang, Float wx, Float wy) global
	Float dx = wx - ax
	Float dy = wy - ay
	Return dx * Math.Cos(ang) - dy * Math.Sin(ang)
EndFunction

Float Function WorldToLocalY(Float ax, Float ay, Float ang, Float wx, Float wy) global
	Float dx = wx - ax
	Float dy = wy - ay
	Return dx * Math.Sin(ang) + dy * Math.Cos(ang)
EndFunction

Float Function NormAngle(Float a) global
	While(a > 180.0)
		a -= 360.0
	EndWhile
	While(a <= -180.0)
		a += 360.0
	EndWhile
	Return a
EndFunction

; Is VRIK still pinning the body? (something else -- another VRIK mod, a SexLab scene, a load -- can clear it)
Bool Function IsPinned() global
	Return VRIK.VrikGetSetting("lockPosition") == 2.0
EndFunction

; Move only the pin (calibration / watchdog); everything else stays as LockAt left it.
Function Repin(Float x, Float y, Float z, Float ang) global
	While(ang < 0.0)
		ang += 360.0
	EndWhile
	While(ang >= 360.0)
		ang -= 360.0
	EndWhile
	VRIK.VrikSetSetting("lockRotation", 1)
	VRIK.VrikSetSetting("lockRotationAngle", ang)
	VRIK.VrikSetSetting("lockPositionX", x)
	VRIK.VrikSetSetting("lockPositionY", y)
	VRIK.VrikSetSetting("lockPositionZ", z)
	VRIK.VrikSetSetting("lockPosition", 2)
	StorageUtil.SetFloatValue(None,KeyX(),x)
	StorageUtil.SetFloatValue(None,KeyY(),y)
	StorageUtil.SetFloatValue(None,KeyZ(),z)
EndFunction

; Is VRFreeCam currently holding the player? (set by LockAt, cleared by UnlockInPlace)
Bool Function IsActive() global
	Return StorageUtil.GetIntValue(None,KeyActive(),0) == 1
EndFunction

; One-line state dump for the Papyrus log -- grep "VRFreeCam: DUMP". Use it at every step while tuning.
Function Dump(String tag, Actor who, ObjectReference furn) global
	String s = "VRFreeCam: DUMP " + tag + " actor=" + who.GetPositionX() + "," + who.GetPositionY() + "," + who.GetPositionZ() + " ang=" + who.GetAngleZ() + " sit=" + who.GetSitState()
	If(furn)
		s += " furn=" + furn.GetPositionX() + "," + furn.GetPositionY() + "," + furn.GetPositionZ() + " fang=" + furn.GetAngleZ()
	EndIf
	s += " vrikPin=" + VRIK.VrikGetSetting("lockPosition") + " pinXYZ=" + VRIK.VrikGetSetting("lockPositionX") + "," + VRIK.VrikGetSetting("lockPositionY") + "," + VRIK.VrikGetSetting("lockPositionZ") + " pinAng=" + VRIK.VrikGetSetting("lockRotationAngle")
	Debug.Trace(s)
EndFunction

; Complete, idempotent reset of everything VRFreeCam changes on the player. Safe to call twice / when not locked.
; moveToExit: first put the player (the camera actor, which may be across the room) at x,y,z / ang.
; NOTE: the caller (zbfSlot) must afterwards call zbf.ReapplyPlayerControls() so ZaZ's own control mask is re-imposed.
Function FullReset(Actor who, Bool moveToExit = False, Float x = 0.0, Float y = 0.0, Float z = 0.0, Float ang = 0.0) global
	If(who == None || who != Game.GetPlayer())
		Return
	EndIf
	Debug.Trace("VRFreeCam: FullReset moveToExit=" + moveToExit)

	; nothing may drag or hold the camera any more
	who.StopTranslation()
	who.SetVehicle(None)
	who.SetDontMove(FALSE)
	Game.SetPlayerAIDriven(FALSE)

	; drop the body pin first (HMD stays where it is), then put the camera actor where the body was
	VRIK.VrikSetSetting("lockHmdToBody", 2)
	VRIK.VrikSetSetting("lockPosition", 0)
	VRIK.VrikSetSetting("lockRotation", 0)
	VRIK.VrikSetSetting("lockRotationAngle", -1.0)
	If(moveToExit)
		who.SetPosition(x, y, z)
		who.SetAngle(0.0, 0.0, ang)
		Utility.Wait(0.2)
	EndIf

	; drop the pose, then restore VRIK / INI / sneak
	Debug.SendAnimationEvent(who, "IdleForceDefaultState")
	UnlockInPlace(who)

	; SetThirdPerson turned fighting/camera-switch/sneak/activate off -- all of it back on
	; (SetThirdPerson's DisablePlayerControls is the one ZaZ's ReapplyPlayerControls never undoes: it passes
	; abCamSwitch=False, abLooking=False, i.e. "leave alone")
	Game.EnablePlayerControls(TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,0)
EndFunction

; CONSOLE ESCAPE (v4): no arguments, so it works from the console:   cgf "VRFreeCam.PanicReset"
; Frees the player completely (pin, camera, controls, collision, VRIK). zbfSlot notices on its next 0.5 s tick that
; VRFreeCam is no longer active and drops its own flags.
Function PanicReset() global
	Actor p = Game.GetPlayer()
	Debug.Trace("VRFreeCam: PanicReset")
	FullReset(p, False)
	Game.EnablePlayerControls(TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,TRUE,0)
	Debug.Notification("VRFreeCam: reset")
EndFunction
