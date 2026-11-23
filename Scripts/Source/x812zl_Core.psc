Scriptname x812zl_Core extends Quest
{ZaZ VR Lock - core state machine (build step 1).
IDLE(0) -> SETUP(1) -> LOCKED(2) -> RELEASING(3) -> IDLE. Every latent step re-checks the token; a release or panic
bumps the token so a set-up still in flight bails out instead of pinning after the release.
Every ZaZ piece is handled the same way (DESIGN rev 3): the engine finishes the sit, the player is stood up, the
furniture's own Enter animation is played on the spot (unseated), then the VRIK body is pinned and the camera actor
walks free. Never seated, never frozen, never SetVehicle, never tfc.
Public API for other mods: script x812zl (globals) or the mod events x812zl_Release / x812zl_RequestRescue.
Console escape: cgf "x812zl.Panic"}

GlobalVariable Property x812zl_Enabled Auto
GlobalVariable Property x812zl_CoffinLidClose Auto
GlobalVariable Property x812zl_Locked Auto
GlobalVariable Property x812zl_RescueMinutes Auto
GlobalVariable Property x812zl_Debug Auto
Actor Property PlayerRef Auto

String Property JsonFile = "x812zl/furniture" AutoReadOnly
String Property LearnFile = "x812zl/calibration" AutoReadOnly

Int Property Phase = 0 Auto Hidden			; 0 idle, 1 set-up, 2 locked, 3 releasing
Int Property Mode = 0 Auto Hidden			; 1 Self (entered by hand), 2 Locked (mod/NPC/Domme)
ObjectReference Property Furn Auto Hidden

