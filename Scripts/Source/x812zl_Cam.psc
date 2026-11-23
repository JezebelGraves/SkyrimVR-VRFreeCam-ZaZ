Scriptname x812zl_Cam Hidden
{ZaZ VR Lock - camera core (global functions only).
VRIK body pin + walking camera actor = the SexLab VR / OStim VR third-person free cam (same values as VRFreeCam.LockAt
and SetThirdPerson). Every VRIK / INI / HIGGS / control value we change is snapshotted first and restored value by value
(never VrikRestoreSettings except in Panic with no snapshot, never VrikSaveSettings).
Never: tfc, SetVehicle on the player, ForceThirdPerson/ForceFirstPerson.}

String Function SnapKey(String k) global
	Return "x812zl.snap." + k
EndFunction

String[] Function VrikKeys() global
	String[] k = new String[19]
	k[0] = "enableLeftArm"
	k[1] = "enableRightArm"
	k[2] = "enableBody"
	k[3] = "enablePosture"
	k[4] = "enableJumping"
	k[5] = "enableHead"
	k[6] = "displayHolsters"
	k[7] = "lockHeightToBody"
	k[8] = "hidePlayerHeadDistance"
	k[9] = "lockHmdToBody"
	k[10] = "lockHmdMinThreshold"
	k[11] = "lockHmdMaxThreshold"
	k[12] = "lockHmdSpeed"
	k[13] = "lockPosition"
	k[14] = "lockPositionX"
	k[15] = "lockPositionY"
	k[16] = "lockPositionZ"
	k[17] = "lockRotation"
	k[18] = "lockRotationAngle"
	Return k
EndFunction

Bool Function HasSnapshot() global
	Return StorageUtil.GetIntValue(None, "x812zl.snap.has", 0) == 1
EndFunction

; Take the snapshot (VRIK keys, 9 control getters, 2 INI bools, HIGGS hands). Stored in StorageUtil so it survives a save.
Function Snapshot() global
	String[] k = VrikKeys()
	Int i = 0
	While i < k.Length
		StorageUtil.SetFloatValue(None, SnapKey(k[i]), VRIK.VrikGetSetting(k[i]))
		i += 1
	EndWhile
	Int c = 0
	If Game.IsMovementControlsEnabled()
		c += 1
	EndIf
	If Game.IsFightingControlsEnabled()
		c += 2
	EndIf
	If Game.IsCamSwitchControlsEnabled()
		c += 4
	EndIf
	If Game.IsLookingControlsEnabled()
		c += 8
	EndIf
	If Game.IsSneakingControlsEnabled()
		c += 16
	EndIf
	If Game.IsMenuControlsEnabled()
		c += 32
	EndIf
	If Game.IsActivateControlsEnabled()
		c += 64
	EndIf
	If Game.IsJournalControlsEnabled()
		c += 128
	EndIf
	StorageUtil.SetIntValue(None, "x812zl.snap.ctl", c)
	; baseline: a snapshot taken within 15 s of a release can still carry another mod's left-over mask -> keep the old one
	Float lastRel = StorageUtil.GetFloatValue(None, "x812zl.lastRelease", -100.0)
	If !StorageUtil.HasIntValue(None, "x812zl.base.ctl") || Utility.GetCurrentRealTime() - lastRel > 15.0 || Utility.GetCurrentRealTime() < lastRel
		StorageUtil.SetIntValue(None, "x812zl.base.ctl", c)
	EndIf
	StorageUtil.SetIntValue(None, "x812zl.snap.sneak", Utility.GetINIBool("bComfortSneak:VR") as Int)
	StorageUtil.SetIntValue(None, "x812zl.snap.coll", Utility.GetINIBool("bDisablePlayerCollision:Havok") as Int)
	StorageUtil.SetIntValue(None, "x812zl.snap.higgsL", HiggsVR.IsDisabled(True) as Int)
	StorageUtil.SetIntValue(None, "x812zl.snap.higgsR", HiggsVR.IsDisabled(False) as Int)
	StorageUtil.SetIntValue(None, "x812zl.snap.has", 1)
	Debug.Trace("x812zl: snapshot taken (controls mask " + c + ", baseline " + StorageUtil.GetIntValue(None, "x812zl.base.ctl", c) + ", lockPosition " + VRIK.VrikGetSetting("lockPosition") + ")")
EndFunction

