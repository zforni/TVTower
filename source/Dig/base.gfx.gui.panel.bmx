Rem
	===========================================================
	GUI Panel
	===========================================================
End Rem
SuperStrict
Import "base.gfx.gui.backgroundbox.bmx"
Import "base.gfx.gui.textbox.bmx"




Type TGUIPanel Extends TGUIObject
	Field guiBackground:TGUIBackgroundBox = Null
	Field guiTextBox:TGUITextBox
	Field _defaultValueColor:TColor


	Method Create:TGUIPanel(pos:TPoint, dimension:TPoint, limitState:String = "")
		Super.CreateBase(pos, dimension, limitState)

		GUIManager.Add(Self)
		Return Self
	End Method


	Method GetPadding:TRectangle()
		'if no manual padding was setup - use sprite padding
		if not _padding and guiBackground then return guiBackground.GetPadding()
		Return Super.GetPadding()
	End Method


	Method Resize:Int(w:Float=Null,h:Float=Null)
		'resize self
		If w Then rect.dimension.setX(w) Else w = rect.GetW()
		If h Then rect.dimension.setY(h) Else h = rect.GetH()

		'move background
		If guiBackground Then guiBackground.resize(w,h)
		'move textbox
		If guiTextBox
			'text box is aligned to padding - so can start at "0,0"
			'-> no additional offset
			guiTextBox.rect.position.SetXY(0,0)

			'getContentScreenWidth takes GetPadding into consideration
			'which considers guiBackground already - so no need to distinguish
			guiTextBox.resize(GetContentScreenWidth(),GetContentScreenHeight())
		EndIf
	End Method


	'override to also check  children
	Method IsAppearanceChanged:int()
		if guiBackground and guiBackground.isAppearanceChanged() then return TRUE
		if guiTextBox and guiTextBox.isAppearanceChanged() then return TRUE

		return Super.isAppearanceChanged()
	End Method


	'override default to handle image changes
	Method onStatusAppearanceChange:int()
		'if background changed - or textbox, we to have resize and
		'reposition accordingly
		resize()
	End Method


	Method SetBackground(obj:TGUIBackgroundBox=Null)
		'reset to nothing?
		If Not obj
			If guiBackground
				removeChild(guiBackground)
				guiBackground.remove()
				guiBackground = Null
			EndIf
		Else
			guiBackground = obj
			'set background to ignore parental padding (so it starts at 0,0)
			guiBackground.SetOption(GUI_OBJECT_IGNORE_PARENTPADDING, True)
			'set background to to be on same level than parent
			guiBackground.SetZIndex(-1)

			addChild(obj) 'manage it by our own
		EndIf
	End Method


	'override default to return textbox value
	Method GetValue:String()
		If guiTextBox Then Return guiTextBox.GetValue()
		Return ""
	End Method


	'override default to set textbox value
	Method SetValue(value:String="")
		If value=""
			If guiTextBox
				guiTextBox.remove()
				guiTextBox = Null
			EndIf
		Else
			Local padding:TRectangle = new TRectangle.Init(0,0,0,0)
			'read padding from background

			if guiBackground then padding = guiBackground.GetSprite().GetNinePatchContentBorder()

			if not guiTextBox
				guiTextBox = New TGUITextBox.Create(new TPoint.Init(0,0), new TPoint.Init(50,50), value, "")
			else
				guiTextBox.SetValue(value)
			endif

			If _defaultValueColor
				guiTextBox.SetValueColor(_defaultValueColor)
			Else
				guiTextBox.SetValueColor(TColor.clWhite)
			EndIf
			guiTextBox.SetValueAlignment("CENTER", "CENTER")
			guiTextBox.SetAutoAdjustHeight(True)
			'we take care of the text box
			addChild(guiTextBox)
		EndIf

		'to resize textbox accordingly
		Resize()
	End Method


	Method disableBackground()
		If guiBackground Then guiBackground.disable()
	End Method


	Method enableBackground()
		If guiBackground Then guiBackground.enable()
	End Method


	Method Update()
		'as we do not call "super.Update()" - we handle this manually
		'if appearance changed since last update tick: inform widget
		If isAppearanceChanged()
			onStatusAppearanceChange()
			SetAppearanceChanged(false)
		Endif


		'Super.Update()
'		UpdateChildren()
	End Method


	Method Draw()
'		DrawChildren()
	End Method
End Type
