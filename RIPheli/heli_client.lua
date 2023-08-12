-- FiveM Heli Cam by mraes, version 1.3 (2017-06-12)
-- Modified by rjross2013 (2017-06-23)
-- Further modified by Loque (2017-08-15) with credits to the following for tips gleaned from their scripts: Guadmaz's Simple Police Searchlight, devilkkw's Speed Camera, nynjardin's Simple Outlaw Alert and IllidanS4's FiveM Entity Iterators.

-- Further modified by Ripper with addition of street names and removal of vehicle locking as per IG + inclusion of working spotlight
	-- Removed rappel as TaskRappelFromHeli doesn't work reliably and causes people to ragdoll off the rope.
	-- Temporarily removed spotlights

-- Config
local fov_max = 80.0
local fov_min = 5.0 -- max zoom level (smaller fov is more zoom)
local zoomspeed = 3.0 -- camera zoom speed
local speed_lr = 6.0 -- speed by which the camera pans left-right 
local speed_ud = 6.0 -- speed by which the camera pans up-down
local toggle_helicam = 51 -- control id of the button by which to toggle the helicam mode. Default: INPUT_CONTEXT 		(E)
local toggle_vision = 25 -- control id to toggle vision mode. Default: INPUT_AIM 										(Right mouse btn)
local toggle_display = 44 -- control id to toggle vehicle info display. Default: INPUT_COVER							(Q)
local streetview_key = 313 -- control id to toggle street view text. Default: INPUT_VEH_NEXT_RADIO						(])
local maxtargetdistance = 600 -- max distance at which target lock is maintained
local speed_measure = "Km/h" -- default unit to measure vehicle speed but can be changed to "MPH". Use either exact string, "Km/h" or "MPH", or else functions break.
local polair = {"polmav", "buzzard", "buzzard2", "frogger", "frogger2", "aw109"}

-- Script starts here
local target_vehicle = nil
local streetrender = false
local vehicle_display = 0 -- 0 is default full vehicle info display with speed/model/plate, 1 is model/plate, 2 turns off display
local helicam = false
local fov = (fov_max+fov_min)*0.5
local vision_state = 0 -- 0 is normal, 1 is nightmode, ~2 is thermal vision~ (removed thermal vision - Ripper)

Citizen.CreateThread(function() -- Register ped decorators used to pass some variables from heli pilot to other players (variable settings: 1=false, 2=true)
	while true do
	Citizen.Wait(0)
		if NetworkIsSessionStarted() then
			DecorRegister("SpotvectorX", 3) -- For direction of manual spotlight
			DecorRegister("SpotvectorY", 3)
			DecorRegister("SpotvectorZ", 3)
			DecorRegister("Target", 3) -- Backup method of target ID
			return
		end
	end
end)