Function ClearSnapshot() global
	String[] k = VrikKeys()
	Int i = 0
	While i < k.Length
		StorageUtil.UnsetFloatValue(None, SnapKey(k[i]))
		i += 1
	EndWhile
	StorageUtil.UnsetIntValue(None, "x812zl.snap.ctl")
	StorageUtil.UnsetIntValue(None, "x812zl.snap.sneak")
	StorageUtil.UnsetIntValue(None, "x812zl.snap.coll")
	StorageUtil.UnsetIntValue(None, "x812zl.snap.higgsL")
	StorageUtil.UnsetIntValue(None, "x812zl.snap.higgsR")
	StorageUtil.UnsetIntValue(None, "x812zl.snap.has")
EndFunction

Float Function NormAngle360(Float a) global
	While a < 0.0
		a += 360.0
	EndWhile
	While a >= 360.0
		a -= 360.0
	EndWhile
	Return a
EndFunction

; Body pin only (watchdog re-pin / moving furniture).
Function Repin(Float x, Float y, Float z, Float ang) global
	VRFreeCam.Repin(x, y, z, PinAngle(ang))
EndFunction

Bool Function IsPinned() global
	Return VRFreeCam.IsPinned()
EndFunction

; update8: the full pin check. VRFreeCam.IsPinned() only looks at lockPosition; VRIK's own furniture-exit handler
; (it runs late, after the stand-up) and a teleport of the camera actor can reset the position AND/OR the rotation
; lock (11/8 logs: lockPosition 2 but lockRotationAngle -1 on the bed). Without the rotation lock the body turns with
; the camera actor, which faces the body from the viewpoint = the body ends up facing backwards / twisted.
Bool Function IsPinnedAt(Float x, Float y, Float ang) global
	If VRIK.VrikGetSetting("lockPosition") != 2.0 || VRIK.VrikGetSetting("lockRotation") != 1.0
		Return False
	EndIf
	If Math.Abs(VRIK.VrikGetSetting("lockPositionX") - x) > 2.0 || Math.Abs(VRIK.VrikGetSetting("lockPositionY") - y) > 2.0
		Return False
	EndIf
	Float ra = VRIK.VrikGetSetting("lockRotationAngle")
	If ra < 0.0
		Return False
	EndIf
	Float d = Math.Abs(ra - PinAngle(ang))
	Return d < 2.0 || d > 358.0
EndFunction

; update9: VRIK's own seat handling restores its saved settings when the sit ends. On slow pieces (shackle pole 6:
; VRIK's seat lock was still 0 at our snapshot) that restore lands AFTER our lock and turns arms, body IK and posture
; back on: hands active, and the body IK bends the pinned body towards the headset 170 units away = twisted.
; LockIntact checks every value the lock owns; Reassert puts them all back (no control / SetDontMove changes).
Bool Function LockIntact(Float x, Float y, Float ang) global
	If !IsPinnedAt(x, y, ang)
		Return False
	EndIf
	Return BodyIntact()
EndFunction

Bool Function BodyIntact() global
	If VRIK.VrikGetSetting("enableLeftArm") != 0.0 || VRIK.VrikGetSetting("enableRightArm") != 0.0
		Return False
	EndIf
	If VRIK.VrikGetSetting("enableBody") != 0.0 || VRIK.VrikGetSetting("enablePosture") != 0.0 || VRIK.VrikGetSetting("enableHead") != 0.0
		Return False
	EndIf
	If VRIK.VrikGetSetting("lockHmdToBody") != 0.0
		Return False
	EndIf
	Return HiggsVR.IsDisabled(True) && HiggsVR.IsDisabled(False)
EndFunction

; what is broken, for the log
String Function LockDiag() global
	Return "pos " + VRIK.VrikGetSetting("lockPosition") as Int + " rot " + VRIK.VrikGetSetting("lockRotation") as Int + "@" + VRIK.VrikGetSetting("lockRotationAngle") as Int + " arms " + VRIK.VrikGetSetting("enableLeftArm") as Int + VRIK.VrikGetSetting("enableRightArm") as Int + " body " + VRIK.VrikGetSetting("enableBody") as Int + " posture " + VRIK.VrikGetSetting("enablePosture") as Int + " head " + VRIK.VrikGetSetting("enableHead") as Int + " hmdLock " + VRIK.VrikGetSetting("lockHmdToBody") as Int + " higgsOff " + HiggsVR.IsDisabled(True) as Int + HiggsVR.IsDisabled(False) as Int
EndFunction

