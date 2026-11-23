Scriptname x812zl_Hook Hidden
{ZaZ VR Lock - called from the patched zbfSlot.pex (stock ZaZ 8 zbfSlot with 5 call sites redirected here,
no recompile of ZaZ's source). For NPCs, or when the patch is disabled / its plugin is missing, every function does
exactly what stock ZaZ did.}

Bool Function Active() global
	GlobalVariable g = Game.GetFormFromFile(0x00000800, "ZazVRLock.esp") as GlobalVariable
	Return g != None && g.GetValue() > 0.0
EndFunction

Bool Function IsVRPlayer(Actor a) global
	Return a != None && a == Game.GetPlayer() && Active()
EndFunction

; zbfSlot.SetFurniture: stock = ActorRef.SetVehicle(akFurniture). Player: no SetVehicle (spins the HMD); tell the core
; that a mod seated (furniture) or released (None) the player.
Function SlotSetVehicle(Actor a, ObjectReference akFurniture) global
	If !IsVRPlayer(a)
		a.SetVehicle(akFurniture)
		Return
	EndIf
	If akFurniture
		akFurniture.SendModEvent("x812zl_ZazSeat", "seat", 1.0)
	Else
		a.SendModEvent("x812zl_ZazSeat", "release", 0.0)
	EndIf
EndFunction

; zbfSlot.ApplyAllEffects: stock = ActorRef.SetVehicle(None) every refresh. Player: skip (no event).
Function SlotClearVehicle(Actor a, ObjectReference akNone) global
	If !IsVRPlayer(a)
		a.SetVehicle(akNone)
	EndIf
EndFunction

; zbfSlot.PinActor / UnPinActor: stock = zbf.PinActor(ActorRef) (SetVehicle on zbf.MarkerPin). Player: skip.
Function SlotPinActor(zbfBondageShell zbf, Actor a) global
	If !IsVRPlayer(a)
		zbf.PinActor(a)
	EndIf
EndFunction

Function SlotUnPinActor(zbfBondageShell zbf, Actor a) global
	If !IsVRPlayer(a)
		zbf.UnPinActor(a)
	EndIf
EndFunction

; zbfSlot.ApplyAnimEffects prologue: True = skip ZaZ's idle refresh, because the player is posed out of the seat by the
; furniture's Enter animation and any idle ZaZ plays (still / arm / reset) would overwrite that pose.
Bool Function SlotHoldAnim(Actor a) global
	If !IsVRPlayer(a)
		Return False
	EndIf
	x812zl_Core c = Game.GetFormFromFile(0x00000805, "ZazVRLock.esp") as x812zl_Core
	Return c != None && c.Phase >= 1 && c.Phase <= 2
EndFunction