Citizen.CreateThread(function()
	while true do
        Citizen.Wait(0)
		if IsPlayerInPolAir() then
			local lPed = PlayerPedId()
			local heli = GetVehiclePedIsIn(lPed)
			
			if IsHeliHighEnough(heli) then
				if IsControlJustPressed(0, toggle_helicam) then -- Toggle Helicam
					PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
					helicam = true
				end
			end
			

			if IsControlJustPressed(0, toggle_display) and GetPedInVehicleSeat(heli, -1) == lPed then 
				ChangeDisplay()
			end

		end
		
		if helicam then
			SetTimecycleModifier("heliGunCam")
			SetTimecycleModifierStrength(0.3)
			local scaleform = RequestScaleformMovie("HELI_CAM")
			while not HasScaleformMovieLoaded(scaleform) do
				Citizen.Wait(0)
			end
			local lPed = PlayerPedId()
			local heli = GetVehiclePedIsIn(lPed)
			local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
			AttachCamToEntity(cam, heli, 0.0,0.0,-1.5, true)
			SetCamRot(cam, 0.0,0.0,GetEntityHeading(heli))
			SetCamFov(cam, fov)
			RenderScriptCams(true, false, 0, 1, 0)
			PushScaleformMovieFunction(scaleform, "SET_CAM_LOGO")
			PushScaleformMovieFunctionParameterInt(0) -- 0 for nothing, 1 for LSPD logo
			PopScaleformMovieFunctionVoid()
			while helicam and not IsEntityDead(lPed) and (GetVehiclePedIsIn(lPed) == heli) and IsHeliHighEnough(heli) do
				if IsControlJustPressed(0, toggle_helicam) then -- Toggle Helicam
					PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
					helicam = false
				end

				if IsControlJustPressed(0, toggle_vision) then
					PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
					ChangeVision()
				end


				if IsControlJustPressed(0, toggle_display) then 
					ChangeDisplay()
				end

				if locked_on_vehicle then
					--removed
				else
					local zoomvalue = (1.0/(fov_max-fov_min))*(fov-fov_min)
					CheckInputRotation(cam, zoomvalue)
					local vehicle_detected = GetVehicleInView(cam)
					if DoesEntityExist(vehicle_detected) then
						RenderVehicleInfo(vehicle_detected)
					end
				end

				HandleZoom(cam)
				HideHUDThisFrame()
				PushScaleformMovieFunction(scaleform, "SET_ALT_FOV_HEADING")
				PushScaleformMovieFunctionParameterFloat(GetEntityCoords(heli).z)
				PushScaleformMovieFunctionParameterFloat(zoomvalue)
				PushScaleformMovieFunctionParameterFloat(GetCamRot(cam, 2).z)
				PopScaleformMovieFunctionVoid()
				DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)
				Citizen.Wait(0)

				------------------------------ street render
				if IsControlJustPressed(0, streetview_key) then
					if not streetrender then
						streetrender = true
					else
						streetrender = false
					end
				end

				if streetrender then
					for _,streetdata in pairs(Streets.Data) do
						local plyCoords = GetEntityCoords(PlayerPedId(), 0)
						distance = GetDistanceBetweenCoords(streetdata.x, streetdata.y, streetdata.z, plyCoords['x'], plyCoords['y'], plyCoords['z'], true)
				
						if distance < 450 then
							render3dtext(streetdata)
						end
					end
				end

				------------------------------ street render


			end

			helicam = false
			ClearTimecycleModifier()
			fov = (fov_max+fov_min)*0.5 -- reset to starting zoom level
			RenderScriptCams(false, false, 0, 1, 0) -- Return to gameplay camera
			SetScaleformMovieAsNoLongerNeeded(scaleform) -- Cleanly release the scaleform
			DestroyCam(cam, false)
			SetNightvision(false)
			SetSeethrough(false)
		end
	end
end)


function IsPlayerInPolAir()
    local lPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(lPed)
    for _, v in pairs(polair) do
		v = GetHashKey(v)
		if IsVehicleModel(vehicle, v) then
        	return IsVehicleModel(vehicle, v)
		end
    end
end


function IsHeliHighEnough(heli)
	return GetEntityHeightAboveGround(heli) > 1.5
end

function ChangeVision()
	if vision_state == 0 then
		SetNightvision(true)
		vision_state = 1
	elseif vision_state == 1 then
		SetNightvision(false)
		SetSeethrough(true)
		vision_state = 2
	else
		SetSeethrough(false)
		vision_state = 0
	end
end

function ChangeDisplay()
	if vehicle_display == 0 then
		vehicle_display = 1
	elseif vehicle_display == 1 then
		vehicle_display = 2
	else
		vehicle_display = 0
	end
end

function HideHUDThisFrame()
	HideHelpTextThisFrame()
	HideHudAndRadarThisFrame()
	HideHudComponentThisFrame(19) -- weapon wheel
	HideHudComponentThisFrame(1) -- Wanted Stars
	HideHudComponentThisFrame(2) -- Weapon icon
	HideHudComponentThisFrame(3) -- Cash
	HideHudComponentThisFrame(4) -- MP CASH
	HideHudComponentThisFrame(13) -- Cash Change
	HideHudComponentThisFrame(11) -- Floating Help Text
	HideHudComponentThisFrame(12) -- more floating help text
	HideHudComponentThisFrame(15) -- Subtitle Text
	HideHudComponentThisFrame(18) -- Game Stream
end