; the VRIK body values of VRFreeCam.LockAt + SetThirdPerson, the pin, and the HIGGS hand block - nothing else.
Function Reassert(Float x, Float y, Float z, Float ang) global
	VRIK.VrikSetSetting("enablePosture", 0)
	VRIK.VrikSetSetting("enableBody", 0)
	VRIK.VrikSetSetting("enableJumping", 0)
	VRIK.VrikSetSetting("displayHolsters", 0)
	VRIK.VrikSetSetting("lockHeightToBody", 1)
	VRIK.VrikSetSetting("enableLeftArm", 0)
	VRIK.VrikSetSetting("enableRightArm", 0)
	VRIK.VrikSetSetting("enableHead", 0)
	VRIK.VrikSetSetting("hidePlayerHeadDistance", 2.0)
	VRIK.VrikSetSetting("lockHmdMinThreshold", 500.0)
	VRIK.VrikSetSetting("lockHmdMaxThreshold", 500.0)
	VRIK.VrikSetSetting("lockHmdSpeed", 60.0)
	VRIK.VrikSetSetting("lockHmdToBody", 0)
	Repin(x, y, z, ang)
	; only the hand that is on again (a repeated disable must never need a repeated enable)
	If !HiggsVR.IsDisabled(True)
		HiggsVR.DisableHand(True)
	EndIf
	If !HiggsVR.IsDisabled(False)
		HiggsVR.DisableHand(False)
	EndIf
EndFunction

; VRIK uses -1 as "no rotation lock"; keep the angle strictly inside (0, 360) so 0 can never be read as "unset".
Float Function PinAngle(Float ang) global
	Float a = NormAngle360(ang)
	If a < 0.05
		a = 0.05
	EndIf
	Return a
EndFunction

; Full lock through the VRFreeCam API (the shared VRFreeCam.pex, Papyrus only = SexLab VR's 3rd-person mode):
; LockAt pins the VRIK body at x,y,z / ang (arms, body, posture off = the body follows the animation), unlocks the HMD
; (enableHead 0, lockHmdToBody 0) and sets SexLab's 3rd-person controls. Then: hands off, Activate back on (our exit
; button, as in v1.1), and the camera mode (ApplyCam) decides whether the camera actor may walk.
Function Pin(Actor who, Float x, Float y, Float z, Float ang) global
	VRFreeCam.LockAt(who, x, y, z, PinAngle(ang))
	HandsOff()
	Game.EnablePlayerControls(False, False, False, False, False, False, True, False, 0)
	StorageUtil.SetIntValue(None, "VRFreeCam.Active", 1)
	StorageUtil.SetIntValue(None, "x812zl.Owner", 1)
EndFunction

; Camera modes. The posed body and the camera are the SAME actor (one animation graph): if the camera actor walks,
; locomotion replaces the furniture pose (11/8 test). So by default the camera actor is put on a viewpoint looking at
; the body and held there with SetDontMove (VR stick movement ignores DisablePlayerControls; SetDontMove is what stops
; it, VRFreeCam note) - no AI-driven, so Activate / gestures / keys keep working. The headset stays free (look, lean,
; step in your room); next view = another side of the device.
;   x812zl.CamMode 0 (default) = hold on a viewpoint;  1 = walk (stick moves the camera, the pose replays when you stop)
;   x812zl.View 0 front, 1 right, 2 back, 3 left;  distance = json view_dist (default 170)
Int Function CamMode() global
	Return StorageUtil.GetIntValue(None, "x812zl.CamMode", 0)
EndFunction

Function ApplyCam(Actor who, Float px, Float py, Float pz, Float pa, Float dist) global
	If CamMode() == 1
		who.SetDontMove(False)
		Game.EnablePlayerControls(True, False, False, False, False, False, False, False, 0)
		Return
	EndIf
	Int v = StorageUtil.GetIntValue(None, "x812zl.View", 0)
	Float lx = 0.0
	Float ly = dist
	Float face = pa + 180.0
	If v == 1
		lx = dist
		ly = 0.0
		face = pa + 270.0
	ElseIf v == 2
		lx = 0.0
		ly = 0.0 - dist
		face = pa
	ElseIf v == 3
		lx = 0.0 - dist
		ly = 0.0
		face = pa + 90.0
	EndIf
	who.SetDontMove(True)
	who.SetPosition(LocalToWorldX(px, py, pa, lx, ly), LocalToWorldY(px, py, pa, lx, ly), pz)
	who.SetAngle(0.0, 0.0, NormAngle360(face))
	; update8: moving the camera actor is a teleport, and VRIK drops its body pin on it (11/8: vrikPin 0 right after
	; every camera placement) -> for that moment the body is drawn on the camera actor, 170 units away and facing the
	; other way. Put the pin straight back; the caller then waits until it holds (Core.EnsurePin).
	Reassert(px, py, pz, pa)
