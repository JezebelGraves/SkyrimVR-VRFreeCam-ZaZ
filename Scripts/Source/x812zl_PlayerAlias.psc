Scriptname x812zl_PlayerAlias extends ReferenceAlias
{ZaZ VR Lock - player alias: forwards OnSit / OnPlayerLoadGame to the core quest.}

x812zl_Core Function Core()
	Return GetOwningQuest() as x812zl_Core
EndFunction

Event OnSit(ObjectReference akFurniture)
	Core().HandleSit(akFurniture)
EndEvent

Event OnGetUp(ObjectReference akFurniture)
	; our own stand-up during set-up fires this too, so it is only logged; the watchdog handles real exits
	x812zl_Core c = Core()
	If c.Phase != 0
		Debug.Trace("x812zl: OnGetUp " + akFurniture + " (phase " + c.Phase + ")")
		c.NoteGetUp()
	EndIf
EndEvent

Event OnPlayerLoadGame()
	Core().OnGameLoad()
EndEvent