function CheckInputRotation(cam, zoomvalue)
	local rightAxisX = GetDisabledControlNormal(0, 220)
	local rightAxisY = GetDisabledControlNormal(0, 221)
	local rotation = GetCamRot(cam, 2)
	if rightAxisX ~= 0.0 or rightAxisY ~= 0.0 then
		new_z = rotation.z + rightAxisX*-1.0*(speed_ud)*(zoomvalue+0.1)
		new_x = math.max(math.min(20.0, rotation.x + rightAxisY*-1.0*(speed_lr)*(zoomvalue+0.1)), -89.5) -- Clamping at top (cant see top of heli) and at bottom (doesn't glitch out in -90deg)
		SetCamRot(cam, new_x, 0.0, new_z, 2)
	end
end

function HandleZoom(cam)
	if IsControlJustPressed(0,241) then -- Scrollup
		fov = math.max(fov - zoomspeed, fov_min)
	end
	if IsControlJustPressed(0,242) then
		fov = math.min(fov + zoomspeed, fov_max) -- ScrollDown		
	end
	local current_fov = GetCamFov(cam)
	if math.abs(fov-current_fov) < 0.1 then -- the difference is too small, just set the value directly to avoid unneeded updates to FOV of order 10^-5
		fov = current_fov
	end
	SetCamFov(cam, current_fov + (fov - current_fov)*0.05) -- Smoothing of camera zoom
end

function GetVehicleInView(cam)
	local coords = GetCamCoord(cam)
	local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
	--DrawLine(coords, coords+(forward_vector*100.0), 255,0,0,255) -- debug line to show LOS of cam
	local rayhandle = CastRayPointToPoint(coords, coords+(forward_vector*500.0), 10, GetVehiclePedIsIn(PlayerPedId()), 0)
	local _, _, _, _, entityHit = GetRaycastResult(rayhandle)
	if entityHit>0 and IsEntityAVehicle(entityHit) then
		return entityHit
	else
		return nil
	end
end

function RenderVehicleInfo(vehicle)
	if DoesEntityExist(vehicle) then
		local model = GetEntityModel(vehicle)
		local vehname = GetLabelText(GetDisplayNameFromVehicleModel(model))
		local licenseplate = GetVehicleNumberPlateText(vehicle)
		if speed_measure == "MPH" then
			vehspeed = GetEntitySpeed(vehicle)*2.236936
		else
			vehspeed = GetEntitySpeed(vehicle)*3.6
		end
		SetTextFont(0)
		SetTextProportional(1)
		if vehicle_display == 0 then
			SetTextScale(0.0, 0.49)
		elseif vehicle_display == 1 then
			SetTextScale(0.0, 0.55)
		end
		SetTextColour(255, 255, 255, 255)
		SetTextDropshadow(0, 0, 0, 0, 255)
		SetTextEdge(1, 0, 0, 0, 255)
		SetTextDropShadow()
		SetTextOutline()
		SetTextEntry("STRING")
		if vehicle_display == 0 then
			AddTextComponentString("Speed: " .. math.ceil(vehspeed) .. " " .. speed_measure .. "\nModel: " .. vehname .. "\nPlate: " .. licenseplate)
		elseif vehicle_display == 1 then
			AddTextComponentString("Model: " .. vehname .. "\nPlate: " .. licenseplate)
		end
		DrawText(0.45, 0.9)
	end
end

------------------drawtext

function render3dtext(streetdata)
	_, screenX, screenY = GetScreenCoordFromWorldCoord(streetdata.x, streetdata.y, streetdata.z)

	SetTextFont(0)
	SetTextScale(0.20, 0.20)
	SetTextProportional(false)
	SetTextColour(255, 255, 255, 255)
	SetTextDropshadow(10, 0, 0, 0, 255)
	SetTextEdge(1, 0, 0, 0, 255)
	SetTextDropShadow()
	SetTextOutline()
	SetTextEntry("STRING")
	AddTextComponentString(streetdata.name)
	DrawText(screenX, screenY)
end

--------------------findrawtext

function RotAnglesToVec(rot) -- input vector3
	local z = math.rad(rot.z)
	local x = math.rad(rot.x)
	local num = math.abs(math.cos(x))
	return vector3(-math.sin(z)*num, math.cos(z)*num, math.sin(x))
end

-- Following two functions from IllidanS4's entity enuerator script:  https://gist.github.com/IllidanS4/9865ed17f60576425369fc1da70259b2
local entityEnumerator = {
  __gc = function(enum)
    if enum.destructor and enum.handle then
      enum.destructor(enum.handle)
    end
    enum.destructor = nil
    enum.handle = nil
  end
}

local function EnumerateEntities(initFunc, moveFunc, disposeFunc)
  return coroutine.wrap(function()
    local iter, id = initFunc()
    if not id or id == 0 then
      disposeFunc(iter)
      return
    end
    
    local enum = {handle = iter, destructor = disposeFunc}
    setmetatable(enum, entityEnumerator)
    
    local next = true
    repeat
      coroutine.yield(id)
      next, id = moveFunc(iter)
    until not next
    
    enum.destructor, enum.handle = nil, nil
    disposeFunc(iter)
  end)
end

function EnumerateVehicles()
  return EnumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

function FindVehicleByPlate(plate) -- Search existing vehicles enumerated above for target plate and return the matching vehicle
	for vehicle in EnumerateVehicles() do
		if GetVehicleNumberPlateText(vehicle) == plate then
			return vehicle
		end
	end
end