EndFunction

Function HandsOff() global
	HiggsVR.DisableHand(True)
	HiggsVR.DisableHand(False)
EndFunction

; Release: drop the pin (HMD stays where it is), put the camera actor on the exit spot, then restore everything.
; Release order (11/8 update6): graph out of the loop (exit anim if known, then default state), VRFreeCam UnlockInPlace,
; VRIK snapshot (pin keys forced OFF), don't-move / AI cleared, controls last (Restore), then the caller verifies.
Function Unpin(Actor who, Bool moveToExit, Float x, Float y, Float z, Float ang, String exitEv = "") global
	who.StopTranslation()
	If moveToExit
		who.SetPosition(x, y, z)
		who.SetAngle(0.0, 0.0, ang)
		Utility.Wait(0.2)
	EndIf
	If exitEv != ""
		Debug.SendAnimationEvent(who, exitEv)
		Utility.Wait(0.6)
	EndIf
	Debug.SendAnimationEvent(who, "IdleForceDefaultState")
	VRFreeCam.UnlockInPlace(who)
	Restore(who)
EndFunction

; VRIK pin keys are run-time state, not settings. VRIK sets them itself while the player sits in furniture, and the
; snapshot is taken right after the sit (11/8 log: snapshot lockPosition 2 + VRIK's own seat pin) -> never restore those.
Function UnpinVrik() global
	VRIK.VrikSetSetting("lockPosition", 0.0)
	VRIK.VrikSetSetting("lockRotation", 0.0)
	VRIK.VrikSetSetting("lockRotationAngle", -1.0)
EndFunction

; ZaZ bits (zbfBondageShell.WornPlayerControlMask: 1 move, 2 fight, 4 sneak, 8 menu, 16 activate) -> our snapshot bits
Int Function ZazToCtl(Int z) global
	Int c = 0
	If Math.LogicalAnd(z, 1) != 0
		c += 1
	EndIf
	If Math.LogicalAnd(z, 2) != 0
		c += 2
	EndIf
	If Math.LogicalAnd(z, 4) != 0
		c += 16
	EndIf
	If Math.LogicalAnd(z, 8) != 0
		c += 32
	EndIf
	If Math.LogicalAnd(z, 16) != 0
		c += 64
	EndIf
	Return c
EndFunction

Int Function CtlNow() global
	Int c = 0
	If Game.IsMovementControlsEnabled()
		c += 1
	EndIf
	If Game.IsFightingControlsEnabled()
		c += 2
	EndIf
	If Game.IsCamSwitchControlsEnabled()
		c += 4
	EndIf
	If Game.IsLookingControlsEnabled()
		c += 8
	EndIf
	If Game.IsSneakingControlsEnabled()
		c += 16
	EndIf
	If Game.IsMenuControlsEnabled()
		c += 32
	EndIf
	If Game.IsActivateControlsEnabled()
		c += 64
	EndIf
	If Game.IsJournalControlsEnabled()
		c += 128
	EndIf
	Return c
EndFunction

; The controls a release must give back: snapshot + baseline + what the lock itself takes (movement 1, sneak 16,
; activate 64), minus what worn ZaZ restraints legitimately block (gag / armbinder / hobble keywords).
Int Function CtlTarget(Int snap, Int base, Int zazWorn) global
	Int t = Math.LogicalOr(Math.LogicalOr(snap, base), 81)
	Return Math.LogicalAnd(t, Math.LogicalXor(255, ZazToCtl(zazWorn)))
EndFunction

Function EnableCtl(Int c) global
	Game.EnablePlayerControls(Math.LogicalAnd(c, 1) != 0, Math.LogicalAnd(c, 2) != 0, Math.LogicalAnd(c, 4) != 0, Math.LogicalAnd(c, 8) != 0, Math.LogicalAnd(c, 16) != 0, Math.LogicalAnd(c, 32) != 0, Math.LogicalAnd(c, 64) != 0, Math.LogicalAnd(c, 128) != 0, 0)
EndFunction

; Value-by-value restore from the snapshot. No snapshot (panic on a broken state) -> VRIK's own saved settings.
Function Restore(Actor who) global
	who.SetDontMove(False)
	Game.SetPlayerAIDriven(False)
	If HasSnapshot()
		String[] k = VrikKeys()
		Int i = 0
		While i < 13	; 0-12 = settings; 13-18 = pin state (lockPosition..lockRotationAngle), forced off below
			VRIK.VrikSetSetting(k[i], StorageUtil.GetFloatValue(None, SnapKey(k[i]), VRIK.VrikGetSettingDefault(k[i])))
			i += 1
		EndWhile
		UnpinVrik()
		Utility.SetINIBool("bComfortSneak:VR", StorageUtil.GetIntValue(None, "x812zl.snap.sneak", 0) == 1)
		Utility.SetINIBool("bDisablePlayerCollision:Havok", StorageUtil.GetIntValue(None, "x812zl.snap.coll", 0) == 1)
		If StorageUtil.GetIntValue(None, "x812zl.snap.higgsL", 0) == 0
			HiggsVR.EnableHand(True)
		EndIf
		If StorageUtil.GetIntValue(None, "x812zl.snap.higgsR", 0) == 0
			HiggsVR.EnableHand(False)
		EndIf
		Int c = StorageUtil.GetIntValue(None, "x812zl.snap.ctl", 255)
		StorageUtil.SetIntValue(None, "x812zl.rel.ctl", c)	; kept for the post-release verify
		; re-enable what was enabled before the lock (False = leave alone); the verify adds baseline + lock bits
		EnableCtl(c)
		ClearSnapshot()
	Else
		VRIK.VrikRestoreSettings()
		UnpinVrik()
		StorageUtil.SetIntValue(None, "x812zl.rel.ctl", 255)
		Utility.SetINIBool("bDisablePlayerCollision:Havok", False)
		HiggsVR.EnableHand(True)
		HiggsVR.EnableHand(False)
		Game.EnablePlayerControls(True, True, True, True, True, True, True, True, 0)
	EndIf
	If StorageUtil.GetIntValue(None, "x812zl.Owner", 0) == 1
		; VRFreeCam's own bookkeeping from LockAt / Repin (we restored the INI values from our snapshot ourselves)
		StorageUtil.UnsetIntValue(None, "VRFreeCam.Active")
		StorageUtil.UnsetIntValue(None, "VRFreeCam.View")
		StorageUtil.UnsetIntValue(None, "VRFreeCam.SetComfortSneak")
		StorageUtil.UnsetFloatValue(None, "VRFreeCam.X")
		StorageUtil.UnsetFloatValue(None, "VRFreeCam.Y")
		StorageUtil.UnsetFloatValue(None, "VRFreeCam.Z")
		StorageUtil.UnsetIntValue(None, "x812zl.Owner")
	EndIf
EndFunction

; furniture local frame helpers (Skyrim degrees, +Y forward)
Float Function LocalToWorldX(Float ax, Float ay, Float ang, Float ox, Float oy) global
	Return ax + ox * Math.Cos(ang) + oy * Math.Sin(ang)
EndFunction
Float Function LocalToWorldY(Float ax, Float ay, Float ang, Float ox, Float oy) global
	Return ay - ox * Math.Sin(ang) + oy * Math.Cos(ang)
EndFunction
Float Function WorldToLocalX(Float ax, Float ay, Float ang, Float wx, Float wy) global
	Return (wx - ax) * Math.Cos(ang) - (wy - ay) * Math.Sin(ang)
EndFunction
Float Function WorldToLocalY(Float ax, Float ay, Float ang, Float wx, Float wy) global
	Return (wx - ax) * Math.Sin(ang) + (wy - ay) * Math.Cos(ang)
EndFunction

Function Dump(String tag, Actor who, ObjectReference furn) global
	String s = "x812zl: DUMP " + tag + " actor=" + who.GetPositionX() + "," + who.GetPositionY() + "," + who.GetPositionZ() + " ang=" + who.GetAngleZ() + " sit=" + who.GetSitState()
	If furn
		s += " furn=" + furn.GetPositionX() + "," + furn.GetPositionY() + "," + furn.GetPositionZ() + " fang=" + furn.GetAngleZ()
	EndIf
	s += " vrikPin=" + VRIK.VrikGetSetting("lockPosition") + " pin=" + VRIK.VrikGetSetting("lockPositionX") + "," + VRIK.VrikGetSetting("lockPositionY") + "," + VRIK.VrikGetSetting("lockPositionZ") + " pinAng=" + VRIK.VrikGetSetting("lockRotationAngle")
	Debug.Trace(s)
EndFunction