Int Token = 0
Float PinX
Float PinY
Float PinZ
Float PinA
Float LocX			; pin in the furniture's local frame (moving furniture re-pin)
Float LocY
Float LocZ
Float LocA
Float FurnX
Float FurnY
Float FurnZ
Float FurnA
Float ExitX
Float ExitY
Float ExitZ
String PoseEv = ""
String MarkerKey = ""
String LoopEv = ""			; the piece's looping idle (FNIS fu chain: Enter is one-shot, Loop is cyclic); "" = none known
Float KeepAt = 0.0			; next keep-alive Loop re-send (real time)
Float LastFull = 0.0			; last full Enter->Loop replay (rate limit)
Int LastDriven = -1			; last logged bAnimationDriven (-1 unknown)
String EnterEv = ""			; the furniture Enter event (PoseEv may become a random loop variant)
Bool LoopStarted = False		; update8: the loop idle is running -> camera moves never replay Enter
Int PinMiss = 0				; update8: consecutive watchdog ticks with a broken pin
; update10: external holds (framework adapters, e.g. the Devious Devices patch). The adapter's own script owns the
; device logic; the core owns the player (snapshot, pin, camera, keep-alive, checked release).
Bool Property ExtHold = False Auto Hidden
ObjectReference Property ExtRef Auto Hidden
String Property ExtTag = "" Auto Hidden
String ExtExit = ""
Bool ExtNoCallback = False
Bool ExtAck = False
Int ExtSelfMode = 1			; 1 = self-release is a guaranteed release, 0 = ask the framework (x812zl_ExtSelfRelease)
Float KeepIv = 0.0
Int GetUps = 0				; OnGetUp counter (the engine's furniture exit finishes late, after our stand-up)
Float LastGetUp = 0.0
Float RePoseAt = 0.0
Bool PoseMoved = False
Int StillTicks = 0
Int MeshKind = 0			; 0 none, 1 coffin (xPlayFurnitureOpenClose), 2 machine (wncRapingMachineScript)
Bool LidClosedByUs = False
ObjectReference ZazSeatFurn		; a SetFurniture() from ZaZ / another mod seen just before or after OnSit
Float ZazSeatTime = 0.0
ObjectReference UnblockFurn
Float UnblockAt = 0.0
Float LockedAt = 0.0
Float RescueAt = 0.0
Bool Rescuing = False
Int KeyA2
Int KeyA5
Int KeyA7

; ------------------------------------------------------------------------------------------------ startup
Event OnInit()
	Startup()
EndEvent

Function OnGameLoad()
	Startup()
	If Phase == 1 || Phase == 3
		; saved mid set-up / mid release: nothing half-applied may survive -> complete restore
		Log("load during phase " + Phase + " -> restoring")
		Token += 1
		FinishRestore("load-midway", False)
	ElseIf Phase == 2
		Utility.Wait(1.2)
		ReapplyAfterLoad()
	ElseIf x812zl_Cam.HasSnapshot()
		; idle but a snapshot is left over (should not happen): repair from it
		Log("stale snapshot while idle -> restoring it")
		x812zl_Cam.Restore(PlayerRef)
	EndIf
EndFunction


Function Startup()
	RegisterForModEvent("x812zl_Release", "OnApiRelease")
	RegisterForModEvent("x812zl_RequestRescue", "OnApiRescue")
	RegisterForModEvent("x812zl_ZazSeat", "OnZazSeat")
	RegisterForModEvent("x812zl_SelfRelease", "OnSelfGesture")
	RegisterForModEvent("x812zl_CallHelp", "OnHelpGesture")
	VRIK.VrikAddGestureAction("x812zl_SelfRelease", "ZaZ VR Lock: release me")
	VRIK.VrikAddGestureAction("x812zl_CallHelp", "ZaZ VR Lock: call for help")
	RegisterForModEvent("x812zl_Repose", "OnReposeGesture")
	VRIK.VrikAddGestureAction("x812zl_Repose", "ZaZ VR Lock: re-pose")
	RegisterForModEvent("x812zl_NextView", "OnViewGesture")
	VRIK.VrikAddGestureAction("x812zl_NextView", "ZaZ VR Lock: next view")
	RegisterForModEvent("x812zl_ToggleWalk", "OnWalkGesture")
	VRIK.VrikAddGestureAction("x812zl_ToggleWalk", "ZaZ VR Lock: walk / hold camera")
	If x812zl_Locked
		x812zl_Locked.SetValue((Phase == 2) as Float)
	EndIf
	Log("started (phase " + Phase + ")")
EndFunction

Function Log(String s)
	Debug.Trace("x812zl: " + s)
EndFunction

Bool Function Enabled()
	Return x812zl_Enabled == None || x812zl_Enabled.GetValue() > 0.0
EndFunction

; ------------------------------------------------------------------------------------------------ detection
Int Function ZazLocal(Form f)
	If f == None
		Return -1
	EndIf
	Int lid = Math.LogicalAnd(f.GetFormID(), 0x00FFFFFF)
	If Game.GetFormFromFile(lid, "ZaZAnimationPack.esm") == f
		Return lid
	EndIf
	Return -1
EndFunction

Bool Function IsZaz(ObjectReference f)
	If f == None
		Return False
	EndIf
	Keyword gk = Game.GetFormFromFile(0x0000762B, "ZaZAnimationPack.esm") as Keyword
	Return gk != None && f.HasKeyword(gk)
EndFunction

; pose = per-base table (precomputed from ZaZ's own FurnitureKeywords order + the esm IDLE tree), else any ZaZ keyword
; on the base, else the json fallback.
String Function PoseFor(ObjectReference f)
	Form b = f.GetBaseObject()
	Int lid = ZazLocal(b)
	String ev = ""
	If lid >= 0
		ev = JsonUtil.GetStringValue(LearnFile, "pose_b" + lid, "")
		If ev != ""
			Return ev
		EndIf
		ev = JsonUtil.GetStringValue(JsonFile, "b" + lid, "")
		If ev != ""
			Return ev
		EndIf
	EndIf
	Int n = b.GetNumKeywords()
	Int i = 0
	While i < n
		Int kl = ZazLocal(b.GetNthKeyword(i))
		If kl >= 0
			ev = JsonUtil.GetStringValue(JsonFile, "k" + kl, "")
			If ev != ""
				Return ev
			EndIf
		EndIf
		i += 1
	EndWhile
	Return JsonUtil.GetStringValue(JsonFile, "fallback", "")
EndFunction

String Function BaseKey(ObjectReference f)
	Return "b" + ZazLocal(f.GetBaseObject())
EndFunction

Bool Function DommeLocked()
	Return StorageUtil.GetIntValue(None, "x812sq.DommeLock", 0) == 1 || StorageUtil.GetIntValue(None, "x812zl.DommeLock", 0) == 1
EndFunction

; ------------------------------------------------------------------------------------------------ OnSit (from the player alias)
Function HandleSit(ObjectReference akFurniture)
	If !Enabled() || akFurniture == None
		Return
	EndIf
	If !IsZaz(akFurniture)
		Return
	EndIf
	If Phase != 0
		Log("OnSit ignored, phase " + Phase + " (" + akFurniture + ")")
		Return
	EndIf
	; atomic claim: no latent call between the check above and this line
	Phase = 1
	Token += 1
	Int my = Token
	If StorageUtil.GetIntValue(None, "VRFreeCam.Active", 0) == 1 && StorageUtil.GetIntValue(None, "x812zl.Owner", 0) != 1
		Log("OnSit ignored: another VR camera owner holds the player (VRFreeCam.Active)")
		Phase = 0
		Return
	EndIf
	If PlayerRef.GetDistance(akFurniture) > 300.0
		Log("OnSit ignored: furniture too far " + PlayerRef.GetDistance(akFurniture))
		Phase = 0
		Return
	EndIf
	Furn = akFurniture
	Mode = 1
	If DommeLocked() || (ZazSeatFurn == akFurniture && Utility.GetCurrentRealTime() - ZazSeatTime < 30.0)
		Mode = 2
	EndIf
	PoseEv = PoseFor(akFurniture)
	MeshKind = 0
	If (akFurniture as xPlayFurnitureOpenClose) != None
		MeshKind = 1
	ElseIf (akFurniture as wncRapingMachineScript) != None
		MeshKind = 2
	EndIf
	LidClosedByUs = False
	Log("lock start " + akFurniture + " base " + BaseKey(akFurniture) + " pose '" + PoseEv + "' mode " + Mode + " mesh " + MeshKind)
	x812zl_Cam.Snapshot()
	; no walking out of the seat while we read it (in VR the stick stands you up); Pin gives movement back to the camera
	Game.DisablePlayerControls(True, False, False, False, False, False, False, False, 0)
	PlayerRef.SetDontMove(True)		; the VR stick ignores DisablePlayerControls
	ArmExit()
	akFurniture.BlockActivation(True)
	Setup(my)
EndFunction

Function Setup(Int my)
	ObjectReference f = Furn
	; (1) let the engine finish snapping us onto the marker (position stable for 3 polls)
	Utility.Wait(0.8)
	Float px = PlayerRef.GetPositionX()
	Float py = PlayerRef.GetPositionY()
	Float pz = PlayerRef.GetPositionZ()
	Int stable = 0
	Int n = 0
	Bool seated = PlayerRef.GetSitState() == 3
	Float sx = px
	Float sy = py
	Float sz = pz
	While stable < 3 && n < 25
		Utility.Wait(0.2)
		If my != Token
			Return
		EndIf
		Float cx = PlayerRef.GetPositionX()
		Float cy = PlayerRef.GetPositionY()
		Float cz = PlayerRef.GetPositionZ()
		If Math.Abs(cx - px) < 0.25 && Math.Abs(cy - py) < 0.25 && Math.Abs(cz - pz) < 0.25
			stable += 1
		Else
			stable = 0
		EndIf
		px = cx
		py = cy
		pz = cz
		If PlayerRef.GetSitState() == 3
			seated = True
			sx = cx
			sy = cy
			sz = cz
		EndIf
		n += 1
	EndWhile
	x812zl_Cam.Dump("1-settled(polls=" + n + ", seated sample " + seated + ")", PlayerRef, f)
	If my != Token
		Return
	EndIf

	; (2) leave the seat the way ZaZ itself does, then stand on the spot
	Int g0 = GetUps
	PlayerRef.MoveTo(PlayerRef)
	Int tries = 0
	While PlayerRef.GetSitState() != 0 && tries < 10
		Utility.Wait(0.1)
		tries += 1
	EndWhile
	If PlayerRef.GetSitState() != 0
		Debug.SendAnimationEvent(PlayerRef, "IdleForceDefaultState")
		Utility.Wait(0.5)
	EndIf
	If my != Token
		Return
	EndIf
	If PlayerRef.GetSitState() != 0
		Log("could not leave the seat (sit state " + PlayerRef.GetSitState() + ") -> restoring, player stays in the normal game seat")
		Token += 1
		FinishRestore("detach-failed", False)
		Return
	EndIf
	; the furniture exit keeps running after the sit state drops (its OnGetUp arrived ~1 s later in the 11/8 logs and
	; overrode the enter pose). Wait for it, then for 1.5 s without another one (a second one came ~1 s later).
	Int w = 0
	While GetUps == g0 && w < 30
		Utility.Wait(0.1)
		w += 1
	EndWhile
	w = 0
	While Utility.GetCurrentRealTime() - LastGetUp < 1.5 && w < 25
		Utility.Wait(0.1)
		w += 1
	EndWhile
	If my != Token
		Return
	EndIf

	; (3) pin spot + facing = the furniture marker baked in the furniture's NIF (offset + heading, local frame),
	; i.e. exactly where the engine would seat you. Multi-seat: the marker nearest to where we were seated.
	; Never the free standing position (step-1 bug: if you had already left the seat we pinned you there).
	FurnX = f.GetPositionX()
	FurnY = f.GetPositionY()
	FurnZ = f.GetPositionZ()
	FurnA = f.GetAngleZ()
	String bk = BaseKey(f)
	Float qx = px
	Float qy = py
	If seated
		qx = sx
		qy = sy
	EndIf
	Float slx = x812zl_Cam.WorldToLocalX(FurnX, FurnY, FurnA, qx, qy)
	Float sly = x812zl_Cam.WorldToLocalY(FurnX, FurnY, FurnA, qx, qy)
	Float mlx = 0.0
	Float mly = 0.0
	Float mlz = 0.0
	; facing: the NIF marker heading (local, relative to the furniture). No marker -> the furniture's own angle
	; (yaw 0 = PinA = furniture angle, the way the engine seats you on a marker with heading 0).
	Float mla = JsonUtil.GetFloatValue(JsonFile, "yaw_default", 0.0)
	String src = "origin + furniture angle (no nif marker)"
	Int mc = JsonUtil.FloatListCount(JsonFile, "mk_" + bk) / 4
	If mc > 0
		Int best = 0
		Float bestD = 1000000000.0
		Int i = 0
		While i < mc
			Float dx = JsonUtil.FloatListGet(JsonFile, "mk_" + bk, i * 4) - slx
			Float dy = JsonUtil.FloatListGet(JsonFile, "mk_" + bk, i * 4 + 1) - sly
			If dx * dx + dy * dy < bestD
				bestD = dx * dx + dy * dy
				best = i
			EndIf
			i += 1
		EndWhile
		mla = JsonUtil.FloatListGet(JsonFile, "mk_" + bk, best * 4 + 3)
		If !(mla >= -360.0 && mla <= 360.0)		; NaN / garbage heading -> furniture angle
			mla = 0.0
		EndIf
		; the marker's Z is the seat height that the furniture ANIMATION already contains (horse +90, gibbet +60):
		; the actor root stays on the furniture's base plane, exactly where the engine put us (seated sample).
		If seated
			mlx = slx
			mly = sly
			mlz = sz - FurnZ
			src = "seat + nif heading " + best + "/" + mc
		Else
			mlx = JsonUtil.FloatListGet(JsonFile, "mk_" + bk, best * 4)
			mly = JsonUtil.FloatListGet(JsonFile, "mk_" + bk, best * 4 + 1)
			src = "nif marker xy+heading " + best + "/" + mc
		EndIf
	ElseIf seated
		mlx = slx
		mly = sly
		mlz = sz - FurnZ
		src = "seated sample"
	EndIf
	MarkerKey = bk
	LocX = JsonUtil.GetFloatValue(JsonFile, "lx_" + bk, mlx) + JsonUtil.GetFloatValue(LearnFile, "dx_" + bk, 0.0)
	LocY = JsonUtil.GetFloatValue(JsonFile, "ly_" + bk, mly) + JsonUtil.GetFloatValue(LearnFile, "dy_" + bk, 0.0)
	LocZ = JsonUtil.GetFloatValue(JsonFile, "lz_" + bk, mlz) + JsonUtil.GetFloatValue(LearnFile, "dz_" + bk, 0.0)
	LocA = JsonUtil.GetFloatValue(JsonFile, "ya_" + bk, mla) + JsonUtil.GetFloatValue(LearnFile, "da_" + bk, 0.0)
	Log("ALIGN source=" + src + " seatLocal=" + slx + "," + sly)
	ComputePin()
	Log("ALIGN " + bk + " local=" + LocX + "," + LocY + "," + LocZ + " yaw=" + LocA + " -> body faces " + x812zl_Cam.NormAngle360(PinA) + " (furniture " + FurnA + ")")

	; (4) stand the body on the spot with the right heading (MoveTo offsets are world-axis)
	PlayerRef.MoveTo(f, PinX - FurnX, PinY - FurnY, PinZ - FurnZ, False)
	PlayerRef.SetAngle(0.0, 0.0, PinA)
	Utility.Wait(0.4)
	If my != Token
		Return
	EndIf

	; (5) play the furniture's own pose unseated and let it run (the pin keeps whatever frame the body is in)
	Int gq = GetUps
	EnterEv = PoseEv
	LoopEv = ""
	LoopStarted = False
	LastDriven = -1
	KeepAt = 0.0
	If PoseEv != ""
		LoopEv = JsonUtil.GetStringValue(JsonFile, "loop:" + PoseEv, "")
		Debug.SendAnimationEvent(PlayerRef, PoseEv)
	EndIf
	Utility.Wait(JsonUtil.GetFloatValue(JsonFile, "wait_" + bk, JsonUtil.GetFloatValue(JsonFile, "wait_default", 1.6)))
	If my != Token
		Return
	EndIf
	If GetUps != gq && PoseEv != ""
		Log("furniture exit landed after the pose -> stand on the spot again and replay it")
		PlayerRef.MoveTo(f, PinX - FurnX, PinY - FurnY, PinZ - FurnZ, False)
		PlayerRef.SetAngle(0.0, 0.0, PinA)
		Utility.Wait(0.3)
		ReplayPose()
		Utility.Wait(1.2)
		If my != Token
			Return
		EndIf
	EndIf
	If LoopEv != ""
		Debug.SendAnimationEvent(PlayerRef, LoopEv)
		Log("enter done -> loop idle " + LoopEv + " (json name; Papyrus may print another casing, graph events ignore case)")
	EndIf
	xRandomFurnitureIdle rnd = f as xRandomFurnitureIdle
	If rnd && rnd.AnimationEventNames.Length > 0
		String variant = rnd.AnimationEventNames[Utility.RandomInt(0, rnd.AnimationEventNames.Length - 1)]
		If variant != ""
			Debug.SendAnimationEvent(PlayerRef, variant)
			EnterEv = PoseEv
			PoseEv = variant
			LoopEv = variant
			Utility.Wait(0.8)
		EndIf
	EndIf
	If my != Token
		Return
	EndIf

	LoopStarted = True
	; update9: VRIK's own seat restore can still be on its way (it arrives with the late furniture exit): give it a
	; moment so it lands before our lock instead of after it (EnsurePin + watchdog still catch a later one)
	w = 0
	While Utility.GetCurrentRealTime() - LastGetUp < 1.0 && w < 15
		Utility.Wait(0.1)
		w += 1
	EndWhile
	; (6) pin the body WHILE the actor still stands on the spot, wait until VRIK really holds it (its own late
	; furniture-exit reset can wipe a fresh pin), and only then move the camera actor away (PlaceCamera re-pins
	; after the move and never replays Enter).
	x812zl_Cam.Pin(PlayerRef, PinX, PinY, PinZ, PinA)
	EnsurePin(my, "lock")
	If my != Token
		Return
	EndIf
	PlaceCamera("lock")
	MeshLock(False)
	Phase = 2
	LockedAt = Utility.GetCurrentRealTime()
	RescueAt = 0.0
	If x812zl_RescueMinutes && x812zl_RescueMinutes.GetValue() > 0.0
		RescueAt = LockedAt + x812zl_RescueMinutes.GetValue() * 60.0
	EndIf
	If x812zl_Locked
		x812zl_Locked.SetValue(1.0)
	EndIf
	x812zl_Cam.Dump("2-locked", PlayerRef, f)
	Log("locked on " + f + " pose " + PoseEv + " mode " + Mode)
	f.SendModEvent("x812zl_Locked", PoseEv, Mode as Float)
	RegisterForSingleUpdate(0.25)
EndFunction

Function ComputePin()
	PinX = x812zl_Cam.LocalToWorldX(FurnX, FurnY, FurnA, LocX, LocY)
	PinY = x812zl_Cam.LocalToWorldY(FurnX, FurnY, FurnA, LocX, LocY)
	PinZ = FurnZ + LocZ
	PinA = FurnA + LocA
	ExitX = PinX
	ExitY = PinY
	ExitZ = PinZ + 10.0
EndFunction

; coffins: lid shut over the pinned body (toggle x812zl_CoffinLidClose); machines: make sure the loop runs.
; ZaZ only drives these from OnActivate, which our stand-up / release never send.
Function MeshLock(Bool afterLoad)
	If MeshKind == 1
		If x812zl_CoffinLidClose == None || x812zl_CoffinLidClose.GetValue() > 0.0
			If !afterLoad || LidClosedByUs
				Furn.PlayGamebryoAnimation("close", True, 3.0)
				LidClosedByUs = True
			EndIf
		EndIf
	ElseIf MeshKind == 2	; machines: run the loop while locked (also after a load); MeshRelease stops it
		Furn.SetMotionType(Furn.Motion_Keyframed, True)
		Furn.PlayGamebryoAnimation("rape", True, 0.0)
	EndIf
EndFunction

Function MeshRelease(ObjectReference f)
	If f == None
		Return
	EndIf
	If MeshKind == 1 && LidClosedByUs
		f.PlayGamebryoAnimation("open", True, 1.0)
	ElseIf MeshKind == 2
		f.PlayGamebryoAnimation("rape", False, 0.1)	; ZaZ's own stop call (wncRapingMachineScript)
	EndIf
	LidClosedByUs = False
EndFunction

; ------------------------------------------------------------------------------------------------ watchdog (only while locked)
Event OnUpdate()
	Float now = Utility.GetCurrentRealTime()
	If UnblockFurn && now >= UnblockAt
		UnblockFurn.BlockActivation(False)
		UnblockFurn = None
	EndIf
	If Phase != 2
		If UnblockFurn
			RegisterForSingleUpdate(0.5)
		EndIf
		Return
	EndIf
	ObjectReference f = Furn
	If StorageUtil.GetIntValue(None, "VRFreeCam.Active", 0) != 1
		Log("watchdog: lock cleared from outside -> restoring")
		Release("outside-reset", None)
		Return
	EndIf
	If f == None || f.IsDisabled() || f.IsDeleted() || !f.Is3DLoaded()
		Release("furniture-gone", None)
		Return
	EndIf
	If PlayerRef.IsDead() || PlayerRef.IsBleedingOut()
		Release("death", None)
		Return
	EndIf
	If PlayerRef.GetParentCell() != f.GetParentCell() && PlayerRef.GetDistance(f) > 4000.0
		Release("teleport", None)
		Return
	EndIf
	If PlayerRef.GetDistance(f) > 4000.0
		Release("teleport", None)
		Return
	EndIf
	; moving furniture (lift-chain gibbets, wheels): follow it
	Float fx = f.GetPositionX()
	Float fy = f.GetPositionY()
	Float fz = f.GetPositionZ()
	Float fa = f.GetAngleZ()
	If Math.Abs(fx - FurnX) > 5.0 || Math.Abs(fy - FurnY) > 5.0 || Math.Abs(fz - FurnZ) > 5.0 || Math.Abs(fa - FurnA) > 2.0
		FurnX = fx
		FurnY = fy
		FurnZ = fz
		FurnA = fa
		ComputePin()
		x812zl_Cam.Reassert(PinX, PinY, PinZ, PinA)
	ElseIf !x812zl_Cam.LockIntact(PinX, PinY, PinA)
		PinMiss += 1
		If PinMiss <= 3 || PinMiss % 40 == 0
			Log("watchdog: lock values reset from outside (" + x812zl_Cam.LockDiag() + ", miss " + PinMiss + ") -> re-assert pin + arms + body + hands")
		EndIf
		x812zl_Cam.Reassert(PinX, PinY, PinZ, PinA)
	Else
		PinMiss = 0
	EndIf
	; pose keeper: the pinned body and the walking camera share ONE animation graph. Walking the camera plays
	; locomotion on it, which drops the furniture pose; when the camera stops, play the pose again.
	If RePoseAt > 0.0 && now >= RePoseAt
		RePose("late furniture exit")
	ElseIf PoseEv != "" && x812zl_Cam.CamMode() == 1
		Float spd = PlayerRef.GetAnimationVariableFloat("Speed")
		If spd > 10.0
			PoseMoved = True
			StillTicks = 0
		ElseIf PoseMoved
			StillTicks += 1
			If StillTicks >= 3
				RePose("camera stopped")
			EndIf
		EndIf
	EndIf
	KeepAlive(now)
	If RescueAt > 0.0 && now >= RescueAt && !Rescuing
		RescueAt = 0.0
		RequestRescue(None)
		If Phase != 2
			Return
		EndIf
	EndIf
	RegisterForSingleUpdate(0.25)
EndEvent

; ------------------------------------------------------------------------------------------------ save / load
Function ReapplyAfterLoad()
	If Phase != 2 || Furn == None
		Return
	EndIf
	If Furn.IsDisabled() || Furn.IsDeleted()
		Release("furniture-gone", None)
		Return
	EndIf
	PlayerRef.SetPosition(PinX, PinY, PinZ)
	PlayerRef.SetAngle(0.0, 0.0, PinA)
	Utility.Wait(0.36)
	If PoseEv != ""
		ReplayPose()
	EndIf
	If !ExtHold
		Furn.BlockActivation(True)
	EndIf
	LoopStarted = True
	x812zl_Cam.Pin(PlayerRef, PinX, PinY, PinZ, PinA)
	EnsurePin(Token, "load")
	PlaceCamera("lock")
	MeshLock(True)
	If !ExtHold
		ArmExit()
	EndIf
	Log("re-applied after load: pose " + PoseEv)
	RegisterForSingleUpdate(0.25)
EndFunction

; ------------------------------------------------------------------------------------------------ input
Function ArmExit()
	UnregisterForAllKeys()
	KeyA2 = Input.GetMappedKey("Activate", 2)
	KeyA5 = Input.GetMappedKey("Activate", 5)
	KeyA7 = Input.GetMappedKey("Activate", 7)
	If KeyA2 > 0
		RegisterForKey(KeyA2)
	EndIf
	If KeyA5 > 0
		RegisterForKey(KeyA5)
	EndIf
	If KeyA7 > 0
		RegisterForKey(KeyA7)
	EndIf
EndFunction

Event OnKeyDown(Int keyCode)
	If Utility.IsInMenuMode()
		Return
	EndIf
	If keyCode != KeyA2 && keyCode != KeyA5 && keyCode != KeyA7
		Return
	EndIf
	If Phase != 2
		; presses during the 3-6 s set-up are ignored (the sit-activation bounce released the player in the 10/31 build)
		Return
	EndIf
	SelfRelease("button")
EndEvent

Function SelfRelease(String how)
	If Phase != 2
		Return
	EndIf
	If ExtHold
		If ExtSelfMode == 0 && ExtRef
			; the framework asked to decide itself (its own menu / escape rules)
			ExtRef.SendModEvent("x812zl_ExtSelfRelease", how, 0.0)
			Return
		EndIf
		Release("self-" + how, None)	; guaranteed: framework cleanup event first, then the restore
		Return
	EndIf
	If Mode == 2 || DommeLocked()
		Debug.Notification("You're locked in.")
		Return
	EndIf
	Release("self-" + how, None)
EndFunction

Function OnSelfGesture(String eventName, String strArg, Float numArg, Form sender)
	SelfRelease("gesture")
EndFunction

Function OnHelpGesture(String eventName, String strArg, Float numArg, Form sender)
	RequestRescue(None)
EndFunction

; ------------------------------------------------------------------------------------------------ mod events
Function OnApiRelease(String eventName, String strArg, Float numArg, Form sender)
	String reason = strArg
	If reason == ""
		reason = "modevent"
	EndIf
	Release(reason, sender as Actor)
EndFunction

Function OnApiRescue(String eventName, String strArg, Float numArg, Form sender)
	RequestRescue(sender as Actor)
EndFunction

; from x812zl_Hook (inside ZaZ's zbfSlot.SetFurniture for the player): numArg 1 = a mod seated the player, 0 = released
Function OnZazSeat(String eventName, String strArg, Float numArg, Form sender)
	If numArg > 0.0
		ZazSeatFurn = sender as ObjectReference
		ZazSeatTime = Utility.GetCurrentRealTime()
		If Phase >= 1 && Phase <= 2 && Furn == ZazSeatFurn
			Mode = 2
			Log("ZaZ SetFurniture: lock is now mod-owned (mode 2)")
		EndIf
	Else
		ZazSeatFurn = None
		If Phase == 1 || Phase == 2
			Release("zaz-setfurniture-none", None)
		EndIf
	EndIf
EndFunction

; ------------------------------------------------------------------------------------------------ release (the hook)
Bool Function Release(String reason, Actor releaser)
	If Phase == 0 || Phase == 3
		Return False
	EndIf
	Log("release: " + reason + " by " + releaser + " (phase " + Phase + ")")
	Token += 1	; any set-up still running bails out
	Bool wasLocked = (Phase == 2)
	Phase = 3	; keep-alive / watchdog / pose replays all check Phase == 2 -> stopped from here on
	UnregisterForUpdate()
	KeepAt = 0.0
	FinishRestore(reason, wasLocked)
	If releaser
		releaser.SendModEvent("x812zl_Released", reason, 1.0)
	Else
		PlayerRef.SendModEvent("x812zl_Released", reason, 0.0)
	EndIf
	Return True
EndFunction

Function FinishRestore(String reason, Bool moveToExit)
	ObjectReference f = Furn
	Bool ext = ExtHold
	If f && !ext
		f.BlockActivation(True)
	EndIf
	If ext && !ExtNoCallback
		ExtNotify(reason, JsonUtil.GetFloatValue(JsonFile, "ext_wait_s", 4.0))
	EndIf
	; never release under an open dialogue/menu (CTD SkyrimVR.exe+06E5BF9 seen with the Dialogue Menu)
	Int w = 0
	While Utility.IsInMenuMode() && w < 50
		Utility.WaitMenuMode(0.1)
		w += 1
	EndWhile
	x812zl_Cam.Dump("5-release-start(" + reason + ")", PlayerRef, f)
	If PlayerRef.GetSitState() != 0
		PlayerRef.MoveTo(PlayerRef)
		Int tries = 0
		While PlayerRef.GetSitState() != 0 && tries < 10
			Utility.Wait(0.1)
			tries += 1
		EndWhile
	EndIf
	String exitEv = ""
	If ext
		exitEv = ExtExit
	ElseIf EnterEv != "" && JsonUtil.GetIntValue(JsonFile, "release_exit", 1) == 1
		exitEv = JsonUtil.GetStringValue(JsonFile, "exit:" + EnterEv, "")
	EndIf
	LoopEv = ""
	LoopStarted = False
	x812zl_Cam.Unpin(PlayerRef, moveToExit, ExitX, ExitY, ExitZ, PinA, exitEv)
	MeshRelease(f)
	UnregisterForAllKeys()
	; ZaZ re-imposes its own control mask (gag / armbinder) after ours is gone
	zbfBondageShell zq = Game.GetFormFromFile(0x000137E6, "ZaZAnimationPack.esm") as zbfBondageShell
	Int zworn = 0
	If zq
		; ZaZ's player slot can keep a stale "pinned" flag (its PinActor call is skipped for the VR player) -> recompute
		zbfSlot ps = zq.FindSlot(PlayerRef)
		If ps && ps.GetFurniture() == None
			ps.UnPinActor(True)
		EndIf
		zq.ReapplyPlayerControls()
		zworn = zq.WornPlayerControlMask(PlayerRef)
	EndIf
	VerifyRelease(zworn, zq)
	Phase = 0
	Mode = 0
	Furn = None
	PoseEv = ""
	MeshKind = 0
	Rescuing = False
	If x812zl_Locked
		x812zl_Locked.SetValue(0.0)
	EndIf
	; furniture usable again ~1.5 s later, so the release press doesn't re-seat us
	If !ext
		UnblockFurn = f
		UnblockAt = Utility.GetCurrentRealTime() + 1.5
	EndIf
	ExtEnd(reason)
	StorageUtil.SetFloatValue(None, "x812zl.lastRelease", Utility.GetCurrentRealTime())
	RegisterForSingleUpdate(0.5)
	x812zl_Cam.Dump("6-release-done", PlayerRef, f)
EndFunction

; ~1 s after the release: anything still set (VRIK pin, VRFreeCam pin, controls another script took back) -> redo, twice max.
Function VerifyRelease(Int zworn, zbfBondageShell zq)
	Int target = x812zl_Cam.CtlTarget(StorageUtil.GetIntValue(None, "x812zl.rel.ctl", 255), StorageUtil.GetIntValue(None, "x812zl.base.ctl", 255), zworn)
	Int pass = 0
	While pass < 3
		Utility.Wait(1.0)
		Int now = x812zl_Cam.CtlNow()
		Int missing = Math.LogicalAnd(target, Math.LogicalXor(255, now))
		Float lp = VRIK.VrikGetSetting("lockPosition")
		Bool vfc = x812zl_Cam.IsPinned() || StorageUtil.GetIntValue(None, "VRFreeCam.Active", 0) == 1
		Int zmask = 0
		If zq
			zmask = zq.PlayerControlsFromSlot
		EndIf
		Log("release verify " + pass + ": controls " + now + " target " + target + " missing " + missing + " (zaz slot " + zmask + ", worn " + zworn + "), VRIK lockPosition " + lp + ", VRFreeCam pinned " + vfc)
		If missing == 0 && lp == 0.0 && !vfc
			Return
		EndIf
		If pass < 2
			PlayerRef.SetDontMove(False)
			Game.SetPlayerAIDriven(False)
			x812zl_Cam.UnpinVrik()
			If vfc
				VRFreeCam.UnlockInPlace(PlayerRef)
				StorageUtil.UnsetIntValue(None, "VRFreeCam.Active")
			EndIf
			x812zl_Cam.EnableCtl(missing)
			; tells "Enable is ignored" (a control layer / menu holds it) from "re-disabled later" (another script's loop)
			Log("release verify: re-enabled " + missing + " -> controls now " + x812zl_Cam.CtlNow())
		EndIf
		pass += 1
	EndWhile
	Log("release verify: still not clean after 2 retries (another mod is holding it)")
EndFunction

; Idempotent full reset, also with no lock and no snapshot.
Function Panic()
	Log("PANIC")
	Token += 1
	ObjectReference f = Furn
	Bool ext = ExtHold
	If ext && !ExtNoCallback
		ExtNotify("panic", 0.0)
	EndIf
	Phase = 3
	PlayerRef.SetDontMove(False)
	Game.SetPlayerAIDriven(False)
	x812zl_Cam.Unpin(PlayerRef, False, 0.0, 0.0, 0.0, 0.0)
	If f && !ext
		MeshRelease(f)
		f.BlockActivation(False)
	EndIf
	UnregisterForAllKeys()
	StorageUtil.UnsetIntValue(None, "VRFreeCam.Active")
	StorageUtil.UnsetIntValue(None, "x812zl.Owner")
	Game.EnablePlayerControls(True, True, True, True, True, True, True, True, 0)
	zbfBondageShell zq = Game.GetFormFromFile(0x000137E6, "ZaZAnimationPack.esm") as zbfBondageShell
	If zq
		zq.ReapplyPlayerControls()
	EndIf
	Phase = 0
	Mode = 0
	Furn = None
	PoseEv = ""
	LoopEv = ""
	LoopStarted = False
	Rescuing = False
	If x812zl_Locked
		x812zl_Locked.SetValue(0.0)
	EndIf
	ExtEnd("panic")
	Debug.Notification("ZaZ VR Lock: reset")
EndFunction

; ------------------------------------------------------------------------------------------------ rescue (call for help / timed / API)
Actor Function FindRescuer()
	Actor best = None
	Float bestD = 1000.0
	Float radius = JsonUtil.GetFloatValue(JsonFile, "npc_radius", 1000.0)
	Int i = 0
	While i < 12
		Actor a = Game.FindRandomActorFromRef(Furn, radius)
		If a && a != PlayerRef && !a.IsDead() && !a.IsHostileToActor(PlayerRef) && !a.IsInCombat() && !a.IsChild()
			Float d = a.GetDistance(Furn)
			If d < bestD || best == None
				best = a
				bestD = d
			EndIf
		EndIf
		i += 1
	EndWhile
	Return best
EndFunction

Function RequestRescue(Actor preferred)
	If Phase != 2 || Rescuing
		Return
	EndIf
	Actor r = preferred
	If r == None
		r = FindRescuer()
	EndIf
	If r == None
		Log("rescue: nobody in range")
		Debug.Notification("Nobody is near enough to hear you.")
		PlayerRef.SendModEvent("x812zl_RescueFailed", "nobody", 0.0)
		Return
	EndIf
	Rescuing = True
	Int my = Token
	Log("rescue: " + r + " is coming")
	r.SendModEvent("x812zl_RescueStarted", "", 0.0)
	Bool arrived = r.PathToReference(Furn, 0.6)
	If my != Token || Phase != 2
		Rescuing = False
		Return
	EndIf
	If !arrived
		Log("rescue: path failed, releasing anyway")
	EndIf
	Release("npc", r)
EndFunction


; ------------------------------------------------------------------------------------------------ live calibration
; Nudge the pin of the piece you are locked in, in the furniture's own frame (x right, y forward, z up, yaw degrees).
; Applied at once and saved per furniture base to SKSE/Plugins/StorageUtilData/x812zl/calibration.json.
Function Nudge(Float dx, Float dy, Float dz, Float da)
	If Phase != 2 || MarkerKey == ""
		Log("nudge ignored (not locked)")
		Return
	EndIf
	LocX += dx
	LocY += dy
	LocZ += dz
	LocA += da
	JsonUtil.AdjustFloatValue(LearnFile, "dx_" + MarkerKey, dx)
	JsonUtil.AdjustFloatValue(LearnFile, "dy_" + MarkerKey, dy)
	JsonUtil.AdjustFloatValue(LearnFile, "dz_" + MarkerKey, dz)
	JsonUtil.AdjustFloatValue(LearnFile, "da_" + MarkerKey, da)
	JsonUtil.Save(LearnFile)
	ComputePin()
	x812zl_Cam.Repin(PinX, PinY, PinZ, PinA)
	Log("NUDGE " + MarkerKey + " now local=" + LocX + "," + LocY + "," + LocZ + " yaw=" + LocA)
	Debug.Notification("ZaZ VR Lock: pin " + LocX as Int + " " + LocY as Int + " " + LocZ as Int + " / " + LocA as Int + " deg")
EndFunction

Function ClearCalibration()
	If MarkerKey != ""
		JsonUtil.UnsetFloatValue(LearnFile, "dx_" + MarkerKey)
		JsonUtil.UnsetFloatValue(LearnFile, "dy_" + MarkerKey)
		JsonUtil.UnsetFloatValue(LearnFile, "dz_" + MarkerKey)
		JsonUtil.UnsetFloatValue(LearnFile, "da_" + MarkerKey)
		JsonUtil.Save(LearnFile)
		Log("calibration cleared for " + MarkerKey)
	EndIf
EndFunction


; ------------------------------------------------------------------------------------------------ pose tester (update9)
; Try another furniture pose on the device you are locked in, no reload: the Enter event of any ZaZ furniture pose,
; e.g. "ZaZRSPP01_Enter". Its loop / exit come from the table. "" = back to the table pose. Not saved until KeepPose.
Function TryPose(String evName)
	If Phase != 2
		Log("trypose ignored (not locked)")
		Debug.Notification("ZaZ VR Lock: not locked")
		Return
	EndIf
	If evName == ""
		JsonUtil.UnsetStringValue(LearnFile, "pose_" + MarkerKey)
		evName = PoseFor(Furn)
	EndIf
	EnterEv = evName
	PoseEv = evName
	LoopEv = JsonUtil.GetStringValue(JsonFile, "loop:" + evName, "")
	LoopStarted = True
	LastDriven = -1
	ReplayPose()
	Log("TRYPOSE " + MarkerKey + ": " + EnterEv + " -> loop '" + LoopEv + "'")
	Debug.Notification("ZaZ VR Lock: pose " + EnterEv)
EndFunction

; Save the pose you are trying as this furniture type's pose (calibration.json, pose_<base>).
Function KeepPose()
	If Phase != 2 || MarkerKey == "" || EnterEv == ""
		Return
	EndIf
	JsonUtil.SetStringValue(LearnFile, "pose_" + MarkerKey, EnterEv)
	JsonUtil.Save(LearnFile)
	Log("KEEPPOSE " + MarkerKey + " = " + EnterEv)
	Debug.Notification("ZaZ VR Lock: saved pose " + EnterEv)
EndFunction

; ------------------------------------------------------------------------------------------------ pose keeper
; update8: the camera never touches the body. ApplyCam moves only the camera actor and puts the VRIK pin straight back;
; here we wait until the pin holds again. No Enter replay (it restarted the furniture chain over the running loop):
; once the loop is running only the loop idle is re-sent, with no reset to the default state.
Function PlaceCamera(String why)
	x812zl_Cam.ApplyCam(PlayerRef, PinX, PinY, PinZ, PinA, JsonUtil.GetFloatValue(JsonFile, "view_dist", 170.0))
	EnsurePin(Token, "camera " + why)
	String sent = "none"
	If LoopStarted && LoopEv != "" && (Phase == 1 || Phase == 2)
		Debug.SendAnimationEvent(PlayerRef, LoopEv)
		KeepAt = Utility.GetCurrentRealTime() + JsonUtil.GetFloatValue(JsonFile, "keepalive_s", 3.0)
		sent = LoopEv
	EndIf
	Log("camera placed (" + why + ", mode " + x812zl_Cam.CamMode() + ", view " + StorageUtil.GetIntValue(None, "x812zl.View", 0) + "), lock intact " + x812zl_Cam.LockIntact(PinX, PinY, PinA) + ", loop re-sent: " + sent)
	PoseMoved = False
	StillTicks = 0
EndFunction

; Re-pin until VRIK holds the full pin (position + rotation) for 3 checks in a row (0.1 s apart), 3 s max.
Bool Function EnsurePin(Int my, String why)
	Int ok = 0
	Int n = 0
	Int fixes = 0
	While ok < 5 && n < 40
		If my != Token
			Return False
		EndIf
		If x812zl_Cam.LockIntact(PinX, PinY, PinA)
			ok += 1
		Else
			If fixes < 3
				Log("pin (" + why + "): lock values reset (" + x812zl_Cam.LockDiag() + ") -> re-assert")
			EndIf
			ok = 0
			fixes += 1
			x812zl_Cam.Reassert(PinX, PinY, PinZ, PinA)
		EndIf
		Utility.Wait(0.1)
		n += 1
	EndWhile
	If fixes > 0 || ok < 5
		Log("pin (" + why + "): re-asserted " + fixes + "x, holding " + (ok >= 5))
	EndIf
	PinMiss = 0
	Return ok >= 5
EndFunction

Function NextView()
	If Phase != 2
		Return
	EndIf
	StorageUtil.SetIntValue(None, "x812zl.View", (StorageUtil.GetIntValue(None, "x812zl.View", 0) + 1) % 4)
	StorageUtil.SetIntValue(None, "x812zl.CamMode", 0)
	PlaceCamera("next view")
EndFunction

Function ToggleWalk()
	If Phase != 2
		Return
	EndIf
	StorageUtil.SetIntValue(None, "x812zl.CamMode", 1 - x812zl_Cam.CamMode())
	PlaceCamera("mode " + x812zl_Cam.CamMode())
EndFunction

Function OnViewGesture(String eventName, String strArg, Float numArg, Form sender)
	NextView()
EndFunction

Function OnWalkGesture(String eventName, String strArg, Float numArg, Form sender)
	ToggleWalk()
EndFunction

Function NoteGetUp()
	GetUps += 1
	LastGetUp = Utility.GetCurrentRealTime()
	If Phase == 2
		RePoseAt = LastGetUp + 0.5
	EndIf
EndFunction

Function RePose(String why)
	RePoseAt = 0.0
	PoseMoved = False
	StillTicks = 0
	If Phase != 2 || PoseEv == ""
		Return
	EndIf
	ReplayPose()
	If x812zl_Debug && x812zl_Debug.GetValue() > 0.0
		Log("re-pose (" + why + "): " + PoseEv)
	EndIf
EndFunction

Function OnReposeGesture(String eventName, String strArg, Float numArg, Form sender)
	RePose("gesture")
EndFunction


; Replay the pose from a clean graph, SexLab VR's RefreshActor order: default state, 0.1 s, then the animation event.
; An Enter event sent while the graph is in locomotion / another furniture state can be ignored; from the default state
; it always starts. Random-loop pieces: Enter first, then the chosen loop variant, as in the set-up.
Function ReplayPose()
	If PoseEv == ""
		Return
	EndIf
	LastFull = Utility.GetCurrentRealTime()
	Debug.SendAnimationEvent(PlayerRef, "IdleForceDefaultState")
	Utility.Wait(0.1)
	If x812zl_Debug && x812zl_Debug.GetValue() > 0.0
		Log("full pose replay: " + EnterEv + " -> " + LoopEv)
	EndIf
	If LoopEv != ""
		; Enter once (it is a one-shot transition clip), then straight into the cyclic loop idle
		Debug.SendAnimationEvent(PlayerRef, EnterEv)
		Utility.Wait(JsonUtil.GetFloatValue(JsonFile, "enter_s", 1.0))
		If Phase != 2 && Phase != 1
			Return	; released meanwhile: never re-send the loop after a release
		EndIf
		Debug.SendAnimationEvent(PlayerRef, LoopEv)
	Else
		If EnterEv != "" && EnterEv != PoseEv
			Debug.SendAnimationEvent(PlayerRef, EnterEv)
			Utility.Wait(0.8)
		EndIf
		Debug.SendAnimationEvent(PlayerRef, PoseEv)
	EndIf
	KeepAt = Utility.GetCurrentRealTime() + JsonUtil.GetFloatValue(JsonFile, "keepalive_s", 3.0)
EndFunction

; Keep-alive while locked: every keepalive_s re-send ONLY the loop idle (no reset, no Enter, so no visible re-entry;
; a loop event while already looping is a no-op/same-pose restart). If the graph shows the pose dropped
; (bAnimationDriven true -> false), do one full clean Enter->Loop replay, at most every 8 s.
Function KeepAlive(Float now)
	If LoopEv == "" || Phase != 2
		Return
	EndIf
	If x812zl_Cam.CamMode() == 1 && PlayerRef.GetAnimationVariableFloat("Speed") > 10.0
		Return	; walking the camera: the walk keeper replays the pose when it stops
	EndIf
	Int drv = 0
	If PlayerRef.GetAnimationVariableBool("bAnimationDriven")
		drv = 1
	EndIf
	If drv != LastDriven
		Log("keep-alive: bAnimationDriven " + LastDriven + " -> " + drv + " (" + LoopEv + ")")
		Bool dropped = LastDriven == 1 && drv == 0
		LastDriven = drv
		If dropped && JsonUtil.GetIntValue(JsonFile, "keep_on_drop", 1) == 1 && now - LastFull > 8.0
			Log("keep-alive: pose dropped -> full replay")
			ReplayPose()
			Return
		EndIf
	EndIf
	Float ka = JsonUtil.GetFloatValue(JsonFile, "keepalive_s", 3.0)
	If ExtHold && KeepIv > 0.0
		ka = KeepIv
	EndIf
	If ka > 0.0 && now >= KeepAt
		Debug.SendAnimationEvent(PlayerRef, LoopEv)
		KeepAt = now + ka
		If x812zl_Debug && x812zl_Debug.GetValue() > 0.0
			Log("keep-alive: " + LoopEv)
		EndIf
	EndIf
EndFunction


; ================================================================================================ external holds (update10)
; For framework adapters that seat the player with their own script (Devious Devices contraptions, ...).
;   1. ExtBegin(device, tag)      before the framework touches the player: claims the core, takes the snapshot
;   2. ExtLock(x, y, z, angle, loopEvent, exitEvent, keepAliveSeconds)   once the player is on the spot
;   3. ExtPlay(event, seconds)    play another idle for a while (struggle), the keep-alive waits;  ExtSetLoop(event)
;   4. ExtRelease(reason)         the framework is unlocking: ordered + verified restore, no callback
; Any OTHER release (x812zl.Release hook, rescue, self-release gesture, death, panic, load mid set-up) first sends
; ModEvent "x812zl_ExtRelease" (sender = device, strArg = reason) and waits up to ext_wait_s (4 s) for the
; framework's ack (ExtCleanupDone / ExtRelease), then restores camera, VRIK, hands and controls LAST and verifies.
; The core never activates the device.
Bool Function ExtBegin(ObjectReference anchor, String tag)
	If !Enabled() || anchor == None
		Return False
	EndIf
	If Phase != 0
		Log("ExtBegin(" + tag + ") refused, phase " + Phase)
		Return False
	EndIf
	Phase = 1
	Token += 1
	If StorageUtil.GetIntValue(None, "VRFreeCam.Active", 0) == 1 && StorageUtil.GetIntValue(None, "x812zl.Owner", 0) != 1
		Log("ExtBegin(" + tag + ") refused: another VR camera owner holds the player")
		Phase = 0
		Return False
	EndIf
	Furn = anchor
	ExtRef = anchor
	ExtTag = tag
	ExtHold = True
	ExtNoCallback = False
	ExtExit = ""
	KeepIv = 0.0
	Mode = 2
	PoseEv = ""
	EnterEv = ""
	LoopEv = ""
	LoopStarted = False
	MeshKind = 0
	LidClosedByUs = False
	MarkerKey = ""
	x812zl_Cam.Snapshot()
	Log("ext begin " + tag + " on " + anchor)
	Return True
EndFunction

Bool Function ExtLock(Float x, Float y, Float z, Float ang, String evLoop, String exitEv, Float keepSec)
	If Phase != 1 || !ExtHold || Furn == None
		Log("ExtLock refused (phase " + Phase + ", ext " + ExtHold + ")")
		Return False
	EndIf
	Int my = Token
	ObjectReference f = Furn
	FurnX = f.GetPositionX()
	FurnY = f.GetPositionY()
	FurnZ = f.GetPositionZ()
	FurnA = f.GetAngleZ()
	LocX = x812zl_Cam.WorldToLocalX(FurnX, FurnY, FurnA, x, y)
	LocY = x812zl_Cam.WorldToLocalY(FurnX, FurnY, FurnA, x, y)
	LocZ = z - FurnZ
	LocA = ang - FurnA
	MarkerKey = "ext_" + ExtTag + "_" + f.GetBaseObject().GetName()
	LocX += JsonUtil.GetFloatValue(LearnFile, "dx_" + MarkerKey, 0.0)
	LocY += JsonUtil.GetFloatValue(LearnFile, "dy_" + MarkerKey, 0.0)
	LocZ += JsonUtil.GetFloatValue(LearnFile, "dz_" + MarkerKey, 0.0)
	LocA += JsonUtil.GetFloatValue(LearnFile, "da_" + MarkerKey, 0.0)
	ComputePin()
	ExtExit = exitEv
	KeepIv = keepSec
	EnterEv = evLoop
	PoseEv = evLoop
	LoopEv = evLoop
	LastDriven = -1
	Log("ext lock " + ExtTag + " at " + PinX + "," + PinY + "," + PinZ + " / " + PinA + " loop '" + evLoop + "' keep " + keepSec + " s")
	PlayerRef.SetDontMove(True)
	PlayerRef.SetPosition(PinX, PinY, PinZ)
	PlayerRef.SetAngle(0.0, 0.0, PinA)
	Utility.Wait(0.3)
	If my != Token
		Return False
	EndIf
	If evLoop != ""
		Debug.SendAnimationEvent(PlayerRef, "IdleForceDefaultState")
		Utility.Wait(0.1)
		Debug.SendAnimationEvent(PlayerRef, evLoop)
	EndIf
	LoopStarted = True
	x812zl_Cam.Pin(PlayerRef, PinX, PinY, PinZ, PinA)
	EnsurePin(my, "ext lock")
	If my != Token
		Return False
	EndIf
	PlaceCamera("ext lock")
	Phase = 2
	LockedAt = Utility.GetCurrentRealTime()
	RescueAt = 0.0
	If x812zl_RescueMinutes && x812zl_RescueMinutes.GetValue() > 0.0
		RescueAt = LockedAt + x812zl_RescueMinutes.GetValue() * 60.0
	EndIf
	If x812zl_Locked
		x812zl_Locked.SetValue(1.0)
	EndIf
	x812zl_Cam.Dump("2-ext-locked", PlayerRef, f)
	f.SendModEvent("x812zl_Locked", PoseEv, Mode as Float)
	RegisterForSingleUpdate(0.25)
	Return True
EndFunction

; another idle for a while (e.g. a struggle); the keep-alive resumes the loop after holdSec
Function ExtPlay(String ev, Float holdSec)
	If Phase != 2 || !ExtHold || ev == ""
		Return
	EndIf
	Debug.SendAnimationEvent(PlayerRef, ev)
	KeepAt = Utility.GetCurrentRealTime() + holdSec
	LastFull = Utility.GetCurrentRealTime() + holdSec	; no "pose dropped" replay over it
	If x812zl_Debug && x812zl_Debug.GetValue() > 0.0
		Log("ext play " + ev + " for " + holdSec + " s")
	EndIf
EndFunction

; switch the held loop (the framework picked another pose); sent at once
Function ExtSetLoop(String ev)
	If Phase != 2 || !ExtHold || ev == ""
		Return
	EndIf
	EnterEv = ev
	PoseEv = ev
	LoopEv = ev
	Debug.SendAnimationEvent(PlayerRef, ev)
	Float ka = KeepIv
	If ka <= 0.0
		ka = JsonUtil.GetFloatValue(JsonFile, "keepalive_s", 3.0)
	EndIf
	KeepAt = Utility.GetCurrentRealTime() + ka
	Log("ext loop -> " + ev)
EndFunction

; the framework is unlocking: restore the player (ordered + verified), no callback to the device
Bool Function ExtRelease(String reason)
	If !ExtHold
		Return False
	EndIf
	If Phase == 3
		ExtAck = True		; called from the framework's cleanup during a core-started release
		Return True
	EndIf
	ExtNoCallback = True
	If Phase == 1
		Token += 1
		Phase = 3
		FinishRestore(reason, False)
		Return True
	EndIf
	Return Release(reason, None)
EndFunction

Bool Function IsExtHeld(ObjectReference anchor)
	Return ExtHold && Phase >= 1 && Phase <= 2 && (anchor == None || ExtRef == anchor)
EndFunction

; called at the end of every restore: hand the device back to the framework, unless it asked for the release itself
Function ExtEnd(String reason)
	If !ExtHold
		Return
	EndIf
	ExtHold = False
	ExtRef = None
	ExtTag = ""
	ExtExit = ""
	ExtNoCallback = False
	ExtAck = False
	ExtSelfMode = 1
	KeepIv = 0.0
	Log("ext hold ended (" + reason + ")")
EndFunction

; core-started release of an external hold: tell the framework to clean up its device state (sender = the device,
; strArg = reason), wait for its ack (ExtCleanupDone or ExtRelease), then the caller restores camera + controls last.
Function ExtNotify(String reason, Float waitSec)
	ObjectReference r = ExtRef
	If r == None
		Return
	EndIf
	ExtAck = False
	Log("ext release (" + reason + ") -> x812zl_ExtRelease to " + r + ", waiting up to " + waitSec + " s")
	r.SendModEvent("x812zl_ExtRelease", reason, 0.0)
	Int n = 0
	While !ExtAck && n < (waitSec * 10.0) as Int
		Utility.Wait(0.1)
		n += 1
	EndWhile
	Log("ext release: framework ack " + ExtAck + " after " + (n as Float / 10.0) + " s")
EndFunction

Function ExtCleanupDone()
	ExtAck = True
EndFunction

; 1 (default) = self-release gesture releases for sure; 0 = sends x812zl_ExtSelfRelease to the device instead
Function ExtSetSelfRelease(Int m)
	ExtSelfMode = m
EndFunction
